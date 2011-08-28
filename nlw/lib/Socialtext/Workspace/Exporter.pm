package Socialtext::Workspace::Exporter;
use Moose;
use MooseX::StrictConstructor;

use File::Temp ();
use File::chdir; # for magic $CWD
use File::Basename qw/basename/;
use File::Copy qw/copy/;
use File::Path qw/make_path/;
use YAML ();

use Socialtext::SQL qw/:exec/;
use Socialtext::Base ();
use Socialtext::Permission ();
use Socialtext::Role ();
use Socialtext::PreferencesPlugin;
use Socialtext::PageRevision;
use Socialtext::Attachments;
use Socialtext::Timer qw/time_scope/;

use namespace::clean -except => 'meta';

# name to export under (may differ from workspace->name):
has 'name' => (is => 'rw', isa => 'Str', required => 1);

# the workspace being exported
has 'workspace' => (
    is => 'ro', isa => 'Socialtext::Workspace',
    required => 1,
    handles => [qw(workspace_id title)],
);

# built from the workspace:
has 'hub' => (is => 'ro', isa => 'Socialtext::Hub', lazy_build => 1);

has 'tmpdir' => (is => 'ro', isa => 'Object|Str', lazy_build => 1);
has 'meta_filename' => (is => 'rw', isa => 'Str', lazy_build => 1);

sub _build_tmpdir {
    my $self = shift;
    (my $name = $self->name) =~ s/[^a-z0-9_-]+//g;
    File::Temp->newdir("/tmp/export-$name-XXXXXX", CLEANUP => 1);
}

sub _build_hub {
    my $self = shift;
    my ($main, $hub) = $self->workspace->_main_and_hub();
    $self->{__main} = $main;
    return $hub;
}

sub filename {
    my $self = shift;
    Socialtext::File::catfile($self->tmpdir."", @_);
}
sub ws_dir {
    my ($self, $thingy, @rest) = @_;
    # e.g. $thingy == 'data': $tmpdir/data/$name
    Socialtext::File::catdir($self->tmpdir."",$thingy,$self->name,@rest);
}

sub BUILD {
    my $self = shift;
    $self->name(lc $self->name);
}

sub to_tarball {
    my ($self, $tarball) = @_;
    my $t = time_scope 'export_tarball';

    # Keep the order of these consistent:
    $self->$_ for map { "export_$_" } # e.g. export_info
    qw( info users permissions meta
        user_prefs breadcrumbs
        pages page_counters
        attachments
    );

    {
        my $t2 = time_scope 'pack_tarball';
        local $CWD = $self->tmpdir."";
        my $flags = ($tarball =~ /\.gz/) ? "zcf" : "cf";
        system("tar $flags $tarball *")
            and die "tar $flags failed ($?)";
    }

    return $tarball;
}

sub _save_yaml {
    my ($file, $data) = @_;
    open my $fh, '>:utf8', $file or die "Cannot write to $file: $!";
    print $fh YAML::Dump($data) or die "Cannot write to $file: $!";
    close $fh or die "Cannot write to $file: $!";
}

my %skip_cols = map { $_ => 1 } qw/workspace_id user_set_id/;
sub export_info {
    my $self = shift;

    my $ws = $self->workspace;
    my %export;
    for my $c ( grep { !$skip_cols{$_} } @Socialtext::Workspace::COLUMNS ) {
        $export{$c} = $ws->$c;
    }
    $export{creator_username} = $ws->creator->username;
    $export{account_name} = $ws->account->name;
    $export{name} = $self->name; # so we can override
    $export{plugins} = { map { $_ => 1 } $ws->plugins_enabled };

    if (my $logo_file = $ws->logo_filename) {
        my $basename = basename($logo_file);
        $export{logo_filename} = $basename;
        my $new_logo = $self->filename($basename);
        copy($logo_file => $new_logo)
            or die "Could not copy $logo_file to $new_logo: $!\n";
    }

    $self->hub->pluggable->hook('nlw.export_workspace', [$ws,\%export,$self]);

    _save_yaml( $self->filename($self->name.'-info.yaml'), \%export );
}

