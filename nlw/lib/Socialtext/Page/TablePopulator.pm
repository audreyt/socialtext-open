package Socialtext::Page::TablePopulator;
# @COPYRIGHT@
use 5.12.0;
use warnings;

use Socialtext::Account;
use Socialtext::Cache;
use Socialtext::Workspace;
use Socialtext::Paths;
use Socialtext::Hub;
use Socialtext::User;
use Socialtext::File;
use Socialtext::Encode;
use Socialtext::Page::Legacy;
use Socialtext::PageRevision;
use Socialtext::String;
use Socialtext::Timer qw/time_scope/;
use Socialtext::SQL qw(get_dbh :exec sql_txn sql_ensure_temp);
use Socialtext::IntSet;

use Carp;
use Email::Valid;
use Fatal qw/opendir closedir chdir open/;
use Cwd   qw/getcwd abs_path/;
use DateTime;
use Try::Tiny;
use List::MoreUtils qw/any all/;
use Scalar::Util qw/looks_like_number/;

our $Noisy = 1;

sub new {
    my $class = shift;
    my %opts  = @_;
    die "workspace is mandatory!" unless $opts{workspace_name};

    my $self = \%opts;
    $self->{pages_with_default_editor} = [];
    $self->{attachments_with_default_editor} = [];
    bless $self, $class;

    my $ws = Socialtext::Workspace->new(name => $opts{workspace_name});
    croak "No such workspace $opts{workspace_name}\n"
        unless $ws;
    $self->{workspace} = $ws;
    $self->{workspace_id} = $ws->workspace_id;

    croak "data_dir is a required option" unless $self->{data_dir};
    croak "No such directory $self->{data_dir}"
        unless -d $self->{data_dir};

    $self->{old_name} ||= $self->{workspace_name};
    $self->{workspace_data_dir} = "$self->{data_dir}/data/$self->{old_name}";
    croak "No such workspace directory $self->{workspace_data_dir}"
        unless -d $self->{workspace_data_dir};
    $self->{workspace_plugin_dir}
        = "$self->{data_dir}/plugin/$self->{old_name}";
    $self->{workspace_user_dir}
        = "$self->{data_dir}/user/$self->{old_name}";

    return $self;
}

