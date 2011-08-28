package Socialtext::Upload;
# @COPYRIGHT@
use Moose;
use File::Copy qw/copy move/;
use File::Path qw/make_path/;
use File::Map qw/map_file advise/;
use File::Temp ();
use Fatal qw/copy move rename open close chmod/;
use Try::Tiny;
use Guard;

use Socialtext::Moose::UserAttribute;
use Socialtext::MooseX::Types::Pg;
use Socialtext::MooseX::Types::UniStr;
use Socialtext::MooseX::Types::UUIDStr;
use Socialtext::SQL qw/:exec sql_txn sql_format_timestamptz get_dbh/;
use Socialtext::SQL::Builder qw/sql_nextval sql_insert sql_update/;
use Socialtext::Exceptions qw/no_such_resource_error data_validation_error/;
use Socialtext::Encode qw/ensure_is_utf8/;
use Socialtext::File ();
use Socialtext::Log qw/st_log/;
use Socialtext::JSON qw/encode_json/;
use Socialtext::Timer qw/time_scope/;
use Socialtext::UUID qw/new_uuid/;

use Carp 'croak';
use List::MoreUtils 'any';
use namespace::clean -except => 'meta';

use constant TIDY_FREQUENCY => 60;
use constant TABLE_REFS => qw(
    page_attachment
    signal_attachment
    signal_asset
);

# NOTE: if this gets changed to anything other than /tmp, make sure tmpreaper is
# monitoring that directory.
our $STORAGE_DIR = Socialtext::AppConfig->data_root_dir."/attachments";

our @SupportedImageTypes = qw(
    image/jpeg
    image/gif
    image/png
    image/bmp
    image/x-ms-bmp
);

has 'attachment_id' => (is => 'rw', isa => 'Int');
has 'attachment_uuid' => (is => 'rw', isa => 'Str.UUID');
has 'filename' => (is => 'rw', isa => 'UniStr', coerce => 1);
has 'mime_type' => (is => 'rw', isa => 'Str');
has 'content_length' => (is => 'rw', isa => 'Int');
has 'content_md5' => (is => 'rw', isa => 'Maybe[Str]', lazy_build => 1);
has 'created_at' => (is => 'rw', isa => 'Pg.DateTime', coerce => 1);
has_user 'creator' => (is => 'rw', st_maybe => 1);
has 'is_image' => (is => 'rw', isa => 'Bool');
has 'is_temporary' => (is => 'rw', isa => 'Bool');

# deliberately excludes 'body'
use constant COLUMNS => qw(
    attachment_id attachment_uuid creator_id created_at filename mime_type
    is_image is_temporary content_length
);
use constant COLUMNS_STR => join ', ', COLUMNS;

has 'disk_filename' => (is => 'ro', isa => 'Str', lazy_build => 1);
*storage_filename = *disk_filename;

