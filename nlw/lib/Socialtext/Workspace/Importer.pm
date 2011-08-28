package Socialtext::Workspace::Importer;
# @COPYRIGHT@

use strict;
use warnings;
use base 'Socialtext::Base';

use Encode::Guess qw( ascii iso-8859-1 utf8 );
use File::chdir;
use Cwd;
use Socialtext::File::Copy::Recursive ();
use Readonly;
use Socialtext::SQL qw(:txn :exec);
use Socialtext::Validate qw( validate FILE_TYPE BOOLEAN_TYPE SCALAR_TYPE OBJECT_TYPE );
use Socialtext::AppConfig;
use Socialtext::Workspace;
use Socialtext::Exceptions qw/rethrow_exception/;
use Socialtext::Search::AbstractFactory;
use Socialtext::Log qw(st_log);
use Socialtext::Timer;
use Socialtext::System qw/shell_run/;
use Socialtext::Page::TablePopulator;
use Socialtext::User::Default::Users;
use Socialtext::User;
use Socialtext::User::Restrictions;
use Socialtext::PreferencesPlugin;
use YAML ();

# This should stay in sync with $EXPORT_VERSION in ST::Workspace.
Readonly my $MAX_VERSION => 1;

{
    Readonly my $spec => {
        name        => SCALAR_TYPE(optional => 1),
        tarball     => FILE_TYPE,
        overwrite   => BOOLEAN_TYPE(default => 0),
        noindex     => BOOLEAN_TYPE(default => 0),
        index_async => BOOLEAN_TYPE(default => 0),
        hub         => OBJECT_TYPE,
    };
    sub new {
        my $class = shift;
        my %p = validate( @_, $spec );

        die "Tarball file does not exist ($p{tarball})\n"
            unless -f $p{tarball};

        my ( $old_name, $version ) = $p{tarball} =~ /([\w-]+)(?:\.(\d+))?\.tar/
            or die
            "Cannot determine workspace name and version from tarball name: $p{tarball}";
        $version ||= 0;

        my $new_name = lc( $p{name} || $old_name );

        if ( $version > $MAX_VERSION ) {
            die "Cannot import a tarball with a version greater than $MAX_VERSION\n";
        }

        my $ws = Socialtext::Workspace->new( name => $new_name );
        if ( $ws && ! $p{overwrite} ) {
            die "Cannot restore $new_name workspace, it already exists.\n";
        }

        my $tarball = Cwd::abs_path( $p{tarball} );

        return bless {
            new_name    => $new_name,
            old_name    => $old_name,
            workspace   => $ws,
            tarball     => $tarball,
            version     => $version,
            noindex     => $p{noindex},
            index_async => $p{index_async},
            hub         => $p{hub},
            },
            $class;
    }
}

# I'd like to call this import() but then Perl calls it when the
# module is loaded.
sub import_workspace {
    my $self = shift;
    my $timer = Socialtext::Timer->new;

    eval {
        my $old_cwd = getcwd();
        local $CWD = File::Temp::tempdir( CLEANUP => 1 );
        system( 'tar', 'xzf', $self->{tarball} );

        # We have an exported workspace from before workspace info was in
        # the DBMS
        die 'Cannot import old format of workspace export'
            if -d "workspace/$self->{old_name}";

        my @users = $self->_import_users();
        $self->_create_workspace();
        $self->Import_user_workspace_prefs(
            "$CWD/user/$self->{old_name}",
            $self->{workspace}
        );
        $self->_populate_db_metadata();
        $self->_rebuild_page_links();

        for my $u (@users) {
            my ($user, $rolename, $indirect) = @{$u};
            unless ($indirect) {
                # If a User has an "indirect" Role, they have access to the
                # Workspace from some other means (e.g. a Group Role), so
                # don't add a Role for them here.

                # Support backwards compatibility for old style
                # 'workspace_admin'
                $rolename = 'admin' if $rolename eq 'workspace_admin';

                $self->{workspace}->assign_role_to_user(
                    user => $user,
                    role => Socialtext::Role->new( name => $rolename ),
                );
            }
        }

        unless ($self->{noindex}) {
            if ($self->{index_async}) {
                $self->{hub}->current_workspace( $self->{workspace} );
                $self->{workspace}->reindex_async( $self->{hub}, 'live' );
            }
            else {
                chdir( $old_cwd );
                my $ws_name = $self->{workspace}->name;
                my @indexers
                    = Socialtext::Search::AbstractFactory->GetIndexers(
                    $ws_name);
                for my $idx (@indexers) {
                    $idx->hub->current_user( Socialtext::User->SystemUser );
                    $idx->index_workspace( $ws_name );
                }
            }
        }

        st_log()
            ->info( 'IMPORT,WORKSPACE,workspace:'
                . $self->{new_name} . '('
                . $self->{workspace}->workspace_id
                . '),[' . $timer->elapsed . ']');

        my $adapter = Socialtext::Pluggable::Adapter->new;
        $adapter->make_hub(Socialtext::User->SystemUser(), $self->{workspace});
        $adapter->hook('nlw.import_workspace.after', [$self->{workspace}, $self->{info}]);
    };
    if (my $err = $@) {
        if ($self->{workspace}) {
            eval { $self->{workspace}->delete };
            warn $@ if $@;
        }
        die "Error importing workspace $self->{new_name}: $err";
    }
    return $self->{workspace};
}