sub user_to_export {
    my ($self, $user) = @_;
    my $adapter = Socialtext::Pluggable::Adapter->new;
    $adapter->make_hub($user, $self->workspace);
    my $plugin_prefs = {};
    $adapter->hook('nlw.export_user_prefs', [$plugin_prefs]);

    my $exported_user = $user->to_hash(want_private_fields => 1);
    delete $exported_user->{user_id};
    $exported_user->{plugin_prefs} = $plugin_prefs if %$plugin_prefs;

    $exported_user->{restrictions} = [
        map { $_->to_hash } $user->restrictions->all
    ];

    return $exported_user;
}

sub export_users {
    my $self = shift;

    require Socialtext::Pluggable::Adapter;
    my $ws = $self->workspace;
    my $user_roles = $ws->user_roles(direct => 1);
    my @export;
    while (my $pair = $user_roles->next) {
        my ($user, $role) = @$pair;
        my $exported_user = $self->user_to_export($user);
        $exported_user->{role_name} = $role->name;
        push @export, $exported_user;
    }

    $self->hub->pluggable->hook('nlw.export_workspace_users',
        [$ws,\@export,$self]);

    _save_yaml($self->filename($self->name.'-users.yaml'), \@export);
}

sub export_permissions {
    my $self = shift;

    my $ws = $self->workspace;

    my $sth = sql_execute(q{
        SELECT role_id, permission_id
        FROM "WorkspaceRolePermission" WHERE workspace_id = ?
    }, $ws->workspace_id);

    my @export;
    my @lock_export;
    my @self_join_export;
    for my $r (@{$sth->fetchall_arrayref || []}) {
        my $p = Socialtext::Permission->new(
            permission_id => $r->[1]);

        # We cannot export 'new' permissions using the default method; they
        # must be placed in separate files in order for exports to remain
        # backwards-compabible.
        my $array_ref = \@export;
        $array_ref = \@lock_export if $p->name eq 'lock';
        $array_ref = \@self_join_export if $p->name eq 'self_join';

        push @$array_ref, {
            role_name => Socialtext::Role->new(role_id => $r->[0])->name,
            permission_name => $p->name,
        }
    }

    my $name = $self->name;
    _save_yaml($self->filename("$name-permissions.yaml"), \@export);

    # Here's where we deal with the 'new' permissions:
    _save_yaml($self->filename("$name-lock-permissions.yaml"),\@lock_export);
    _save_yaml($self->filename("$name-self-join-permissions.yaml"),
        \@self_join_export);
}

sub export_meta {
    my $self = shift;
    # create this unused, legacy file:
    _save_yaml($self->filename('meta.yaml'), { has_lock => 1 });
}

sub export_user_prefs {
    my $self = shift;

    my $ws = $self->workspace;
    my $ws_dir = $self->ws_dir('user');
    make_path($ws_dir) or die "Cannot make $ws_dir: $!";
    my $users = $ws->users(direct => 1);
    while (my $user = $users->next) {
        my $prefs = Socialtext::PreferencesPlugin->Workspace_user_prefs($user,$ws);
        next unless $prefs && %$prefs;

        # We export these prefs to the `preferences.dd` format (instead of 
        # yaml, say) to preserve backwards compatibility of workspace exports..
        my $user_dir = "$ws_dir/" . $user->email_address . '/preferences';
        make_path($user_dir) or die "Can't make $user_dir: $!";
        Socialtext::Base->dumper_to_file("$user_dir/preferences.dd", $prefs);
    }
}