sub populate {
    my $self = shift;
    my %opts = @_;
    my $workspace = $self->{workspace};
    my $workspace_name = $self->{workspace_name};
    my $workspace_id = $self->{workspace_id};

    my $old_cwd = getcwd();
    my $hub = $self->{hub}
        = Socialtext::Hub->new( current_workspace => $workspace );
    my $workspace_dir = $self->{workspace_data_dir};
    chdir $workspace_dir;

    try { sql_txn {
        # Assume a "dirty" workspace environment where we'll be overwriting
        # certain objects.  We need to consider page-table entries, page
        # revisions, page attachments, page tags and finally breadcrumbs

        # Track pages so we know which ones to purge.  It's important not to
        # delete pages so that we don't get unwanted ON DELETE CASCADE
        # effects.
        sql_ensure_temp(t_page =>
            q{ page_id text },
            q{CREATE INDEX t_page_id_ix ON t_page (page_id)}
        );
        sql_execute(q{
            INSERT INTO t_page
            SELECT page_id FROM page WHERE workspace_id = ?
        }, $workspace_id);

        # Don't delete page revs so we can avoid having to re-insert them.
        # Revs only ever get added to a page unless a workspace or page
        # purge happens.  Revs don't have a FK into page, so it's ok to
        # clean these up as a final step in the workspace population.
        1; # no-op for page revs

        # Save attachment_ids so we can avoid having to re-upload attachment
        # blobs.  Since attachments can be deleted (hidden) or purged, it's
        # safest to start with a clean page_attachments table and then
        # re-insert the rows.  We'll clean dangling uploads later.
        sql_ensure_temp(t_attachments => q{
            id text,
            attachment_id bigint,
            page_id text
        }, q{CREATE INDEX t_att_id ON t_attachments (page_id,id)});
        sql_execute(q{
            INSERT INTO t_attachments
            SELECT id, attachment_id, page_id
              FROM page_attachment
              WHERE workspace_id = ?
        }, $workspace_id);
        sql_execute(q{
            DELETE FROM page_attachment WHERE workspace_id = ?
        }, $workspace_id);

        # Completely overwrite breadcrumbs every time (since the files
        # have no timestamp information, there's no way to merge the
        # existing and imported lists).
        sql_execute(q{
            DELETE FROM breadcrumb WHERE workspace_id = ?
        }, $workspace_id);

        # Grab all the Pages in the Workspace, figure out which ones we need
        # to add to the DB, then add them all.
        opendir(my $dfh, $workspace_dir);
        my @pages;
        my @page_tags;
      PAGE:
        while (my $dir = readdir($dfh)) {
            next PAGE unless -d $dir;
            next PAGE if $dir =~ m/^\./;

            # Ignore really old pages that have invalid page_ids
            next PAGE unless Socialtext::Encode::is_valid_utf8($dir);

            # Fix up relative links in the filesystem
            next PAGE unless try { fix_relative_page_link($dir); 1 }
            catch { my $err = format_err($_); warn "Fixing relative link: $err\n"; 0 };

            # Get all the data we want on a page

            my $page = try { $self->load_page_metadata($dir) }
            catch {
                my $err = format_err($_);
                warn "Populating $workspace_name, skipping $dir: $err\n";
                undef;
            };
            next PAGE unless $page;

            # if we get this far, the page wasn't purged in the datadir

            try { $self->load_page_attachments($page) }
            catch {
                my $err = format_err($_);
                warn "Populating $workspace_name attachments: $err\n";
            };

            try { sql_txn { $self->insert_or_update_page($page) } }
            catch {
                my $err = format_err($_);
                warn "Updating $workspace_name ".
                     "page $page->{page_id}: $err";
            };
        }
        closedir($dfh);

        $self->load_breadcrumbs();

        # clean up any un-referenced uploads (for when attchments got purged
        # between populations)
        Socialtext::JobCreator->tidy_uploads();

        # clean up any un-referenced page_revisions (i.e. pages that have been
        # purged)
        sql_execute(q{
            DELETE FROM page_revision
             WHERE workspace_id = $1
               AND page_id NOT IN (
                SELECT page_id FROM page WHERE workspace_id = $1
               )
        }, $workspace_id);

        # clean up purged pages; anything left in t_page is a candidate
        sql_execute(q{
            DELETE FROM page WHERE workspace_id = ? AND page_id IN (
                SELECT page_id FROM t_page
            )
        }, $workspace_id);

    }}
    catch {
        die "Error during populate of $workspace_name: $_";
    }
    finally {
        chdir $old_cwd;
    };
    return;
}

use constant PAGE_COLUMNS => Socialtext::Page::COLUMNS;
use constant PAGE_UPDATE_COLS =>
    grep !/^(?:workspace_id|page_id|creator_id|create_time)$/, PAGE_COLUMNS;

use constant PAGE_UPDATE_SQL => do {
    my $ph = join(', ', map { "$_ = ?" } PAGE_UPDATE_COLS);
    qq{UPDATE page SET $ph WHERE workspace_id = ? AND page_id = ?};
};

use constant PAGE_INSERT_SQL => do {
    my $cols = join ', ', PAGE_COLUMNS;
    my $ph = '?,' x scalar(PAGE_COLUMNS);
    chop $ph;
    qq{INSERT INTO page ($cols) VALUES ($ph)};
};
        