sub _create_workspace {
    my $self = shift;

    return if $self->{workspace};

    my $info = $self->_load_yaml( $self->_workspace_info_file() );
    my $creator = Socialtext::User->new( username => $info->{creator_username} );
    $creator ||= Socialtext::User->SystemUser();

    my $account = Socialtext::Account->new( name => $info->{account_name} );
    $account ||= $self->hub->account_factory->create( 
        name => $info->{account_name} );

    my $ws = Socialtext::Workspace->create(
        title => $info->{title},
        name => $self->{new_name},
        created_by_user_id => $creator->user_id,
        account_id         => $account->account_id,
        skip_default_pages => 1,
        dont_add_creator   => 1,
    );

    my %update;
    my @to_update = grep { $_ ne 'logo_uri' 
            and $_ ne 'name' 
            and $_ ne 'created_by_user_id' 
            and $_ ne 'account_id' }
        map { $_ } @Socialtext::Workspace::COLUMNS;
    for my $c (@to_update) {
        $update{$c} = $info->{$c}
            if exists $info->{$c};
    }

    $ws->update( %update );

    if ( my $logo_filename = $info->{logo_filename} ) {
        $ws->set_logo_from_file(
            filename   => $logo_filename,
        );
    }
    elsif ( $info->{logo_uri} ) {
        $ws->set_logo_from_uri( uri => $info->{logo_uri} );
    }

    my $adapter = Socialtext::Pluggable::Adapter->new;
    $adapter->make_hub(Socialtext::User->SystemUser(), $ws);
    for my $plugin (keys %{ $info->{plugins}}) {
        eval { $ws->enable_plugin($plugin) };
    }

    $self->{workspace} = $ws;
    $self->{info} = $info;
    $self->_set_permissions();
    $adapter->hook('nlw.import_workspace', [$ws, $info]);
}

sub _workspace_info_file { $_[0]->{old_name} . '-info.yaml' }

sub Import_user_workspace_prefs {
    my $class     = shift;
    my $path      = shift;
    my $workspace = shift;

    my @files = glob("$path/*/preferences/preferences.dd");
    for my $f (@files) {
        (my $email = $f) =~ s#^.+/([^/]+)/preferences/preferences\.dd$#$1#;

        my $user = Socialtext::User->new(email_address => $email);
        if ($user and $workspace->real) {
            my $is_in_db = sql_singlevalue('
                SELECT 1 FROM user_workspace_pref
                 WHERE user_id = ? AND workspace_id = ?
                 ', $user->user_id, $workspace->workspace_id,
            );

            if ( !$is_in_db ) {
                eval {
                    my $prefs = do $f;
                    die "can't load prefs, exception: $@" if $@;
                    die "can't load prefs: $!" unless ref($prefs) eq 'HASH';
                    Socialtext::PreferencesPlugin->Store_workspace_user_prefs(
                        $user, $workspace, $prefs);
                };
                if ($@) {
                    st_log->error("unable to import preferences for user ".
                        "'$email' in workspace '".$workspace->name."'".
                        ": $@");
                }
            }
        }

        (my $pref_dir = $f) =~ s#/preferences\.dd$##;
        for my $file (glob("$pref_dir/*")) {
            unlink $file or warn "Could not unlink $file: $!";
        }
        rmdir $pref_dir or warn "Could not rmdir $pref_dir: $!";
    }

    my @pref_dirs = glob("$path/*/preferences");
    for my $d (@pref_dirs) {
        rmdir $d or warn "Could not rmdir $d $!";

        # Try to also delete the user dir, which may now be empty.
        (my $user_dir = $d) =~ s#/preferences$##;
        rmdir $user_dir;
    }
}

sub _load_yaml {
    my $self = shift;
    my $file = shift;

    my $mode = $self->{version} >= 1 ? '<:utf8' : '<';

    open my $fh, $mode, $file
        or die "Cannot read $file: $!";

    my $yaml = do { local $/; <$fh> };
    if ( $self->{version} < 1 ) {
        my $decoder = Encode::Guess->guess($yaml);
        $yaml = ref $decoder
            ? $decoder->decode($yaml)
            : Encode::decode( 'utf8', $yaml );
    }

    return YAML::Load($yaml);
}