around 'Create' => \&sql_txn;
sub Create {
    my ($class, %p) = @_;

    # temp_filename can be either a handle or a name. copy() below will accept
    # either.
    my $temp_fh = $p{fh} || $p{temp_filename}; 

    my $type_hint = $p{mime_type};
    if (my $field = $p{cgi_param}) {
        my $q = $p{cgi};
        $temp_fh = $q->upload($field);
        confess "no upload field '$field' found \n" unless $temp_fh;
        my $raw_info = $q->uploadInfo($temp_fh);
        my %info = map { lc($_) => $raw_info->{$_} } keys %$raw_info;
        my $cd = $info{'content-disposition'};
        my $real_filename;
        # XXX: this header can be mime-encoded (a la
        # http://www.ietf.org/rfc/rfc2184.txt) if it contains non-ascii
        if ($cd =~ /filename="([^"]+)"/) {
            $real_filename = $class->CleanFilename($1);
        }
        confess "no filename in Content-Disposition header"
            unless $real_filename;
        $type_hint = $info{'content-type'} if $info{'content-type'};
        $p{filename} = $real_filename;
    }
    else {
        confess "no temp_filename parameter supplied!"
            unless $temp_fh;
    }

    my $creator = $p{creator};
    my $creator_id = $creator ? $creator->user_id : $p{creator_id};

    my $id = sql_nextval('attachment_id_seq');
    my $uuid = $p{uuid} || new_uuid();

    my $filename = ensure_is_utf8($p{filename});
    $filename =~ s/[\/\\]+$//; # strip slashes like in clean_filename()
    $filename =~ s/^.*[\/\\]//;
    my $disk_filename = $class->_build_disk_filename($uuid);

    my ($g, $tmp_store, $content_length, $sref);
    if ($p{db_only}) {
        $tmp_store = $temp_fh;
        $content_length = -s $tmp_store;
    }
    else {
        _ensure_storage_dir($disk_filename);
        $tmp_store = $disk_filename.".tmp";
        $g = guard { local $!; unlink $tmp_store };

        # special-case IO::Scalar (well, a duck-type)
        if (blessed($temp_fh) && $temp_fh->can('sref')) {
            my $sref = $temp_fh->sref;
            $content_length = bytes::length($$sref);
            open my $fh, '>', $tmp_store;
            binmode($fh);
            print $fh $$sref;
            close $fh;
        }
        else {
            # these will die from Fatal:
            copy($temp_fh, $tmp_store);
            $content_length = -s $tmp_store;
        }
    }

    my $mime_type;
    if ($type_hint && $p{trust_mime_type}) {
        $mime_type = $type_hint;
    }
    else {
        my $tm = time_scope 'upload_mime_type';
        try {
            $mime_type = Socialtext::File::mime_type(
                $tmp_store, $filename, $type_hint);
        }
        catch {
            $mime_type = 'application/octet-stream';
            warn "Could not detect mime_type of $filename: $_\n";
        };
    }
    my $is_image = (any { $mime_type eq $_ } @SupportedImageTypes) ? 1 : 0;

    sql_insert(attachment => {
        attachment_uuid => $uuid,
        attachment_id   => $id,
        creator_id      => $creator_id,
        filename        => $filename,
        is_temporary    => 1,
        content_length  => $content_length,
        mime_type       => $mime_type,
        is_image        => $is_image,
        # let pg calculate the default for these:
        ($p{created_at} ? (created_at => $p{created_at}) : ()),
    });

    # Moose type constraints can cause the create to fail here, hence the txn
    # wrapper.
    my $self = $class->Get(attachment_id => $id);

    # pg will calculate it otherwise:
    $self->content_md5($p{content_md5}) if $p{content_md5};
    $self->_save_blob($tmp_store,$sref);

    unless ($p{db_only}) {
        rename $tmp_store => $disk_filename;
        $g->cancel if $g;
        my $time = $self->created_at->epoch;
        $self->update_utime($disk_filename);
    }

    return $self if $p{no_log};

    st_log()->info(join(',', "UPLOAD,CREATE",
        $self->is_image ? 'IMAGE' : 'FILE',
        encode_json({
            'id'         => $self->attachment_id,
            'uuid'       => $self->attachment_uuid,
            'path'       => $self->disk_filename,
            'creator_id' => $self->creator_id,
            'creator'    => $self->creator->username,
            'filename'   => $self->filename,
            'created_at' => $self->created_at_str,
            'type'       => $self->mime_type,
        })));

    return $self;
}

sub Get {
    my ($class, %p) = @_;

    my $attachment_id = delete $p{attachment_id};
    my $attachment_uuid = delete $p{attachment_uuid};
    data_validation_error("need an ID or UUID to retrieve an attachment")
        unless ($attachment_id || $attachment_uuid);

    my $dbh = sql_execute(q{
        SELECT }.COLUMNS_STR.q{,
            created_at AT TIME ZONE 'UTC' || '+0000' AS created_at_utc
          FROM attachment
         WHERE attachment_id = ? OR attachment_uuid = ?
    }, $attachment_id, $attachment_uuid);
    my $row = $dbh->fetchrow_hashref();

    no_such_resource_error(
        message => "Uploaded file not found.",
        name => 'Uploaded file'
    ) unless $row;

    $row->{created_at} = delete $row->{created_at_utc};
    return $class->new($row);
}