sub insert_or_update_page {
    my ($self, $page) = @_;
    my $workspace_id = $self->{workspace_id};
    my $page_id = $page->{page_id};

    my $dbh = get_dbh();
    my $t_page_get_sth = $dbh->prepare_cached(q{
        SELECT 1 FROM t_page WHERE page_id = ?
    });
    $t_page_get_sth->execute($page_id);
    my ($exists_already) = $t_page_get_sth->fetchrow_array;
    $t_page_get_sth->finish();

    # page will not end up purged
    my $t_page_del_sth = $dbh->prepare_cached(
        "DELETE FROM t_page WHERE page_id = ?");
    $t_page_del_sth->execute($page_id);

    if ($exists_already) {
        # NOTE that creator/create_time are not updated:
        my $update_sth = $dbh->prepare_cached(PAGE_UPDATE_SQL);
        $update_sth->execute(
            @$page{(PAGE_UPDATE_COLS)}, $workspace_id, $page_id);
        die "updating database failed"
            unless $update_sth->rows == 1;
    }
    else {
        my $insert_sth = $dbh->prepare_cached(PAGE_INSERT_SQL);
        $insert_sth->execute(@$page{(PAGE_COLUMNS)});
        die "inserting page failed"
            unless $insert_sth->rows == 1;
    }

    my $del_tags_sth = $dbh->prepare_cached(q{
        DELETE FROM page_tag WHERE workspace_id = ? AND page_id = ?
    });
    my $ins_tags_sth = $dbh->prepare_cached(q{
        INSERT INTO page_tag (workspace_id,page_id,tag) VALUES(?,?,?)
    });

    $del_tags_sth->execute($workspace_id, $page_id);
    $ins_tags_sth->execute_array({}, $workspace_id, $page_id, $page->{tags})
        if @{$page->{tags}||[]};

    return;
}

sub load_page_metadata {
    my ($self, $dir) = @_;
    my $ws_dir = $self->{workspace_data_dir};

    my $t = time_scope 'load_page_meta';

    my $ws_id = $self->{workspace}->workspace_id;
    $self->load_revision_metadata($ws_dir, $dir);
    my $sth;

    # Start with latest revision fields.  This *should* exclude "body".
    $sth = sql_execute(q{
        SELECT }.Socialtext::PageRevision::COLUMNS_STR.q{
          FROM page_revision
         WHERE workspace_id = ? AND page_id = ?
         ORDER BY revision_id DESC
         LIMIT 1
    }, $ws_id, $dir);
    die "Couldn't find any page_revisions for $ws_id:$dir"
        unless $sth->rows == 1;
    my $page = $sth->fetchrow_hashref();

    # and creation stats
    $sth = sql_execute(q{
        SELECT editor_id AS creator_id, edit_time AS create_time
          FROM page_revision
         WHERE workspace_id = ? AND page_id = ?
         ORDER BY revision_id ASC
         LIMIT 1
    }, $ws_id, $dir);
    @$page{qw(creator_id create_time)} = $sth->fetchrow_array();

    # and a revision tally
    $page->{revision_count} = sql_singlevalue(q{
        SELECT count(1) AS revision_count
          FROM page_revision
         WHERE workspace_id = ? AND page_id = ?
    }, $ws_id, $dir);

    # Finally, attempt to load the COUNTER file for this page
    my $counter_file = "$self->{workspace_plugin_dir}/counter/$dir/COUNTER";
    $page->{views} = -e $counter_file ? read_counter($counter_file) : 0;

    $page->{revision_count} ||= 0;
    $page->{summary} //= '';
    $page->{edit_summary} //= '';

    $page->{last_editor_id} = delete $page->{editor_id};
    $page->{last_edit_time} = delete $page->{edit_time};
    $page->{current_revision_id} = delete $page->{revision_id};
    $page->{current_revision_num} = delete $page->{revision_num};

    delete $page->{body_length};

    return $page;
}

use constant PAGE_REV_INSERT_SQL => do {
    my $cols_str = join(',', 'body', Socialtext::PageRevision::COLUMNS());
    my $ph = '?'; # body
    $ph .= ',?' x scalar(Socialtext::PageRevision::COLUMNS());
    qq{INSERT INTO page_revision ($cols_str) VALUES ($ph)};
};

