package Socialtext::Attachment;
# @COPYRIGHT@
use 5.12.0;
use Moose;
use MooseX::StrictConstructor;
use Carp qw/croak confess/;
use Scalar::Util qw/blessed/;
use Try::Tiny;
use Fcntl qw/LOCK_EX/;
use File::Basename;

use Socialtext::Upload;
use Socialtext::File ();
use Socialtext::SQL qw/:exec :txn/;
use Socialtext::SQL::Builder qw/sql_insert/;
use Socialtext::String qw/:uri :html/;
use Socialtext::Timer qw/time_scope/;
use Socialtext::Client::Wiki qw( wiki2html );

use namespace::clean -except => 'meta';

has 'hub' => (
    is => 'ro', isa => 'Socialtext::Hub',
    weak_ref => 1, predicate => 'has_hub'
);

# pseudo-FK into the "page" table. The page may be in the process of being
# created and thus may not "exist" until after this attachment gets stored.
has 'page_id' => (is => 'ro', isa => 'Str', required => 1);
has 'page' => (
    is => 'rw', isa => 'Socialtext::Page',
    lazy_build => 1,
    writer => '_page',
);

has 'workspace_id' => (is => 'ro', isa => 'Int', required => 1);
has 'workspace' => (
    is => 'ro', isa => 'Socialtext::Workspace',
    lazy_build => 1,
    writer => '_workspace',
);

# FK into the "attachment" table. Used to build ->upload:
has 'attachment_id' => (is => 'rw', isa => 'Int', writer => '_attachment_id');

# Legacy identifier, date-based:
has 'id' => (is => 'rw', isa => 'Str', writer => '_id',
    default => \&new_id);

has 'deleted' => (is => 'rw', isa => 'Bool',
    reader => 'is_deleted', writer => '_deleted');
*deleted = *is_deleted;

has 'upload' => (
    is => 'rw', isa => 'Socialtext::Upload',
    lazy_build => 1,
    handles => [qw(
        attachment_uuid binary_contents cleanup_stored clean_filename
        content_length content_md5 copy_to_file created_at created_at_str
        creator creator_id disk_filename ensure_stored filename is_image
        is_temporary mime_type protected_uri short_name to_string
    )],
    trigger => sub { $_[0]->_attachment_id($_[1]->attachment_id) },
);
*uploaded_by = *creator;
*editor_id = *creator_id;
*editor = *creator;
*CleanFilename = *Socialtext::Upload::CleanFilename;

use constant COLUMNS => qw(id workspace_id page_id attachment_id deleted);
use constant COLUMNS_STR => join ', ', COLUMNS;

override 'BUILDARGS' => sub {
    my $class = shift;
    my $p = ref($_[0]) eq 'HASH' ? $_[0] : {@_};
    if (my $hub = $p->{hub}) {
        $p->{workspace} = $hub->current_workspace;
        $p->{workspace_id} = $p->{workspace}->workspace_id;
    }
    return $p;
};

sub _build_page {
    my $self = shift;
    croak "Can't build page: no hub on this Attachment" unless $self->has_hub;
    $self->hub->pages->new_page($self->page_id);
}

sub _build_workspace {
    my $self = shift;
    return Socialtext::Workspace->new(workspace_id => $self->workspace_id);
}

sub _build_upload {
    my $self = shift;
    my $att_id = $self->attachment_id;
    confess "This Attachment hasn't been saved yet" unless $att_id;
    return Socialtext::Upload->Get(attachment_id => $att_id);
}

sub Search {
    my $class = shift;
    my %params = @_;
    my $workspace = delete $params{workspace};
    my $workspace_name = delete $params{workspace_name};
    my $term = delete $params{search_term};

    croak $class."->Search requires a workspace or workspace_name param"
        if (!$workspace && !$workspace_name);

    require Socialtext::Search::Solr::Factory;
    my $name = $workspace ? $workspace->name : $workspace_name;
    my $searcher = Socialtext::Search::Solr::Factory->create_searcher($name);

    my ($ref,$num_hits) = $searcher->begin_search(
        $term, undef, undef, %params, doctype=>'attachment');

    return ($ref->() || [], $num_hits);
}