sub CleanTemps {
    my $class = shift;
    # tmpreaper period is hard-coded to 7d in gen-config and will be
    # deleteing the files themselves.
    my $sth = sql_execute(q{
        DELETE FROM attachment
        WHERE is_temporary
          AND created_at < 'now'::timestamptz - '7 days'::interval
    });
    warn "Cleaned up ".$sth->rows." temp attachment records"
        if ($sth->rows > 0);
}

sub update_utime {
    my ($self, $filename) = @_;
    $filename //= $self->disk_filename;
    utime time, # update atime for tmpreaper
        $self->created_at->epoch, # mtime for nginx
        $filename
     or warn "can't update timestamp on $filename: $!";
    return;
}

sub relative_filename {
    my ($class_or_self, $uuid) = @_;
    $uuid ||= $class_or_self->attachment_uuid;
    my $part1 = substr($uuid,0,2);
    my $part2 = substr($uuid,2,2);
    my $file  = substr($uuid,4);
    return join('/', $part1, $part2, $file);
}

sub _build_disk_filename {
    my $class_or_self = shift;
    return join('/', $STORAGE_DIR, $class_or_self->relative_filename(@_));
}

sub protected_uri {
    my $class_or_self = shift;
    return join('/', '/nlw/attachments', $class_or_self->relative_filename(@_));
}

sub created_at_str { sql_format_timestamptz($_[0]->created_at) }

*as_hash = *to_hash;
sub to_hash {
    my ($self, $viewer) = shift;
    my %hash = map { $_ => $self->$_ } qw(
        attachment_id attachment_uuid filename
        mime_type content_length creator_id
    );
    $hash{created_at} = $self->created_at_str;
    $hash{is_temporary} = $self->is_temporary ? 1 : 0;
    $hash{is_image} = $self->is_image ? 1 : 0;
    $hash{content_md5} = $self->has_content_md5 ? $self->content_md5 : undef;

    if ($viewer && $viewer->is_business_admin) {
        my $filename = $self->disk_filename;
        my $stat = [stat $filename];
        my $exists = -f _;
        $hash{physical_status} = {
            filename => $filename,
            'exists' => $exists ? 1 : 0,
            'stat' => $stat,
        };
    }

    return \%hash;
}

sub to_string {
    my ($self, $buf_ref, $is_temp) = @_;
    croak "must supply a buffer reference for to_string()"
        unless $buf_ref && ref($buf_ref);
    require Socialtext::File::Stringify;
    my $file;

    if ($is_temp) {
        $file = File::Temp->new;
        $self->copy_to_fh($file);
        close $file;
    }
    else {
        $self->ensure_stored();
        $file = $self->disk_filename;
    }

    Socialtext::File::Stringify->to_string(
        $buf_ref, "$file", $self->mime_type);
    return;
}

sub delete {
    my $self = shift;
    # missing file is OK; it's just a cache copy anyhow
    unlink $self->disk_filename;
}

sub purge {
    my ($self, %p) = @_;
    croak "delete requires an actor" unless $p{actor};
    my $actor = $p{actor};

    # missing file is OK; it's just a cache copy anyhow
    unlink $self->disk_filename;

    # If uploads are copyable to multiple attachments this delete may fail
    # harmlessly ASSUMING that all the foreign keys are "ON DELETE RESTRICT".
    my $deleted = 0;
    try { sql_txn {
        my $sth = sql_execute(q{DELETE FROM attachment WHERE attachment_id = ?},
            $self->attachment_id);
        $deleted = $sth->rows == 1;
    }}
    catch {
        die $_ unless (/violates foreign key constraint/i);
    };

    # trigger cleaning up any others that may have been purged
    Socialtext::JobCreator->tidy_uploads();

    return if $p{no_log} || !$deleted;

    st_log()->info(join(',', "UPLOAD,DELETE",
        $self->is_image ? 'IMAGE' : 'FILE',
        encode_json({
            'id'       => $self->attachment_id,
            'uuid'     => $self->attachment_uuid,
            'path'     => $self->disk_filename,
            'actor_id' => $actor->user_id,
            'actor'    => $actor->username,
            'filename' => $self->filename,
        })
    ));
}