sub load_revision_metadata {
    my ($self, $ws_dir, $pg_dir) = @_;
    my $t = time_scope 'load_rev_metadata';
    my $ws_id = $self->{workspace}->workspace_id;

    my $dbh = get_dbh();
    my $page_rev_insert_sth = $dbh->prepare_cached(PAGE_REV_INSERT_SQL);

    # If overwriting, we'll fetch basically every revision anyway.  For fresh
    # workspaces, this is empty and thus cheap.
    my $check_sth = $dbh->prepare_cached(q{
        SELECT revision_id FROM page_revision
        WHERE workspace_id = ? AND page_id = ?
    });
    my $existing_ids = Socialtext::IntSet->FromArray(
        # yes, you can pass in a prepared sth instead of text!
        $dbh->selectcol_arrayref($check_sth,{},$ws_id,$pg_dir) || []
    );

    my @files;
    opendir(my $dfh, "$ws_dir/$pg_dir");
    while (my $file = readdir($dfh)) {
        next unless $file =~ m/^[.\d]+\.txt$/;
        $file = "$ws_dir/$pg_dir/$file";
        next if -l $file;
        next unless -f $file;

        # Ignore really old pages that have invalid page_ids
        next unless Socialtext::Encode::is_valid_utf8($file);

        (my $revision_id = $file) =~ s#.+/(.+)\.txt$#$1#;
        $revision_id += 0 unless looks_like_number($revision_id); # force-numify
        next if $existing_ids->check($revision_id);

        push @files, [$revision_id, $file];
    }
    closedir $dfh;

    while (my $revvy = shift @files) {
        my ($revision_id, $file) = @$revvy;
        try {
            my $t = time_scope 'load_rev';

            die "zero length file" unless -s $file;

            my $pagemeta = fetch_metadata($file);
            die "missing required metadata" unless has_required_meta($pagemeta);

            my $body_ref = read_and_decode_page($file, 'content too');

            my $tags = $pagemeta->{Category} || [];
            $tags = [$tags] unless ref($tags);

            my $subject = $pagemeta->{Subject} || '';
            if (ref($subject)) { # Handle bad duplicate headers
                $subject = shift @$subject;
            }
            my $summary = $pagemeta->{Summary} || '';
            if (ref($summary) eq 'ARRAY') {
                # work around a bug where a page has 2 Summary revisions.
                $summary = $summary->[-1];
            }

            my $editor =  $self->editor_to_id($pagemeta->{From});
            unless ($editor) {
                push @{$self->{pages_with_default_editor}}, {
                    email_address => $pagemeta->{From},
                    page_id => $pg_dir,
                    revision_id => $revision_id,
                };
                $editor = Socialtext::User->SystemUser()->user_id();
            }

            my $control = lc($pagemeta->{Control} || '');
            my %cols = (
                workspace_id => $ws_id,
                page_id => $pg_dir,
                body_length => length($$body_ref),
                revision_id => $revision_id,
                name => $subject,
                tags => $tags,
                summary => $summary,
                editor_id => $editor,
                edit_time => $pagemeta->{Date},
                page_type => $pagemeta->{Type}||'wiki',
                deleted => $control eq 'deleted' ? 1 : 0,
                edit_summary => $pagemeta->{'Revision-Summary'},
                locked => $pagemeta->{Locked}||0,
                revision_num => $pagemeta->{Revision}||1,
            );

            sql_txn {
                my $n = 1;
                $page_rev_insert_sth->bind_param(
                    $n++, $$body_ref, {pg_type => DBD::Pg::PG_BYTEA});
                for my $col (Socialtext::PageRevision::COLUMNS()) {
                    $page_rev_insert_sth->bind_param($n++, $cols{$col});
                };
                $page_rev_insert_sth->execute;
                die "failed to insert $revision_id"
                    unless $page_rev_insert_sth->rows == 1;
            };
        }
        catch {
            my $err = format_err($_);
            warn "Couldn't parse revision $ws_dir/$pg_dir/$file, skipping: $err\n";
        };
    }

    return;
}

sub has_required_meta {
    my $pagemeta = shift;

    return 0 unless $pagemeta;
    return all { defined($pagemeta->{$_}) } qw/Subject From Date/;
}