# legacy ID generator (new stuff should use UUIDs)
my $id_counter = 0;
sub new_id {
    my ($sec, $min, $hour, $mday, $mon, $year) = gmtime(time);
    return sprintf('%4d%02d%02d%02d%02d%02d-%d-%d',
        $year+1900, $mon+1, $mday, $hour, $min, $sec, $id_counter++, $$
    );
}

# Only call this from tests, please
sub content {
    my $self = shift;
    my $blob;
    $self->upload->binary_contents(\$blob);
    return $blob;
}

sub store {
    my $self = shift;
    my %p = @_;
    $p{user} //= $self->has_hub ? $self->hub->current_user : undef;
    my $is_temp = $p{temporary} ? 1 : 0;
    confess('no user given to Socialtext::Attachment->store')
        unless $p{user};

    croak "Can't save an attachment without an associated Upload object"
        unless $self->has_upload;
    croak "Can't store once deleted (calling delete() does a store())"
        if $self->deleted;

    my %args = map { $_ => $self->$_ } COLUMNS;
    $args{deleted} = 0;

    try {
        sql_txn {
            my $guard = $self->upload->make_permanent(
                actor => $p{user}, guard => 1
            ) unless $is_temp;
            sql_insert('page_attachment' => \%args);
            $guard->cancel() if $guard;
        };
    }
    catch {
        croak "store page attachment failed: ".
            "attachment already exists? error: $_"
            if /primary.key/i;
        die $_;
    };

    $self->reindex() unless $is_temp;
    return;
}

sub clone {
    my $self = shift;
    my %p = @_;
    my $page = delete $p{page};

    my $upload = $self->upload;
    my $target = $self->new(
        hub => $page->hub,
        page_id => $page->page_id,
        workspace_id => $page->workspace_id,
        upload => $upload,
        attachment_id => $upload->attachment_id,
        id => new_id(),
        deleted => undef,
        page => $page,
        workspace => $page->workspace,
    );
    $target->store(temporary => 1); # so the upload doesn't make_permanent again
    $target->reindex();
    return $target;
}

sub reindex {
    my $self = shift;
    return if $self->is_temporary;
    require Socialtext::JobCreator;
    Socialtext::JobCreator->index_attachment($self);
    return;
}

sub make_permanent {
    my $self = shift;
    my %p = @_;
    $p{user} //= $self->has_hub ? $self->hub->current_user : undef;
    confess('no user given to Socialtext::Attachment->make_permanent')
        unless $p{user};

    # Use a guard if anything tricky can happen between perma-fying and
    # returning:
    $self->upload->make_permanent(
        actor => $p{user}, no_log => $p{no_log}, guard => 0);

    $self->move_to_page($p{page});
    $self->reindex();

    return;
}

sub move_to_page {
    my ($self, $page) = @_;
    if ($page and $page->page_id ne $self->page_id) {
        # Here we need to move $self from an untitled page
        # into the newly assigned page.
        sql_execute(q{
            UPDATE page_attachment SET page_id = ? WHERE id = ?
        }, $page->page_id, $self->id);
    }
}

sub delete {
    my $self = shift;
    my %p = @_;
    $p{user} //= $self->has_hub ? $self->hub->current_user : undef;
    confess('no user given to Socialtext::Attachment->delete')
        unless $p{user};
    confess "can't delete an attachment that isn't saved yet"
        unless $self->has_upload;

    sql_txn {
        sql_execute(q{
            UPDATE page_attachment SET deleted = true
            WHERE page_id = ? AND attachment_id = ?
        }, $self->page_id, $self->attachment_id);
        local $!;
        $self->upload->delete(actor => $p{user});
    };

    $self->reindex();
    return;
}