sub make_permanent {
    my ($self, %p) = @_;
    croak "make_permanent requires an actor" unless $p{actor};
    return unless $self->is_temporary;

    my $g = guard {
        local $!;
        $self->is_temporary(1);
        unlink $self->disk_filename;
    };

    sql_execute(q{
        UPDATE attachment SET is_temporary = false WHERE attachment_id = ?
    }, $self->attachment_id);
    $self->is_temporary(0);
    $self->ensure_stored() unless $p{db_only};
    $g->cancel() unless $p{guard};

    return $g if $p{no_log};

    my $actor = $p{actor};
    st_log()->info(join(',', "UPLOAD,CONSUME",
        $self->is_image ? 'IMAGE' : 'FILE',
        encode_json({
            'id'        => $self->attachment_id,
            'uuid'      => $self->attachment_uuid,
            'path'      => $self->disk_filename,
            'actor_id'  => $actor->user_id,
            'actor'     => $actor->username,
            'filename'  => $self->filename,
        })));
    return $g;
}

sub _ensure_storage_dir {
    my $filename = shift;
    (my $dir = $filename) =~ s{/[^/]+$}{};
    make_path($dir, {mode => 0774});
    return $dir;
}

sub _store {
    my ($self, $data_ref, $filename) = @_;
    local $!;
    confess "undef data" unless defined($$data_ref);

    $filename ||= $self->disk_filename;
    my $dir = _ensure_storage_dir($filename);
    my $tmp = File::Temp->new(DIR => $dir,
        TEMPLATE => 'store-XXXXXX', SUFFIX => '.tmp')
        or confess "can't open storage temp file: $!";

    my $wrote = syswrite $tmp, $$data_ref;
    die "can't write to storage temp file: $!" if ($! or $wrote <= 0);
    close $tmp; # Fatal
    chmod 0644, "$tmp"; # Fatal
    rename "$tmp" => $filename; # Fatal
    $self->update_utime($filename);
    return;
}

sub _save_blob {
    my ($self, $from_filename, $data) = @_;
    my $t = time_scope 'upload_save_blob';
    unless ($data) {
        $from_filename ||= $self->disk_filename;
        if (my $size = -s $from_filename) {
            map_file $data, $from_filename, '<', 0, $size;
            advise $data, 'sequential';
        }
        else {
            $data = '';
        }
    }
    my $md5 = $self->has_content_md5 ? $self->content_md5 : undef;
    my $sth = sql_saveblob(\$data, q{
        UPDATE attachment SET body = $1, content_md5 = $2
         WHERE attachment_id = $3
        RETURNING content_md5
    }, $md5, $self->attachment_id);
    my ($new_md5) = $sth->fetchrow_array();
    $self->content_md5($new_md5);
    return;
}

sub _load_blob {
    my ($self, $data_ref) = @_;
    sql_singleblob($data_ref,
        q{SELECT body FROM attachment WHERE attachment_id = $1},
        $self->attachment_id);
}

# opposite of ensure_stored
sub cleanup_stored {
    my $self = shift;
    my $filename = $self->disk_filename;
    confess "illegal glob filename: $filename" if $filename =~ /\s/;
    while (my $file = glob "$filename*") {
        unlink $file;
    }
}

sub ensure_stored {
    my ($self, $filename) = @_;
    $filename //= $self->disk_filename;
    if (-f $filename && -s _ == $self->content_length) {
        $self->update_utime($filename);
        return;
    }

    my $data;
    $self->_load_blob(\$data);
    $self->_store(\$data, $filename);
    return;
}

sub binary_contents {
    my ($self, $data_ref) = @_;
    my $filename = $self->disk_filename;
    if (-f $filename) {
        if (my $size = -s _) {
            map_file $$data_ref, $filename, '<', 0, $size;
        }
        else {
            $$data_ref = '';
        }
    }
    else {
        $self->_load_blob($data_ref);
    }
    return;
}

sub copy_to_file {
    my ($self, $target) = @_;
    open my $fh, '>:mmap', $target; # Fatal
    $self->copy_to_fh($fh);
    close $fh; # Fatal
}

sub copy_to_fh {
    my ($self, $target_fh) = @_;
    my $blob;
    $self->binary_contents(\$blob); # either maps or sql_singleblobs
    my $wrote = syswrite $target_fh, $blob;
    die "failed to copy to file: $!" unless $wrote == length($blob);
}