use constant CONTENT_LIMIT => 2147483647; # 2GB-1byte, the max val for an Int in Pg.
sub load_page_attachments {
    my ($self, $page_hash) = @_;
    my $ws_dir = $self->{workspace_data_dir};
    my $t = time_scope 'load_page_atts';
    my $page_id = $page_hash->{page_id};

    my $atts_dir = $self->{workspace_plugin_dir}."/attachments/".
        $page_id;
    return unless -d $atts_dir;

    my $dbh = get_dbh();
    my $page_att_ins_sth = $dbh->prepare_cached(q{
        INSERT INTO page_attachment
        (workspace_id, page_id, id, attachment_id, deleted)
        VALUES (?,?,?,?,?)
    });
    my $upload_non_temp_sth = $dbh->prepare_cached(q{
        UPDATE attachment SET is_temporary = false WHERE attachment_id = ?
    });

    my $check_sth = $dbh->prepare_cached(q{
        SELECT id, attachment_id FROM t_attachments WHERE page_id = ?
    });
    $check_sth->execute($page_id);
    my %existing_att = map { $_->[0] => $_->[1] }
        @{ $check_sth->fetchall_arrayref || [] };
    $check_sth->finish;

    opendir my $dh, $atts_dir or die "can't open dir $atts_dir: $!";
    while (my $file = readdir($dh)) {
        next unless $file =~ m{([0-9-]+)\.txt$};
        my $legacy_id = $1;
        $file = "$atts_dir/$file";
        next unless -f $file;

        try {
            my $t2 = time_scope 'load_page_att';
            my $meta = fetch_metadata($file);

            # lowercase and underscorify headers to get rid of inconsistencies.
            $meta = { map {
                my $k = $_;
                $_ = lc($_);
                tr/-/_/;
                $_ => $meta->{$k};
            } keys %$meta };
            
            # From: q@q.q
            # Subject: Non-Hippie.jpg
            # DB_Filename: Non-Hippie.jpg
            # Date: 2011-02-08 22:19:01 GMT
            # Content-Length: 50418
            # Received: from 96.54.183.89
            # Content-MD5: cs7LkgTlDfL2ZS9rGVmkSA==
            # Content-type: image/jpeg
            # Control: Deleted

            $meta->{content_length} //= -1;
            my $control = lc($meta->{control} || '');
            my $deleted = $control eq 'deleted' ? 1 : 0;

            # If we're recreating this attachment, use the old attachment blob
            # (which can be identified by its old unique ID on this page) and
            # update the deleted status.
            if (my $upload_id = $existing_att{$legacy_id}) {
                sql_txn {
                    $page_att_ins_sth->execute(
                        @$page_hash{qw(workspace_id page_id)},
                        $legacy_id, $upload_id, $deleted);
                    die "insert failed" unless $page_att_ins_sth->rows == 1;
                };
                return; # from the try
            }

            $meta->{db_filename} //=
                Socialtext::String::uri_escape($meta->{subject});
            unless ($meta->{db_filename}) {
                die "attachment filename missing\n" if $Noisy;
                return; # from the try
            }

            my $disk_filename = "$atts_dir/$legacy_id/$meta->{db_filename}";
            my $disk_size = -s $disk_filename;
            if (!-f _ || !-r _) {
                die "attachment missing\n" if $Noisy;
                return; # from the try
            }
            elsif (!$disk_size) {
                die "zero-length attachment\n" if $Noisy;
                return; # from the try
            }
            elsif ($disk_size > CONTENT_LIMIT) {
                warn "attachment length greater than ". CONTENT_LIMIT
                    .", skipping\n";
                return; # from the try
            }
            elsif ($meta->{content_length} != $disk_size) {
                warn "attachment has unexpected size; ".
                    "got $disk_size, expected $meta->{content_length}\n"
                    if $Noisy;
                # continue
            }

            my $editor = $self->editor_to_id($meta->{from});
            my $found = $editor ? 1 : 0;
            $editor ||= Socialtext::User->SystemUser()->user_id();

            my %args = (
                temp_filename  => $disk_filename,
                creator_id     => $editor,
                created_at     => $meta->{date},
                filename       => $meta->{subject},
                content_length => $disk_size,
                content_md5    => $meta->{content_md5}, # possibly ignored
                no_log         => 1,
                db_only        => 1, # don't copy to storage area
            );

            if (-f "$disk_filename-mime") {
                my $hint = do { local (@ARGV,$_) = "$disk_filename-mime"; <> };
                chomp $hint;
                $args{mime_type} = $hint if $hint;
            }
            elsif ($meta->{content_type}) {
                $args{mime_type} = $meta->{content_type};
            }

            # Don't recalculate the mime_type (which requires a slow
            # shell-out) if we have it at hand.  This saves about 40% time for
            # help-en.
            $args{trust_mime_type} = 1 if $args{mime_type};

            sql_txn {
                my $t3 = time_scope 'upload_att';
                my $upload = Socialtext::Upload->Create(%args);
                undef $t3;

                # page_attachment make_permanent:
                # NOTE bind values must be same order as actual table
                $page_att_ins_sth->execute(
                    @$page_hash{qw(workspace_id page_id)}, 
                    $legacy_id, $upload->attachment_id, $deleted);
                die "insert failed" unless $page_att_ins_sth->rows == 1;

                # roughly Socialtext::Upload->make_permanent():
                $upload_non_temp_sth->execute($upload->attachment_id);
                die "upload de-temping failed"
                    unless $page_att_ins_sth->rows == 1;
                $upload->is_temporary(0); # just in case of cached

                push(
                    @{$self->{attachments_with_default_editor}},
                    {
                       email_address => $meta->{from},
                       attachment_id =>  $upload->attachment_id
                    }
                ) unless $found;
            };
        }
        catch {
            chomp;
            warn "importing attachment $legacy_id failed, skipping: $_\n";
        };
    }
}