sub purge {
    my $self = shift;

    # clean up the index first
    my $ws = $self->workspace;
    my $ws_name = $ws->name;

    my $u = $self->upload;
    sql_txn {
        sql_execute(q{
            DELETE FROM page_attachment
            WHERE workspace_id = ? AND page_id = ? AND attachment_id = ?
        }, $ws->workspace_id, $self->page_id, $u->attachment_id);

        # this will leave the attachment intact if referenced by other things:
        $u->purge(actor => $self->hub->current_user);
    };

    # If solr/kino are slow, we may wish to do this async in a job.  Note that
    # jobs generally require the attachment object to be available.
    require Socialtext::Search::AbstractFactory;
    my @indexers = Socialtext::Search::AbstractFactory->GetIndexers($ws_name);
    for my $indexer (@indexers) {
        $indexer->delete_attachment($self->page_id, $self->id);
    }
}

sub inline {
    my ($self, $user) = @_;
    croak "can't inline without a hub" unless $self->has_hub;
    $user //= $self->hub->current_user;

    # a page object/id used to be the first parameter:
    croak "user is required as the first argument"
        unless blessed($user) && $user->isa('Socialtext::User');

    my $page = $self->page;
    my $guard = $self->hub->pages->ensure_current($page);
    $page->edit_rev();

    my $body_ref = $page->body_ref;
    my $body_new = $self->image_or_file_wafl();
    $body_new = wiki2html($body_new) if $page->page_type eq 'xhtml';
    $body_new .= $$body_ref;
    $body_ref = \$body_new;
    $page->body_ref(\$body_new);

    $page->store(user => $user);
}

sub extract {
    my $self = shift;
    require Socialtext::ArchiveExtractor;
    my $t = time_scope 'attachment_extract';
    my $cur_guard = $self->hub->pages->ensure_current($self->page_id);

    # TODO: de-duplicate files by doing md5 lookups and multiply-assigning
    # Uploads to attachments.

    # Socialtext::ArchiveExtractor uses the extension to figure out how to
    # extract the archive, so that must be preserved here.
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    my $archive = "$tmpdir/".$self->clean_filename;
    $self->copy_to_file($archive);

    my @files = Socialtext::ArchiveExtractor->extract(archive => $archive);
    # before everything-in-the-db this used to try to add the archive itself
    return unless @files;

    my $attachments = $self->hub->attachments;
    sql_txn {
        my @atts;
        for my $file (@files) {
            my $filename = File::Basename::basename($file);
            my $att = $attachments->create(
                filename  => $filename,
                fh        => $file,
                page_id   => $self->page_id,
                embed     => 0,
                temporary => 1,
            );
            push @atts, $att;
        }
        $_->make_permanent(user => $self->hub->current_user) for @atts;
        $self->hub->attachments->inline_all(
            $self->hub->current_user,
            $self->page,
            \@atts,
        );
    };

    return;
}

sub dimensions {
    my ($self, $size) = @_;
    $size ||= '';
    return if $size eq 'scaled' and $self->workspace->no_max_image_size;
    return unless $size;
    return [0, 0] if $size eq 'scaled';
    return [100, 0] if $size eq 'small';
    return [300, 0] if $size eq 'medium';
    return [600, 0] if $size eq 'large';
    return [$1 || 0, $2 || 0] if $size =~ /^(\d+)(?:x(\d+))?$/;
}