my $encoding_charset_map = {
    'euc-jp' => 'EUC-JP',
    'shiftjis' => 'Shift_JIS',
    'iso-2022-jp' => 'ISO-2022-JP',
    'utf8' => 'UTF-8',
    'cp932' => 'CP932',
    'iso-8859-1' => 'ISO-8859-1',
};

sub charset {
    my $self = shift;
    my $type = $self->mime_type;
    my $charset = $type =~ /\bcharset=(.+?)[\s;]?/ ? $1 : 'UTF-8';
    return $encoding_charset_map->{lc $charset} || $charset;
}

*CleanFilename = *clean_filename;
sub clean_filename {
    my $class_or_self = shift;
    my $filename      = shift || $class_or_self->filename;
    $filename = ensure_is_utf8($filename);
    $filename =~ s/[\/\\]+$//;
    $filename =~ s/^.*[\/\\]//;
    # why would we do  ... => ~~.  ?
    $filename =~ s/(\.+)\./'~' x length($1) . '.'/ge;
    return $filename;
}

sub short_name {
    my $self = shift;
    my $name = $self->filename;
    $name =~ s/ /_/g;
    return $name
      unless $name =~ /^(.{16}).{2,}(\..*)/;
    return "$1..$2";
}

sub _build_content_md5 {
    my $self = shift;
    my $blob;
    $self->binary_contents(\$blob);
    return unless defined $blob;
    my $ctx = Digest::MD5->new();
    $ctx->add($blob);
    return $ctx->b64digest . "==";
}

sub ensure_scaled {
    my ($self, %opts) = @_;
    confess "can only scale images" unless $self->is_image;
    require Socialtext::Image;

    my $t = time_scope 'ensure_scaled';

    my $spec = delete $opts{spec} || 'thumb-64x64';
    confess "invalid resize spec" unless $spec =~ /^[a-z0-9-@]+$/;

    my $filename = $self->disk_filename;
    my $dir = _ensure_storage_dir($filename);
    my $scaled = "$filename.$spec";
    if (-f $scaled && -s _) {
        my $size = -s _;
        $self->update_utime($scaled);
        return $size;
    }

    my $t2 = time_scope 'gen_scaled';

    $self->ensure_stored unless -f $filename; # avoid utimes bump

    my $tmp = File::Temp->new(
        DIR => $dir, TEMPLATE => 'scale-XXXXXX',
    ) or die "can't make tempfile: $!";
    close $tmp; # will read/write via name

    Socialtext::Image::spec_resize($spec, $filename => "$tmp");
    chmod 0644, "$tmp"; # Fatal
    # the -f check here doesn't guarantee we won't overwrite, but *does* give
    # more insurance that we won't return an incorrect Content-Length due to
    # multiple writer processes and non-deterministic image scaling output.
    rename "$tmp" => $scaled unless -f $scaled; # Fatal

    # make the scaled image have the same utimes as for regular attachments:
    $self->update_utime($scaled);
    return -s $scaled;
}

__PACKAGE__->meta->make_immutable;
1;
__END__

=head1 NAME

Socialtext::Upload - Data object for uploaded files

=head1 SYNOPSIS

    use Socialtext::Upload;
    my $upload = Socialtext::Upload->Get(attachment_id => $n);
    # or
    my $upload = Socialtext::Upload->Get(attachment_uuid => $uuid);

    my $u = Socialtext::Upload->Create(cgi => $cgi, cgi_param => 'file_param',
        user => $creator);
    sql_txn {
        $social_object->attach($u);
        $u->make_permanent(actor => $creator);
    };

=head1 DESCRIPTION

Socialtext::Upload encapsulates the "uploaded file" lifecycle.  It's a
combination of a database record and file on disk.  The file is stored in a
temporary area (which is periodically cleaned by other parts of the system)
until it is "made permanent" by associating it with some other object in the
Socialtext system.

=head1 SEE ALSO

C<Socialtext::Rest::Upload> and C<Socialtext::Rest::Uploads> - the ReST API
associated with this class.

C<Socialtext::Signal::Attachment> - the first user of this module.

=cut