sub fetch_metadata {
    my $file = shift;

    # Ignore non-UTF-8 warnings
    local $SIG{__WARN__} = sub {
        my $warning = shift;
        if ($warning =~ m/\Qdoesn't seem to be valid utf-8\E/ or
            $warning =~ m/\QTreating as iso-8859-1\E/) {
        }
        else {
            warn "\n\n$warning\n";
        }
    };

    return parse_page_headers(read_and_decode_page($file));
}

sub _clean_email_address {
    my $self = shift;
    my $email_address = shift;

    # We have some very bogus data on our system, so we need to
    # be very cautious.
    $email_address = lc($email_address);
    return $email_address if Email::Valid->address($email_address);

    my $unknown = 'unknown@example.com';

    my ($name) = $email_address =~ /([\w-]+)/;
    return $unknown unless defined $name;

    # appending '@example.com' does not guarantee a valid email.
    my $retry = "$name\@example.com";
    return Email::Valid->address($retry) ? $retry : $unknown;
}

sub editor_to_id {
    my $self = shift;
    my $email_address = shift || '';
    my $force = shift;
    state %userid_cache;
    $email_address = $self->_clean_email_address($email_address);
    unless ( $userid_cache{ $email_address } ) {

        # Load or create a new user with the given email.
        # Email addresses are always written to disk, even for ldap users.
        my $user = try {
            Socialtext::User->new(email_address => $email_address);
        };
        unless ($user) {
            return if $self->{skip_user_create} && !$force;
            $user = $self->_create_user_from_email($email_address);
        }

        $userid_cache{ $email_address } = $user->user_id;
    }
    return $userid_cache{ $email_address };
}

sub _create_user_from_email {
    my $self = shift;
    my $email_address = shift;

    my $user;
    warn "Creating user account for '$email_address'\n";
    try {
        Socialtext::Cache->clear('accounts');
        my $deleted = Socialtext::Account->Deleted();
        $user = Socialtext::User->create(
            email_address      => $email_address,
            username           => $email_address,
            primary_account_id => $deleted->account_id,
            missing            => 1,
        );
    	$user ||= Socialtext::User->SystemUser();
    }
    catch {
        warn "Failed to create user '$email_address', ".
             "defaulting to system-user: $_\n";
    	$user = Socialtext::User->SystemUser();
    };

    return $user;
}

sub has_missing_editors {
    my $self = shift;
    return 0 unless $self->{skip_user_create};

    return scalar(@{$self->{pages_with_default_editor}})
        || scalar(@{$self->{attachments_with_default_editor}});
}