sub prepare_to_serve {
    my ($self, $flavor, $protected) = @_;
    undef $flavor if ($flavor && ($flavor eq 'original' || $flavor eq 'files'));

    my ($uri,$content_length);
    if ($self->is_image && $flavor) {
        my $dim = $self->dimensions($flavor);
        my $spec = 'resize-'.join('x',@$dim) if $dim;
        if ($spec) {
            $spec = 'thumb-600x0' if $spec eq 'resize-0x0';
            try {
                $content_length = $self->upload->ensure_scaled(spec => $spec);
                $uri = $protected
                    ? $self->protected_uri.".$spec"
                    : $self->download_uri($flavor);
            }
            catch {
                warn "while scaling attachment: $_";
            };
        }
    }

    unless ($uri) {
        $self->ensure_stored();
        $content_length = $self->content_length;
        $uri = $protected ? $self->protected_uri : $self->download_uri;
    }

    return ($uri, $content_length) if wantarray;
    return $uri;
}

sub should_popup {
    my $self = shift;
    my @easy_going_types = (
        qr|^text/|, # especially text/html
        qr|^image/|,
        qr|^video/|,
        # ...any others?   ...any exceptions?
    );
    return not grep { $self->mime_type =~ $_ } @easy_going_types;
}

sub image_or_file_wafl {
    my $self = shift;
    my $filename = $self->filename;
    my $wafl = $self->is_image ? "image" : "file";
    return "{$wafl\: $filename}\n\n";
}

my $ExcerptLength = 350;
sub preview_text {
    my $self = shift;
    my $excerpt;
    $self->to_string(\$excerpt);
    $excerpt = substr( $excerpt, 0, $ExcerptLength ) . '...'
        if length $excerpt > $ExcerptLength;
    return $excerpt;
}

sub download_uri {
    my ($self, $flavor) = @_;
    $flavor ||= 'original'; # can also be 'files'
    my $ws = $self->workspace->name;
    my $filename_uri  = uri_escape($self->clean_filename);
    my $uri = "/data/workspaces/$ws/attachments/".
        $self->page->uri.':'.$self->id."/$flavor/$filename_uri";
}

sub download_link {
    my ($self, $flavor) = @_;
    my $uri = $self->download_uri($flavor);
    my $filename_html = html_escape($self->filename);
    return qq(<a href="$uri">$filename_html</a>);
}

sub to_hash {
    my ($self, %p) = @_;
    state $nf = Number::Format->new;
    my $user = $self->creator;
    my $hash = {
        id   => $self->id,
        uuid => $self->attachment_uuid,
        name => $self->filename,
        uri  => $self->download_uri('original'),
        'content-type'   => $self->mime_type,
        'content-length' => $self->content_length,
        date             => $self->created_at_str,
        uploader         => $user->email_address,
        uploader_name    => $user->display_name,
        uploader_id      => $user->user_id,
        'page-id'        => $self->page_id,
        ($self->is_temporary ? (is_temporary => 1) : ()),
    };

    if ($p{formatted}) {
        my $bytes = $self->content_length;
        $hash->{size} = $bytes < 1024
            ? "$bytes bytes" : $nf->format_bytes($bytes);
        $hash->{local_date} = $self->hub->timezone->get_date($self->created_at);
    }

    return $hash;
}

sub export_to_dir {
    my ($self, $dir) = @_;
    my $id = $self->id;
    my $db_filename = uri_escape($self->filename);

    mkdir "$dir/$id" or die "can't write attachment: $!";

    open my $fh, '>:mmap:utf8', "$dir/$id.txt"
        or die "can't write attachment: $!";
    print $fh
        ($self->deleted ? ("Control: Deleted\n") : ()),
        "From: ",$self->creator->email_address,"\n",
        "Subject: ",$self->filename,"\n",
        "DB_Filename: ",$db_filename,"\n",
        "Date: ",$self->created_at_str,"\n",
        "Received: from 127.0.0.1\n",
        "Content-MD5: ",$self->content_md5,"\n",
        "Content-type: ",$self->mime_type,"\n", # yes, lowercase t
        "Content-Length: ",$self->content_length,"\n",
        "\n";
    close $fh
        or die "can't write attachment: $!";

    $self->copy_to_file("$dir/$id/$db_filename");
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;
