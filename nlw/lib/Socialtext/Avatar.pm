package Socialtext::Avatar;
# @COPYRIGHT@
use Moose::Role;
use DBD::Pg qw/:pg_types/;
use File::Temp qw(tempfile);
use File::Path qw/remove_tree/;
use Socialtext::Image;
use Socialtext::File;
use Socialtext::Skin;
use Socialtext::SQL qw(:txn :exec get_dbh);
use Socialtext::SQL::Builder qw(sql_insert sql_update);
use Try::Tiny;
use namespace::clean -except => 'meta';

requires qw(cache table versions id_column id resize_spec default_skin);

sub DefaultPhoto {
    my $class = shift;
    my $version = shift || die 'version required';

    # get the path to the image, on *disk*
    my $skin = Socialtext::Skin->new( name => $class->default_skin );
    my $dir = File::Spec->catfile($skin->skin_path, "images");

    my $default_arg = "default_$version";
    my $file = $class->$default_arg || die "no $default_arg!";
    my $blob = Socialtext::File::get_contents_binary("$dir/$file");
    return \$blob;
}

sub cache_dir {
    my $class = shift;
    my $cache_dir = Socialtext::Paths::cache_directory($class->cache);
    Socialtext::File::ensure_directory($cache_dir);
    return $cache_dir;
}

has 'default' => (
    is => 'rw', isa => 'Bool',
    lazy_build => 1,
    reader => 'is_default',
);

sub _build_default {
    my $self = shift;
    my $table = $self->table;
    my $id_column = $self->id_column;
    return !sql_singlevalue(
        "SELECT 1 FROM $table WHERE $id_column = ?", $self->id
    );
}

sub set {
    my $self = shift;
    my $blob_ref = shift;

    return try {
        my %blobs;
        for my $version (@{$self->versions}) {
            my $tmp = File::Temp->new(UNLINK => 1);
            print $tmp $$blob_ref;
            close $tmp or die "Invalid image: $!";

            my $spec = Socialtext::Image::spec_resize_get(
                $self->resize_spec, $version);
            Socialtext::Image::spec_resize($spec, "$tmp" => "$tmp");

            my $contents = Socialtext::File::get_contents_binary("$tmp");
            $self->$version(\$contents);
            $blobs{$version} = \$contents;
        }

        $self->_save_db(%blobs);
        $self->_save_cache(%blobs);
        $self->default(0);
        return;
    }
    catch {
        return "Animated images are not supported"
            if /Can't resize animated images/;
        warn $_;
        return "Invalid image";
    };
}

sub purge {
    my $self = shift;
    my $id = $self->id;
    my $table = $self->table;
    my $id_column = $self->id_column;

    # Remove from DB
    sql_execute("DELETE FROM $table WHERE $id_column = ?", $self->id);

    # Remove from cache
    my $cache_dir = $self->cache_dir;
    my $lock_fh = Socialtext::File::write_lock("$cache_dir/.lock");
    for my $version (@{$self->versions}) {
        unlink "$cache_dir/$id-$version.png";
        if ($self->can('synonyms')) {
            my @symlinks = map { s#/#\%2f#g; "$cache_dir/$_-$version.png" }
                           $self->synonyms;
            unlink @symlinks;
        }
    }
}


sub _save_db {
    my ($self, %blobs) = @_;

    sql_txn {
        my $dbh = get_dbh;
        local $dbh->{RaiseError} = 1; # b/c of direct $dbh usage

        my $table = $self->table;
        my $id_column = $self->id_column;

        my $exists = sql_singlevalue(qq{
            SELECT 1 FROM $table WHERE $id_column = ?
        }, $self->id);

        my @versions = @{$self->versions};
        my $sth;
        if ($exists) {
            my $sets = join ", ", map { "$_ = ?" } @versions;
            $sth = $dbh->prepare(
                "UPDATE $table SET $sets WHERE $id_column = ?"
            );
        }
        else {
            my $cols = join ', ', @versions, $id_column;
            my $ques = join ', ', map('?', 0 .. scalar @versions);
            $sth = $dbh->prepare("INSERT INTO $table ($cols) VALUES ($ques)");
        }

        my $n = 1;
        for my $version (@versions) {
            $sth->bind_param($n++, ${$blobs{$version}}, {pg_type => PG_BYTEA});
        }
        $sth->bind_param($n++, $self->id);
        $sth->execute;

        die "unable to update image" unless ($sth->rows == 1);
    };
}

sub _save_cache {
    my ($self, %blobs) = @_;

    my $cache_dir = $self->cache_dir;
    my $id = $self->id;

    my $lock_fh = Socialtext::File::write_lock("$cache_dir/.lock");

    for my $version (keys %blobs) {
        my $file = "$cache_dir/$id-$version.png";
        my $temp = "$file.tmp";
        Socialtext::File::set_contents_binary($temp, $blobs{$version});
        rename $temp, $file;
        if ($self->can('synonyms')) {
            my @symlinks = map { s#/#\%2f#g; "$cache_dir/$_-$version.png" }
                           $self->synonyms;
            for my $link (@symlinks) {
                unlink $link; # fail = ok
                link $file => $link;
            }
        }
    }
}

sub load {
    my ($self, $version) = @_;
    die "version required" unless $version;

    my $table = $self->table;
    my $id_column = $self->id_column;

    my $sth = sql_execute(
        "SELECT $version FROM $table WHERE $id_column = ?", $self->id
    );
    my $blob;
    $sth->bind_columns(\$blob);
    $sth->fetch();
    $sth->finish();

    $self->default(1) unless $blob;

    my $blob_ref = $blob ? \$blob : $self->DefaultPhoto($version);
    $self->_save_cache($version => $blob_ref);
    return $blob_ref;
}

sub ClearCache {
    my $class = shift;
    my $cache_dir = $class->cache_dir
        or die "can't get cache_dir; is it a class-method?";

    my $lock_fh = Socialtext::File::write_lock("$cache_dir/.lock");
    my $temp_dir = $cache_dir . ".tmp" . $$;
    rename $cache_dir => $temp_dir;
    undef $lock_fh;

    Socialtext::File::ensure_directory($cache_dir);
    remove_tree($temp_dir);
}

{
    package Socialtext::Avatar::Common;
    use Moose::Role;

    requires qw(load);
    use constant versions => [qw(small large)];

    has 'small' => (
        is => 'rw', isa => 'ScalarRef',
        lazy_build => 1,
    );
    sub _build_small { $_[0]->load('small') }

    has 'large' => (
        is => 'rw', isa => 'ScalarRef',
        lazy_build => 1,
    );
    sub _build_large { $_[0]->load('large') }

    no Moose::Role;
}

package Socialtext::Avatar;

1;

__END__

=head1 NAME

Socialtext::Avatar - Role for storing user/group/account avatars.

=head1 SYNOPSIS

  use constant ROLES => ('Socialtext::Avatar');
  ...
  with(ROLES);

=head1 DESCRIPTION

Saves the image blob to the database and to a cached version on disk.

=cut