sub export_breadcrumbs {
    my $self   = shift;

    my $sth = sql_execute(q{
         SELECT users.email_address AS email, page_id
           FROM breadcrumb
           JOIN users ON (breadcrumb.viewer_id = users.user_id)
           WHERE breadcrumb.workspace_id = ?
           ORDER BY last_viewed DESC
    }, $self->workspace->workspace_id);
    my %breadcrumbs;
    while (my $row = $sth->fetchrow_hashref) {
        push @{ $breadcrumbs{$row->{email}} }, $row->{page_id};
    }

    my $bc_dir = $self->ws_dir('user');
    for my $email (keys %breadcrumbs) {
        my $trail_dir = "$bc_dir/$email";
        make_path($trail_dir) unless -d $trail_dir;
        my $trail_file = "$trail_dir/.trail";
        Socialtext::File::set_contents_utf8($trail_file,
            join("\n", @{ $breadcrumbs{$email} }) . "\n");
    }
}

sub export_pages {
    my $self = shift;

    my $ws = $self->workspace;
    my $ws_dir = $self->ws_dir('data');
    make_path($ws_dir);

    my $sth = sql_execute(q{
         SELECT }.Socialtext::PageRevision::SELECT_COLUMNS_STR.q{
           FROM page_revision
           WHERE workspace_id = ?
    }, $ws->workspace_id);

    while (my $row = $sth->fetchrow_hashref) {
        my $page_dir = "$ws_dir/$row->{page_id}";
        make_path($page_dir);
        my $filename = "$page_dir/$row->{revision_id}.txt";
        open my $fh, '>:mmap:utf8', $filename
            or die "Can't write $filename: $!";
        Socialtext::PageRevision->Export_to_file_from_row($row => $fh);
        close $fh or die "Can't write $filename: $!";
    }
}

sub export_page_counters {
    my $self = shift;
    my $ws = $self->workspace;

    my $sth2 = sql_execute(q{
        SELECT page_id, views FROM page WHERE workspace_id = ?
    }, $ws->workspace_id);
         
    my $counter_dir = $self->ws_dir('plugin' => 'counter');
    make_path($counter_dir);
    while (my $row = $sth2->fetchrow_arrayref) {
        my ($page_id, $views) = @$row;
        my $page_counter_dir = "$counter_dir/$page_id";
        mkdir $page_counter_dir or die "can't make $page_counter_dir: $!";
        Socialtext::File::set_contents("$page_counter_dir/COUNTER",
            "#COUNTER-1.0\n$views\n");
    }
}

sub export_attachments {
    my $self = shift;
    my $tmpdir = shift;
    my $name   = shift;

    my $plugin_dir = $self->ws_dir('plugin' => 'attachments');
    make_path($plugin_dir) or die "Cannot make $plugin_dir: $!";
    my $ws = $self->workspace;

    my $sth = sql_execute(q{
        SELECT }.Socialtext::Attachments::COLUMNS_STR.q{,
               created_at AT TIME ZONE 'UTC' || '+0000' AS created_at_utc
          FROM page_attachment pa
          JOIN attachment a USING (attachment_id)
         WHERE workspace_id = $1
    }, $ws->workspace_id);

    my $atts = $self->hub->attachments;
    while (my $row = $sth->fetchrow_hashref()) {
        $row->{workspace} = $ws;
        my $att = $atts->_new_from_row($row);
        my $dir = "$plugin_dir/".$att->page_id;
        unless (-d $dir) {
            make_path($dir) or die "can't write attachment: $dir $!";
        }
        $att->export_to_dir($dir);
    }
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

__END__

=head1 NAME

Socialtext::Workspace::Exporter - Export workspace to a tarball

=head1 SYNOPSIS

  use Socialtext::Workspace::Exporter
  my $wx = Socialtext::Workspace::Exporter->new(
      workspace => $ws,
      name => $ws->name,
  );
  $wx->to_tarball("/path/to/tarball.gz");

=head1 DESCRIPTION

Export the workspace into the specified tarball.