sub cleanup_missing_editors {
    my $self = shift;
    my $dbh = get_dbh();

    my $page_update_sth = $dbh->prepare_cached(q{
        UPDATE page_revision
           SET editor_id = ?
         WHERE workspace_id = ?
           AND page_id = ?
           AND revision_id = ?
    });
    for my $pagemeta (@{$self->{pages_with_default_editor}}) {
        my $editor = $self->editor_to_id($pagemeta->{email_address}, 1);
        my $ws_id = $self->{workspace}->workspace_id;
        try {
            $page_update_sth->execute($editor, $ws_id,
                $pagemeta->{page_id}, $pagemeta->{revision_id});
        }
        catch {
            warn "Could not update editor to '$editor' for "
                . "ws_id=($ws_id),page_id=($pagemeta->{page_id}),"
                . "revision_id=($pagemeta->{revision_id})\n";
        };
    };

    my $att_update_sth = $dbh->prepare_cached(q{
        UPDATE attachment
           SET creator_id = ?
         WHERE attachment_id = ?
    });
    for my $attmeta (@{$self->{attachments_with_default_editor}}) {
        my $editor = $self->editor_to_id($attmeta->{email_address}, 1);
        try {
            $att_update_sth->execute($editor, $attmeta->{attachment_id});
        }
        catch {
            warn "Could not update editor to '$editor' for "
                . "attachment_id=($attmeta->{attachment_id})\n";
        };
    };
}

sub format_err {
    my $err = shift;
    return '' unless $err;

    chomp $err;
    $err =~ s/at \S+ line \d+.*.$//;

    return $err;
}

sub fix_relative_page_link {
    my $dir = shift;
    my $t = time_scope 'fix_rel_page_lnk';

    my $page_link_name = "$dir/index.txt";
    my $current_revision_file = ( -f $page_link_name )
        ? readlink( $page_link_name )
        : Socialtext::File::newest_directory_file( $dir );

    die "Couldn't find revision page for $page_link_name, skipping."
        unless $current_revision_file;

    unless ($current_revision_file =~ m#^/#) {
        my $abs_page = abs_path("$dir/$current_revision_file");
        die "Could not find symlinked page ($abs_page)"
            unless -f $abs_page;
        Socialtext::File::safe_symlink($abs_page, "$dir/index.txt");
    }
}

sub read_counter {
    my $file = shift;
    my $t = time_scope 'read_counter';
    my $contents = Socialtext::File::get_contents($file);
    my (undef, $count) = split "\n", $contents;
    return 0+$count;
}

sub load_breadcrumbs {
    my $self  = shift;
    my $t = time_scope 'load_breadcrumbs';
    my $ws_id = $self->{workspace}->workspace_id;

    my $ws_user_dir = $self->{workspace_user_dir};
    return unless -d $ws_user_dir;

    my $bc_insert = get_dbh()->prepare_cached(q{
        INSERT INTO breadcrumb
        (viewer_id, workspace_id, page_id, last_viewed)
        VALUES (?,?,?, current_date + ?::interval)
    });

    opendir(my $dfh, $ws_user_dir);
    while (my $user_dir = readdir($dfh)) {
        next unless -d "$ws_user_dir/$user_dir";
        next if $user_dir =~ m/^\./;
        my $trail = "$ws_user_dir/$user_dir/.trail";
        next unless -e $trail;

        my $user_id = $self->get_user_id($user_dir);
        next unless $user_id;


        my @page_ids;
        my $content = Socialtext::File::get_contents($trail);
        for my $name (split(/\n/, $content)) {
            my $decoded = Socialtext::Encode::guess_decode($name);

            # we've done our best to properly decode the string, override
            # warnings so we can skip and move on if there's further issues.
            local $SIG{__WARN__} = sub {
                die "improper UTF8 encoding for title_to_id() in $trail\n"
                    if $_[0] =~ /^Malformed UTF-8 character/;
                warn $_[0];
            };

            try {
                push @page_ids, Socialtext::String::title_to_id($decoded);
            }
            catch {
                warn "$_";
            };
        }

        # The .trail files do not contain dates, so we will sythesize dates to
        # provide order. We will start at midnight of today and add a second
        # for each breadcrumb.  Reverse the offsets because the trail file
        # is ordered most-to-least recent.
        my @offsets = map {"$_ seconds"} reverse 0 .. $#page_ids;

        # no need to worry about fk constraints (there are none):
        sql_txn {
            my @status;
            $bc_insert->execute_array({ArrayTupleStatus=>\@status},
                $user_id, $ws_id, \@page_ids, \@offsets);
            die "one or more breadcrumbs failed to insert\n"
                if any { $_ != 1 } @status;
        };
    }
    closedir $dfh;

    return;
}

sub get_user_id {
    my $self = shift;
    my $email = shift;
    my $user = Socialtext::User->new(email_address => $email);

    return $user ? $user->user_id : undef;
}

1;