sub _set_permissions {
    my $self = shift;

    my $perms = $self->_load_yaml( $self->_permissions_file() );
    $perms = $self->_add_missing_role_for_perms($perms);

    # Also look for lock permissions
    my $lock_perm_file = $self->_lock_permissions_file;
    if (-e $lock_perm_file) {
        my $lock_perms = $self->_load_yaml($lock_perm_file);
        push @$perms, @$lock_perms;
    }

    # ... and self_join permissions. Methinks we have a pattern here.
    my $self_join_perm_file = $self->_self_join_permissions_file;
    if (-e $self_join_perm_file) {
        my $self_join_perms = $self->_load_yaml($self_join_perm_file);
        push @$perms, @$self_join_perms;
    }

    sql_txn {
        sql_execute(
            'DELETE FROM "WorkspaceRolePermission" WHERE workspace_id = ?',
            $self->{workspace}->workspace_id,
        );

        my $sql =
            'INSERT INTO "WorkspaceRolePermission" (workspace_id, role_id, permission_id) VALUES (?,?,?)';
        for my $p (@$perms) {
            # In older versions of workspace exports, the 'admin' role was
            # called 'workspace_admin', make sure we're compatible with that.
            my $role_name = ( $p->{role_name} eq 'workspace_admin' )
                ? 'admin' : $p->{role_name};

            my $role = Socialtext::Role->new(name => $role_name);
            my $permission = Socialtext::Permission->new(name => $p->{permission_name});

            next unless $permission and $role;
            sql_execute(
                $sql,
                $self->{workspace}->workspace_id,
                $role->role_id,
                $permission->permission_id,
            );
        }

        my $meta = {};
        eval { $meta = $self->_load_yaml( $self->_meta_file() ); };

        unless ( exists $meta->{has_lock} && $meta->{has_lock} ) {
            sql_execute( $sql, $self->{workspace}->workspace_id,
                Socialtext::Role->new(name => 'admin')->role_id,
                Socialtext::Permission->new(name => 'lock')->permission_id,
            );
        }

    };
}

sub _add_missing_role_for_perms {
    my $self = shift;
    my $set  = shift;

    # map to a hash for easy duplication
    my %set_as_hash = ();
    for my $item (@$set) {
        my $role_name = $item->{role_name};
        $set_as_hash{$role_name} = [] unless $set_as_hash{$role_name};
        push(@{$set_as_hash{$role_name}}, $item->{permission_name});
    }

    $set_as_hash{account_user} = $set_as_hash{authenticated_user}
        unless $set_as_hash{account_user};

    # re-map our set
    my @remapped = ();
    for my $role_name (keys %set_as_hash) {
        my $names = $set_as_hash{$role_name};
        push @remapped, (
            map { +{permission_name=>$_, role_name=>$role_name}} @$names );
    }

    return \@remapped;
}

sub _populate_db_metadata {
    my $self = shift;

    Socialtext::Timer->Continue('populate_db');
    local $Socialtext::Page::TablePopulator::Noisy = 0;
    my $populator = Socialtext::Page::TablePopulator->new(
        workspace_name => $self->{new_name},
        data_dir       => $CWD,
        old_name       => $self->{old_name},
    );
    $populator->populate( recreate => 1 );
    Socialtext::Timer->Pause('populate_db');
}

sub _rebuild_page_links {
    my $self = shift;
    Socialtext::JobCreator->insert(
        'Socialtext::Job::Upgrade::RebuildPageLinks',
        { workspace_id => $self->{workspace}->workspace_id }
    );
}

sub _permissions_file { return $_[0]->{old_name} . '-permissions.yaml' }

sub _lock_permissions_file {
    return $_[0]->{old_name} . '-lock-permissions.yaml'
}

sub _self_join_permissions_file {
    return $_[0]->{old_name} . '-self-join-permissions.yaml'
}

sub _meta_file { return 'meta.yaml' }

sub _import_users {
    my $self = shift;

    my $users = $self->_load_yaml( $self->_users_file() );

    my @users;
    for my $info (@$users) {
        next unless Socialtext::User::Default::Users->CanImportUser($info);

        delete $info->{primary_account_id};
        my $plugin_prefs = delete($info->{plugin_prefs}) || {};
        my $indirect     = delete($info->{indirect})     || 0;
        my $restrictions = delete($info->{restrictions}) || [];

        my $user = Socialtext::User->new( username => $info->{username} )
                || Socialtext::User->new( email_address => $info->{email_address} )
                || Socialtext::User->Create_user_from_hash( $info );
        push @users, [ $user, $info->{role_name}, $indirect ];

        if (keys %$plugin_prefs) {
            my $adapter = Socialtext::Pluggable::Adapter->new;
            $adapter->make_hub($user);
            $adapter->hook('nlw.import_user_prefs', [$plugin_prefs]);
        }

        foreach my $r (@{$restrictions}) {
            Socialtext::User::Restrictions->CreateOrReplace( {
                user_id => $user->user_id,
                %{$r},
            } );
        }
    }

    return @users;
}

sub _users_file { $_[0]->{old_name} . '-users.yaml' }

1;

__END__
