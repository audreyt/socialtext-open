# @COPYRIGHT@
package Socialtext::Account;
use Moose;
use Carp qw(croak);
use Readonly;
use Socialtext::Authz;
use Socialtext::Cache;
use Socialtext::Exceptions qw( data_validation_error );
use Socialtext::Schema;
use Socialtext::SQL qw(:exec :txn);
use Socialtext::SQL::Builder qw(sql_nextval sql_abstract sql_insert_many);
use Socialtext::Helpers;
use Socialtext::String;
use Socialtext::User::Default::Users;
use Socialtext::User;
use Socialtext::UserSet qw/:const/;
use Socialtext::MultiCursor;
use Socialtext::Validate qw( validate SCALAR_TYPE );
use Socialtext::Log qw( st_log );
use Socialtext::l10n qw(loc);
use Socialtext::SystemSettings qw(set_system_setting get_system_setting);
use Socialtext::Skin;
use Socialtext::Timer qw/time_scope/;
require Socialtext::Pluggable::Adapter;
use Socialtext::AccountLogo;
use Socialtext::Account::Roles;
use Socialtext::Role;
use Socialtext::UserSet qw/:const/;
use YAML qw/DumpFile LoadFile/;
use MIME::Base64 ();
use Socialtext::JSON::Proxy::Helper;
use File::Basename qw(dirname);
use namespace::clean -except => 'meta';

our $VERSION = '0.01';

Readonly our @ACCT_COLS => qw(
    account_id
    name
    skin_name
    is_system_created
    email_addresses_are_hidden
    is_exportable
    allow_invitation
    account_type
    restrict_to_domain
    pref_blob

    desktop_logo_uri
    desktop_header_gradient_top
    desktop_header_gradient_bottom
    desktop_bg_color
    desktop_2nd_bg_color
    desktop_text_color
    desktop_link_color
    desktop_highlight_color

    user_set_id
);

my %ACCT_COLS = map { $_ => 1 } @ACCT_COLS;

foreach my $column ( grep !/^skin_name$/, @ACCT_COLS ) {
    has $column => (is => 'rw', isa => 'Any');
}
has 'skin_name' => (is => 'rw', isa => 'Str', lazy_build => 1);

with 'Socialtext::UserSetContainer' => {
    # Moose 0.89 renamed to -excludes and -alias
    ($Moose::VERSION >= 0.89 ? '-excludes' : 'excludes')
        => [qw( add_account assign_role_to_account )],
};


my @TYPES = ('Standard', 'Free 50', 'Placeholder', 'Paid', 'Comped', 'Trial', 'Unknown');
my %VALID_TYPE = map { $_ => 1 } @TYPES;
sub Types { [ @TYPES ] }

# For Account exports:
Readonly my $EXPORT_VERSION => 1;

Readonly my @RequiredAccounts => qw( Unknown Socialtext Deleted );
sub RequiredAccounts { @RequiredAccounts }
sub EnsureRequiredDataIsPresent {
    my $class = shift;

    for my $name (@RequiredAccounts) {
        next if $class->new( name => $name );

        my $acct = $class->create(
            name              => $name,
            is_system_created => 1,
        );
        $acct->enable_plugin('dashboard');
        $acct->enable_plugin('widgets');
    }

    foreach my $mod (qw( Permission Role User::Default::Factory )) {
        my $class = "Socialtext::$mod";
        eval "require $class";
        die $@ if $@;

        if ($class->can('EnsureRequiredDataIsPresent')) {
            $class->EnsureRequiredDataIsPresent;
        }
    }

    if ($class->Default->name eq 'Unknown') {
        # Explicit requires here to avoid extra run-time dependencies
        require Socialtext::Hostname;
        my $acct = $class->create(
            name => Socialtext::Hostname::fqdn(),
            # This is not a system account, it is intended to be used.
            is_system_created => 0,
        );
        $acct->enable_plugin('dashboard');
        $acct->enable_plugin('widgets');

        set_system_setting('default-account', $acct->account_id);
    }
}

sub Resolve {
    my $class = shift;
    my $maybe_account = shift;
    my $account;

    if ( $maybe_account =~ /^\d+$/ ) {
        $account = Socialtext::Account->new( account_id => $maybe_account );
    }

    $account ||= Socialtext::Account->new( name => $maybe_account );
    return $account;
}

around 'PluginsEnabledForAll' => sub {
    my $orig = shift;
    return $orig->($_[0], 'Account');
};

around 'EnablePluginForAll' => \&sql_txn;
sub EnablePluginForAll {
    my ($class, $plugin) = @_;

    require Socialtext::Pluggable::Adapter;
    my $adapter = Socialtext::Pluggable::Adapter->new;
    my $plugin_class = $adapter->plugin_class($plugin);
    $class->_check_plugin_scope($plugin, $plugin_class, 'account');

    my @plugins = (
        $plugin, $plugin_class->dependencies, $plugin_class->enables,
    );

    my ($sql, @bind) = sql_abstract->delete(user_set_plugin => {
        plugin => { -in => \@plugins }
    });
    sql_execute($sql, @bind);

    # This makes enabling the people plugin a bit slow because for some reason
    # it regenerates all the fields
    if ($plugin_class->can('EnablePlugin')) {
        my $all = $class->All;
        while (my $account = $all->next) {
            $plugin_class->EnablePlugin($account)
        }
    }

    my $sth = sql_execute(q{SELECT user_set_id, account_id FROM "Account"});
    my @insert;
    while (my $account = $sth->fetchrow_hashref) {
        push @insert, [$account->{user_set_id}, $_] for @plugins;
    }

    sql_insert_many(user_set_plugin => ['user_set_id', 'plugin'], \@insert);

    Socialtext::Cache->clear('authz_plugin');
    Socialtext::Cache->clear('user_accts');
    set_system_setting( "$plugin-enabled-all", 1 );
}

around 'EnablePluginForAll' => \&sql_txn;
sub DisablePluginForAll {
    my ($class, $plugin) = @_;

    require Socialtext::Pluggable::Adapter;
    my $plugin_class = Socialtext::Pluggable::Adapter->plugin_class($plugin);
    $class->_check_plugin_scope($plugin, $plugin_class, 'account');

    my @plugins = ($plugin, $plugin_class->reverse_dependencies);

    # Noop so far
    if ($plugin_class->can('DisablePlugin')) {
        my $all = $class->All;
        while (my $account = $all->next) {
            $plugin_class->DisablePlugin($account)
        }
    }

    my ($sql, @bind) = sql_abstract->delete(user_set_plugin => {
        plugin => { -in => \@plugins }
    });
    sql_execute($sql, @bind);

    Socialtext::Cache->clear('authz_plugin');
    Socialtext::Cache->clear('user_accts');
    set_system_setting( "$plugin-enabled-all", 0 );
}

sub _build_skin_name { get_system_setting('default-skin') }

has 'logo' => (
    is => 'ro', isa => 'Socialtext::AccountLogo',
    lazy_build => 1,
);

sub _build_logo {
    my $self = shift;
    return Socialtext::AccountLogo->new(account => $self);
}

has 'plugin_preferences' => (
    is => 'ro', isa => 'HashRef',
    lazy_build => 1,
);

sub _build_plugin_preferences {
    my $self = shift;
    return Socialtext::Pluggable::Adapter->new->account_preferences(
        account => $self, with_defaults => 1,
    );
}

sub custom_workspace_skins {
    my $self = shift;
    my %p    = @_;

    my $workspaces = $self->workspaces;
    my %skins_hash = ();
    while ( my $ws = $workspaces->next ) {
        my $ws_skin = $ws->skin_name;
        unless ( $ws_skin eq $self->skin_name  || $ws_skin eq '' ) {
           $skins_hash{ $ws_skin } = []
               unless defined $skins_hash{ $ws_skin };

           push @{ $skins_hash{ $ws_skin } }, $ws;
        }
    }

    return \%skins_hash if $p{include_workspaces};
    return [ keys %skins_hash ];
}

sub reset_skin {
    my ($self, $skin_name) = @_;
    
    $self->update(skin_name => $skin_name);

    my $skin = Socialtext::Skin->new(name => $skin_name);
    $self->update(
        map {
            $_ => $skin->info_param($_)
        } grep { /^desktop_/ } @ACCT_COLS,
    );

    my $workspaces = $self->workspaces;

    while (my $workspace = $workspaces->next) {
        $workspace->update(skin_name => '');
    }
    return $self->skin_name;
}

sub prefs {
    my $self = shift;
    require Socialtext::Prefs::Account;
    return Socialtext::Prefs::Account->new(account=>$self);
}

sub workspaces {
    my $self = shift;
    return Socialtext::Workspace->ByAccountId( 
        account_id => $self->account_id, 
        @_ 
    );
}

sub workspace_count {
    my $self = shift;
    return $self->workspaces->count();
}

around 'groups', 'group_count' => sub {
    my $code = shift;
    my $self = shift;
    my %p = @_;
    $p{direct} = 1 unless exists $p{direct};
    $code->($self, %p);
};
# ' # <= fix vim highlighting

sub invite {
    my $self = shift;
    my %p    = @_;

    require Socialtext::AccountInvitation;
    return Socialtext::AccountInvitation->new(
        account    => $self,
        from_user  => $p{from_user},
        extra_text => $p{extra_text},

        # optional arguments.
        ($p{template} ? (template => $p{template}) : ()),
        ($p{viewer} ? (viewer => $p{viewer}) : ()),
    );
}

sub _primary_user_ids {
    my $self = shift;
    my $sth = sql_execute(q{
        SELECT DISTINCT user_id
        FROM "UserMetadata"
        WHERE primary_account_id = ?
    }, $self->account_id);
    my @ids = map { $_->[0] } @{$sth->fetchall_arrayref || []};
    return \@ids;
}

around 'user_ids' => sub {
    my $call = shift;
    my ($self,%p) = @_;
    return $call->(@_) unless $p{primary_only};
    
    my $t = time_scope('acct_user_ids');
    return $self->_primary_user_ids();
};

around 'users' => sub {
    my $call = shift;
    my ($self,%p) = @_;
    return $call->(@_) unless $p{primary_only};
    
    my $t = time_scope('acct_users');
    return Socialtext::MultiCursor->new(
        iterables => $self->_primary_user_ids(),
        apply     => sub {
            return Socialtext::User->new(user_id => $_[0]);
        },
    );
};

sub to_hash {
    my $self = shift;
    my %p = @_;

    if ($p{minimal}) {
        return +{
            account_id => $self->account_id,
            name => $self->name,
        };
    }
    else {
        my $hash = {
            map { $_ => $self->$_ } @ACCT_COLS
        };
        return $hash;
    }
}

sub is_placeholder {
    my $self = shift;
    return $self->account_type eq 'Placeholder';
}

# wrap methods in UserSetContainer
# 'after' works because the default "scope" is 'account'
after 'enable_plugin','disable_plugin' => sub {
    my $self = shift;
    Socialtext::JSON::Proxy::Helper->ClearForAccount($self->account_id);
    Socialtext::Helpers->clean_user_frame_cache();
};
# ' # <= fix vim highlighting

sub export {
    my $self = shift;
    my %opts = @_;
    my $dir = $opts{dir};
    my $hub = $opts{hub};

    my $export_file = $opts{file} || "$dir/account.yaml";

    my $logo_ref = $self->logo->logo;
    my $data     = {
        # versioning
        version => $EXPORT_VERSION,
        # data
        name                       => $self->name,
        is_system_created          => $self->is_system_created,
        skin_name                  => $self->skin_name,
        email_addresses_are_hidden => $self->email_addresses_are_hidden,
        users                      => $self->all_users_as_hash(want_private_fields => 1),
        logo                       => MIME::Base64::encode($$logo_ref),
        allow_invitation           => $self->allow_invitation,
        pref_blob                  => $self->pref_blob,
        plugins                    => [ $self->plugins_enabled ],
        plugin_preferences         =>
            Socialtext::Pluggable::Adapter->new->account_preferences(
                account       => $self,
                with_defaults => 0, # do _not_ export defaults.
            ),
        all_users_workspaces       =>
            [ map { $_->name } @{ $self->all_users_workspaces } ],
        (map { $_ => $self->$_ } grep {/^desktop_/} @ACCT_COLS),
    };
    $hub->pluggable->hook('nlw.export_account', [$self, $data, \%opts]);

    DumpFile($export_file, $data);
    return $export_file;
}

# Always use direct => 1 for account plugins.
around 'plugins_enabled' => sub {
    my ($orig, $self, @args) = @_;
    $orig->($self, direct => 1, @args);
};

sub user_can {
    my $self = shift;
    my %p = @_; # pass straight through to authz checker.

    my $authz = Socialtext::Authz->new;
    return $authz->user_has_permission_for_account(%p, account=>$self);
}

sub all_users_as_hash {
    my $self  = shift;
    my %args  = @_;
    my $iter  = $self->users(show_hidden => 1, order => 1);
    my @users = map { $self->_dump_user_to_hash($_,%args) } $iter->all();
    return \@users;
}

sub users_as_hash {
    my $self  = shift;
    my %args  = @_;
    my $iter  = $self->users(primary_only => 1);
    my @users = map { $self->_dump_user_to_hash($_,%args) } $iter->all();
    return \@users;
}

sub _dump_user_to_hash {
    my $self = shift;
    my $user = shift;
    my %args = @_;
    my $hash = $user->to_hash(%args);
    delete $hash->{user_id};
    delete $hash->{primary_account_id};
    $hash->{primary_account_name} = $user->primary_account->name;
    $hash->{profile} = $self->_dump_profile($user, %args);

    my $user_accounts = $user->accounts;
    for my $acct (@$user_accounts) {
        my $uar = $acct->role_for_user($user);
        $hash->{roles}{$acct->name} = $uar->name;
    }

    $hash->{restrictions} = [
        map { $_->to_hash } $user->restrictions->all
    ];

    return $hash;
}

sub _dump_profile {
    my $self = shift;
    my $user = shift;
    my %args = @_;

    eval "require Socialtext::People::Profile";
    return {} if $@;

    my $profile = Socialtext::People::Profile->GetProfile($user);
    return {} unless $profile;
    return $profile->to_hash(%args);
}

sub import_file {
    my $class = shift;
    my %opts = @_;
    my $import_file = $opts{file};
    my $import_name = $opts{name};
    my $hub = $opts{hub};

    my $hash = LoadFile($import_file);

    my $version = $hash->{version};
    if ($version && ($version > $EXPORT_VERSION)) {
        die loc(
            "error.import-account=max-version",
            $EXPORT_VERSION
        );
    }

    # Make sure we've got a name for this Account that's being imported
    my $export_name = $hash->{name};
    $import_name ||= $export_name;
    $hash->{import_name} = $import_name;

    # Fail if the Account already exists
    my $account = $class->new(name => $import_name);
    if ($account && !$account->is_placeholder()) {
        die loc("error.exists=account!", $import_name) . "\n";
    }

    my %acct_params = (
        is_system_created          => $hash->{is_system_created},
        skin_name                  => $hash->{skin_name},
        pref_blob                  => $hash->{pref_blob} || '',
        backup_skin_name           => 's3',
        email_addresses_are_hidden => $hash->{email_addresses_are_hidden} ? 1 : 0,
        allow_invitation           => (
            defined $hash->{allow_invitation}
            ? $hash->{allow_invitation}
            : 1
        ),
        (
            map { $hash->{$_} ? ($_ => $hash->{$_}) : () }
                grep {/^desktop_/} @ACCT_COLS
        ),
    );

    if ($account && $account->is_placeholder) {
        # "Placeholder" Accounts can be over-written at import; they were
        # created as placeholders during the import of another Account.
        #
        # We also need to make sure that we update the Account Type to
        # _something_, even if it wasn't explicit in the original export; by
        # default, Accounts are of the "Standard" type.
        $account->update(
            account_type => 'Standard',
            %acct_params,
        );
    }
    else {
        $account = $class->create(
            %acct_params,
            name => $import_name,
        );
    }

    if ($hash->{logo}) {
        print loc("account.importing-logo") . "\n";
        eval {
            my $image = MIME::Base64::decode($hash->{logo});
            $account->logo->set(\$image);
            delete $hash->{logo};
        };
        warn "Could not import account logo: $@" if $@;
    }
    
    print loc("user.importing"), "\n";
    my @profiles;
    for my $user_hash (@{ $hash->{users} }) {

        next unless Socialtext::User::Default::Users->CanImportUser($user_hash);

        # Import this user into the new account we're creating. If they were
        # in some other account we'll fix that up below.
        my $user_orig_acct = $user_hash->{primary_account_name} || $export_name;
        $user_hash->{primary_account_name} = $import_name;

        my $existing_user
            = Socialtext::User->new(username => $user_hash->{username});
        my $user = $existing_user
            || Socialtext::User->Create_user_from_hash($user_hash);

        # If the user's primary account before export was not the account
        # we're currently importing, then keep that relationship, even if we
        # need to create a blank/empty account with that name.
        my $pri_acct = $account;
        if ($user_orig_acct ne $export_name) {
            # User had a Primary Account that was *not* the Account that we're
            # re-importing (possibly under a new name).
            $pri_acct = Socialtext::Account->new(name => $user_orig_acct)
                     || Socialtext::Account->create(
                            name         => $user_orig_acct,
                            account_type => 'Placeholder',
                        );
        }

        $user->primary_account($pri_acct, no_hooks => 1);

        my $default_acct = Socialtext::Account->Default();
        if (!$existing_user and $pri_acct->account_id != $default_acct->account_id) {
            # When we create a user, she is assigned to the default account
            # so we should remove her from that account.
            $default_acct->remove_user(user => $user);
        }

        # Give the User the correct Role in this Account (which could be
        # either "give this User a new Role here that they didn't have before"
        # or could be "change their role to the one specified in the import".
        eval {
            my $role_name = $user_hash->{roles}{$export_name} || 'member';
            my $acct_role = Socialtext::Role->new(name => $role_name);
            if ($account->has_user($user, direct => 1)) {
                $account->assign_role_to_user(user => $user, role => $acct_role);
            }
            else {
                $account->add_user(user => $user, role => $acct_role);
            }
        };
        warn $@ if $@;

        # Hang onto the profile so we can create it later.
        if (my $profile = delete $user_hash->{profile}) {
            $profile->{user} = $user;
            push @profiles, $profile;
        }

        # Apply any restrictions that existed in the export back to the User
        foreach my $r (@{$user_hash->{restrictions}}) {
            Socialtext::User::Restrictions->CreateOrReplace( {
                user_id => $user->user_id,
                %{$r},
            } );
        }
    }

    $hub->pluggable->hook('nlw.import_account', [$account, $hash, \%opts]);
    die $hub->pluggable->hook_error if ($hub->pluggable->hook_error);

    $account->{_import_hash} = $hash;

    # Create all the profiles after so that user references resolve.
    eval "require Socialtext::People::Profile";
    unless ($@) {
        print loc("profile.importing") . "\n";
        Socialtext::People::Profile->create_from_hash( $_ ) for @profiles;
    }

    if ($hash->{plugins}) {
        print loc("account.enabling-plugins") . "\n";
        for my $plugin_name (@{ $hash->{plugins} }) {
            unless (Socialtext::Pluggable::Adapter->plugin_exists($plugin_name)) {
                print loc("account.skip-missing=plugin", $plugin_name) . "\n";
                next;
            }
            eval {
                $account->enable_plugin($plugin_name);

                my $prefs = $hash->{plugin_preferences}{$plugin_name};
                if ($prefs) {
                    my $class = Socialtext::Pluggable::Adapter->plugin_class(
                        $plugin_name);
                    my $table = $class->GetAccountPluginPrefTable($account->account_id);
                    $table->set( %{$hash->{plugin_preferences}{$plugin_name}} );
                }
            };
            warn $@ if $@;
        }
    }

    return $account;
}

sub finish_import {
    my $self = shift;
    my %opts = @_;
    my $hub  = $opts{hub};
    my $meta = $self->{_import_hash};

    my @auws;
    # Exports may use the deprecated all_users_workspace setting
    if ( my $ws_name = $meta->{all_users_workspace} ) {
        push @auws, $ws_name;
    }
    if (my $auw_names = $meta->{all_users_workspaces}) {
        push @auws, @$auw_names;
    }

    for my $ws_name (@auws) {
        my $ws = Socialtext::Workspace->new( name => $ws_name );
        $ws->assign_role_to_account(account => $self, role => 'member');
    }

    $hub->pluggable->hook('nlw.finish_import_account', [$self, $meta, \%opts]);
    die $hub->pluggable->hook_error if ($hub->pluggable->hook_error);
}

sub all_users_workspaces {
    my $self = shift;

    my $ws_cursor = $self->workspaces;
    my @auws;
    while (my $ws = $ws_cursor->next) {
        push @auws, $ws if $ws->role_for_account($self);
    }
    return \@auws;
}

sub has_all_users_workspaces {
    my $self = shift;

    my $auws = $self->all_users_workspaces;
    return @$auws > 0 ? 1 : 0;
}

after 'role_change_check' => sub {
    my $self = shift;
    my $actor = shift;
    my $action = shift;
    my $thing = shift;

    if ($action eq 'remove' and $thing->isa('Socialtext::User')) {
        if ($self->account_id == $thing->primary_account_id) {
            die "Cannot remove a user from their primary account!";
        }
    }
};

after 'role_change_event' => sub {
    my ($self,$actor,$change,$thing,$role) = @_;

    my $to_hook;

    if ($thing->isa('Socialtext::User')) {
        if ($change eq 'add') {
            $to_hook = 'nlw.add_user_account_role';
        }
        elsif ($change eq 'remove') {
            $to_hook = 'nlw.remove_user_account_role';
        }
    }
    elsif ($thing->isa('Socialtext::Group')) {
        if ($change eq 'add') {
            $to_hook = 'nlw.add_group_account_role';
        }
        elsif ($change eq 'remove') {
            $to_hook = 'nlw.remove_group_account_role';
        }
    }

    if ($to_hook) {
        my $adapter = Socialtext::Pluggable::Adapter->new();
        $adapter->make_hub( Socialtext::User->SystemUser() );
        $adapter->hook($to_hook, [$self, $thing, $role]);
    }
};

sub Unknown    { $_[0]->new( name => 'Unknown' ) }
sub Socialtext { $_[0]->new( name => 'Socialtext' ) }
sub Deleted    { $_[0]->new( name => 'Deleted' ) }

{
    my $CachedDefault;
    sub Default {
        my $class = shift;
        $CachedDefault ||= get_system_setting('default-account');
        return $CachedDefault;
    }
    sub Clear_Default_Account_Cache {
        undef $CachedDefault;
    }
}

sub new {
    my ( $class, %p ) = @_;

    return defined $p{name}       ? $class->_new_from_name(%p)
         : defined $p{account_id} ? $class->_new_from_account_id(%p)
         : undef;
}

sub _new_from_name {
    my ( $class, %p ) = @_;

    if (my $acct = $class->cache->get("name:$p{name}")) {
        return $acct;
    }
    return $class->_new_from_where('name=?', $p{name});
}

sub _new_from_account_id {
    my ( $class, %p ) = @_;
    return unless defined $p{account_id};

    if (my $acct = $class->cache->get("id:$p{account_id}")) {
        return $acct;
    }
    return $class->_new_from_where('account_id=?', $p{account_id});
}

sub _new_from_where {
    my ( $class, $where_clause, @bindings ) = @_;

    my $sth = sql_execute(
        'SELECT *'
        . ' FROM "Account"'
        . " WHERE $where_clause",
        @bindings );
    my $row = $sth->fetchrow_hashref;
    return unless $row;

    my $acct = $class->new_from_hash_ref($row);
    $class->cache->set("name:" . $acct->name     => $acct);
    $class->cache->set("id:" . $acct->account_id => $acct);
    return $acct;
}

sub new_from_hash_ref {
    my ( $class, $row ) = @_;
    return $row unless $row;
    return bless $row, $class;
}

# NOTE: Use and account_factory to create an account so that
# the proper hooks get called. To re-iterate: Do NOT call this
# directly.
sub create {
    my ( $class, %p ) = @_;
    my $timer = Socialtext::Timer->new;

    my $no_plugin_hooks = delete $p{no_plugin_hooks};

    $class->_validate_and_clean_data(\%p);
    $class->_create_full(%p);
    my $self = $class->new(%p);
    $self->_enable_default_plugins;
    $self->_account_create_hook unless $no_plugin_hooks;

    my $msg = 'CREATE,ACCOUNT,account:' . $self->name
              . '(' . $self->account_id . '),'
              . 'type=' . $self->account_type . ','
              . '[' . $timer->elapsed . ']';
    st_log()->info($msg);
    return $self;
}

sub _account_create_hook {
    my $self = shift;

    # Don't die trying to access the systemuser before it exists
    return
        if $self->name eq 'Unknown'
        or $self->name eq 'Deleted'
        or $self->name eq 'Socialtext';

    # Call the nlw.create_account event on all pluggable plugins
    # Here is where the widgets plugin will set the central_workspace
    # preference
    my $adapter = Socialtext::Pluggable::Adapter->new;
    $adapter->make_hub(Socialtext::User->SystemUser());
}

sub _enable_default_plugins {
    my $self = shift;
    for (Socialtext::Pluggable::Adapter->plugins) {
        next unless $_->scope eq 'account';
        my $plugin = $_->name;
        $self->enable_plugin($plugin)
            if get_system_setting("$plugin-enabled-all");
    }

    if ($self->account_type eq 'Free 50') {
        $self->_enable_marketo_if_present;
    }
}

sub _create_full {
    my ( $class, %p ) = @_;

    my $id = sql_nextval('"Account___account_id"');
    $p{account_id} = $id;
    $p{user_set_id} = $id + ACCT_OFFSET;

    my $fields = join ',', keys %p;
    my $values = '?,' x keys %p;
    chop $values;

    sql_execute(qq{
        INSERT INTO "Account" ($fields) VALUES ($values)
    },map { $p{$_} } keys %p);
}

sub delete {
    my ($self) = @_;

    my $workspaces = $self->workspaces;
    while ( my $ws = $workspaces->next ) {
        $ws->delete();
    }

    sql_execute( 'DELETE FROM "Account" WHERE account_id=?',
        $self->account_id );
    Socialtext::Cache->clear('account');
}

sub update {
    my ( $self, %p ) = @_;

    $self->_validate_and_clean_data(\%p);
    my $prev_settings = { map { $_ => $self->{$_} } keys %p };

    my ( @updates, @bindings );
    while (my ($column, $value) = each %p) {
        push @updates, "$column=?";
        push @bindings, $value;
    }

    if (@updates) {
        my $set_clause = join ', ', @updates;
        my $sth;
        eval {
            $sth = sql_execute(
                'UPDATE "Account"'
                . " SET $set_clause WHERE account_id=?",
                @bindings, $self->account_id);
        };
        if ( my $e = $@ ) {
            die $sth->error if $sth;
            die $e;
        }

        while (my ($column, $value) = each %p) {
            $self->$column($value);
            $self->{$column} = $value;
        }
    }

    $self->_post_update( $prev_settings, \%p );

    return $self;
}

sub _post_update {
    my $self = shift;
    my $old  = shift;
    my $new  = shift;

    $old->{account_type} ||= '';
    $new->{account_type} ||= '';
    if (    $old->{account_type} eq 'Free 50'
        and $new->{account_type} ne 'Free 50') {
        $self->update( restrict_to_domain => '' );
        my $wksps = $self->workspaces;
        while (my $w = $wksps->next) {
            $w->update(invitation_filter => '');
            $w->enable_plugin('socialcalc');
        }
        $self->_disable_marketo_if_present;
    }
    elsif ($new->{account_type} eq 'Free 50') {
        my $wksps = $self->workspaces;
        while (my $w = $wksps->next) {
            $w->disable_plugin('socialcalc');
        }
        $self->_enable_marketo_if_present;
    }

    if ($old->{account_type} and $old->{account_type} ne $new->{account_type}) {
        my $msg = 'UPDATE,ACCOUNT,account:' . $self->name
                  . '(' . $self->account_id . '),'
                  . "old_type='" . $old->{account_type} . "',"
                  . "new_type='" . $new->{account_type} . "'";
        st_log()->info($msg);
    }

    Socialtext::Cache->clear('account');
}

sub Count {
    my ( $class, %p ) = @_;

    my @bind  = ();
    my $where = '';
    if ( $p{is_exportable} ) {
        $where = 'WHERE "Account".is_exportable = ?';
        push @bind, $p{is_exportable};
    }

    return sql_singlevalue("SELECT COUNT(*) FROM \"Account\" $where", @bind);
}

sub CountByName {
    my ( $class, %p ) = @_;
    die "name is mandatory!" unless $p{name};

    my $where = _where_by_name(\%p);
    my $sth = sql_execute(
        qq{SELECT COUNT(*) FROM "Account" $where},
        $p{name},
    );
    return $sth->fetchall_arrayref->[0][0];
}

{
    Readonly my $spec => {
        limit      => SCALAR_TYPE( default => undef ),
        offset     => SCALAR_TYPE( default => 0 ),
        order_by   => SCALAR_TYPE(
            regex   => qr/^(?:name|user_count|workspace_count)$/,
            default => 'name',
        ),
        sort_order => SCALAR_TYPE(
            regex   => qr/^(?:ASC|DESC)$/i,
            default => 'ASC',
        ),
        # For searching by account name
        name             => SCALAR_TYPE( default => undef ),
        # For searching by account type
        type             => SCALAR_TYPE( default => undef ),
        case_insensitive => SCALAR_TYPE( default => undef ),
    };
    sub All {
        my $class = shift;
        my %p = validate( @_, $spec );
        my $t = time_scope('acct_all');

        my $sth;
        if ( $p{order_by} eq 'name' ) {
            $sth = $class->_All( %p );
        }
        elsif ( $p{order_by} eq 'workspace_count' ) {
            $sth = $class->_AllByWorkspaceCount( %p );
        }
        elsif ( $p{order_by} eq 'user_count' ) {
            $sth = $class->_AllByUserCount( %p );
        }

        return Socialtext::MultiCursor->new(
            iterables => [ $sth->fetchall_arrayref({}) ],
            apply => sub {
                return Socialtext::Account->new_from_hash_ref($_[0]);
            }
        );
    }
}

sub _All {
    my ( $self, %p ) = @_;

    my $where = '';
    my @args = ($p{limit}, $p{offset});
    if ($p{name}) {
        $where = _where_by_name(\%p);
        unshift @args, $p{name};
    }
    elsif ($p{type}) {
        $where = q{ WHERE "Account".account_type = ? };
        unshift @args, $p{type};
    }

    my $order_by_field = $p{case_insensitive} ? 'LOWER(name)' : 'name';

    return sql_execute(
        'SELECT *'
        . ' FROM "Account"'
        . $where
        . " ORDER BY $order_by_field $p{sort_order}"
        . ' LIMIT ? OFFSET ?' ,
        @args );
}

# There's a _tiny_ chance that there could be more than one matching
# result here, forcibly return either 0 or 1.
sub Free50ForDomain {
    my $class        = shift;
    my $domain       = shift;

    my $sth = sql_execute(qq{
        SELECT *
          FROM "Account"
         WHERE restrict_to_domain = ?
           AND account_type = 'Free 50'
         ORDER BY account_id
         LIMIT 1
    }, $domain);

    my $row = $sth->fetchall_arrayref({});

    return @$row
        ? $class->new_from_hash_ref($row->[0])
        : undef;
}

sub _AllByWorkspaceCount {
    my ( $self, %p ) = @_;

    my $where = '';
    my @args = ($p{limit}, $p{offset});
    if ($p{name}) {
        $where = _where_by_name(\%p);
        unshift @args, $p{name};
    }

    my $sql = qq{
        SELECT "Account".*, 
               COALESCE(workspace_count,0) AS workspace_count
        FROM "Account"
        LEFT JOIN (
            SELECT account_id, 
                   COUNT(DISTINCT(workspace_id)) AS workspace_count
            FROM "Workspace"
            GROUP BY account_id
        ) wa USING (account_id)
        $where
        ORDER BY workspace_count $p{sort_order}, "Account".name ASC
        LIMIT ? OFFSET ?
    };
    return sql_execute($sql, @args);
}

sub _AllByUserCount {
    my ( $self, %p ) = @_;

    my $where = '';
    my @args = ($p{limit}, $p{offset});
    if ($p{name}) {
        $where = _where_by_name(\%p);
        unshift @args, $p{name};
    }

    my $sql = qq{
        SELECT "Account".*, COALESCE(user_count,0) AS user_count
          FROM "Account"
          LEFT OUTER JOIN (
            SELECT into_set_id, COUNT(DISTINCT(from_set_id)) AS user_count
              FROM user_set_path
             WHERE from_set_id } . PG_USER_FILTER . qq{
             GROUP BY into_set_id
          ) AS X ON (user_set_id = into_set_id)
          $where
         ORDER BY user_count $p{sort_order}, "Account".name ASC
         LIMIT ? OFFSET ?
    };
    return sql_execute($sql, @args);
}

sub ByName {
    my $class = shift;
    return Socialtext::Account->All( @_ );
}

sub _where_by_name {
    my $p = shift;
    return '' unless $p->{name};

    # Turn our substring into a SQL pattern.
    $p->{name} =~ s/^\s+//; $p->{name} =~ s/\s+$//;
    $p->{name} .= '%';
    if (!($p->{name} =~ s/^\\b//)) {
        $p->{name} = "\%$p->{name}";
    }

    my $comparator = $p->{case_insensitive} ? 'ILIKE' : 'LIKE';
    return qq{ WHERE "Account".name $comparator ?};
}


sub _validate_and_clean_data {
    my $self = shift;
    my $p = shift;

    my $is_create = ref $self ? 0 : 1;

    if (defined $p->{name}) {
        $p->{name} = Socialtext::String::scrub( $p->{name} );
    }

    my @errors;
    if ( ( exists $p->{name} or $is_create )
         and not
         ( defined $p->{name} and length $p->{name} ) ) {
        push @errors, loc('error.account-name-required');
    }

    if ($p->{all_users_workspace}) {
        push @errors, 'Updating the all-users workspace via $acct->update is deprecated';
    }

    if ( $p->{skin_name} ) {
        my $skin = Socialtext::Skin->new(name => $p->{skin_name});
        unless ($skin->exists) {
            if ($p->{backup_skin_name}) {
                $skin = Socialtext::Skin->new(name => $p->{backup_skin_name});
            }
            my $msg = loc(
                "error.no-skin=name", $p->{skin_name}
            );
            if ($skin->exists) {
                warn $msg . "\n";
                warn "Falling back to the $p->{backup_skin_name} skin.\n";
            }
            else {
                push @errors, $msg;
            }
        }
    }
    delete $p->{backup_skin_name};

    if ( defined $p->{name} && Socialtext::Account->new( name => $p->{name} ) ) {
        push @errors, loc('error.account-exists=name',$p->{name} );
    }

    if ( not $is_create and $self->is_system_created and $p->{name} ) {
        push @errors, loc('error.set-system-account-name');
    }

    if ( not $is_create and $p->{is_system_created} ) {
        push @errors, loc('error.set-system-account');
    }

    if ($p->{account_type} and !$VALID_TYPE{ $p->{account_type} }) {
        push @errors, 
            loc("error.invalid=account-type!", $p->{account_type});
    }

    if ($p->{restrict_to_domain}
        and !Socialtext::Helpers->valid_email_domain( $p->{restrict_to_domain} )
    ) {
        push @errors,
            loc("error.invalid=domain!", $p->{restrict_to_domain});
    }

    unless (defined $p->{allow_invitation}) {
        $p->{allow_invitation} = Socialtext::AppConfig->allow_network_invitation;
    }

    data_validation_error errors => \@errors if @errors;
}

sub hash_representation {
    my ($self,%p) = @_;
    my $hash = {
        account_name       => $self->name,
        account_id         => $self->account_id,
        plugins_enabled    => [ sort $self->plugins_enabled ],
        plugin_preferences => $self->plugin_preferences,
    };
    unless ($p{minimal} || $p{no_desktop}) {
        $hash->{$_} = $self->$_ for (grep /^desktop_/,@ACCT_COLS);
    }
    if ($p{user_count}) {
        $hash->{user_count} = $self->user_count;
    }
    return $hash;
}

sub is_using_account_logo_as_desktop_logo {
    my $self = shift;
    my $account_id = $self->account_id;
    if ($self->desktop_logo_uri =~ m{^/data/accounts/\Q$account_id\E/logo(\?|$)}) {
        return 1;
    }
    else {
        return 0;
    }
}

sub email_passes_domain_filter {
    my $self = shift;
    my $email = shift;

    my $domain = $self->restrict_to_domain;
    return 1 unless $domain;

    my $filter = qr/@\Q$domain\E$/i;
    if ($email =~ $filter) {
        return 1;
    }
    return 0;
}

sub _disable_marketo_if_present {
    shift->_change_marketo_if_present('disable_plugin');
}
sub _enable_marketo_if_present {
    shift->_change_marketo_if_present('enable_plugin');
}

sub _change_marketo_if_present {
    my $self = shift;
    my $method = shift;
    my $adapter = Socialtext::Pluggable::Adapter->new();
    if ($adapter->plugin_exists('marketo')) {
        $self->$method('marketo');
    }
}

{
    my $cache;
    sub cache {
        return $cache ||= Socialtext::Cache->cache('account');
    }
}

after role_change_check => sub {
    my ($self,$actor,$change,$thing,$role) = @_;
    if ($thing->isa(ref($self))) {
        die "Account user_sets cannot contain other accounts.";
    }
};

sub impersonation_ok {
    my ($self, $actor, $user) = @_;

    if (($self->name eq 'Unknown') or ($self->name eq 'Deleted')) {
        st_log->error("Failed attempt to impersonate ".$user->username.
             " by ".$actor->username.". ".
             "The user belongs to the ".$self->name." account, ".
             "which disallows impersonation");
        Socialtext::Exception::Auth->throw(
            "Cannot impersonate in system account ".$self->name
        );
    }

    return unless $self->has_user($user);
    my $authz = Socialtext::Authz->new;
    return $authz->user_has_permission_for_account(
        user       => $actor,
        account    => $self,
        permission => 'impersonate'
    );
}

has 'pref_table' => (is => 'ro', isa => 'Socialtext::PrefsTable',
    lazy_build => 1);

sub _build_pref_table {
    my $self = shift;

    return Socialtext::PrefsTable->new(
        table    => 'user_set_plugin_pref',
        identity => {
            plugin      => 'widgets',
            user_set_id => $self->user_set_id,
        },
    );
}

sub central_workspace {
    my $self = shift;

    my $prefs = $self->pref_table->get();
    return $prefs->{central_workspace}
        ? Socialtext::Workspace->new(name => $prefs->{central_workspace})
        : undef;
}

sub create_central_workspace {
    my $self = shift;
    my $template_ws = shift;

    my $wksp = $self->central_workspace;
    return $wksp if $wksp;

    my $user = Socialtext::User->SystemUser();

    # Enable the widgets plugin so we can set this preference
    $self->enable_plugin('widgets');

    # Find a valid name for a new workspace
    my ($title, $name, $main_page_name);
    for (my $i = 0; !$i or defined $wksp; $i++) {
        # XXX: Horrible for i18n:
        my $suffix = ' Central' . ($i ? " $i" : "");
        $main_page_name = $title = $self->name . $suffix;
        $name = Socialtext::String::title_to_id($title);

        $name =~ s/^st_//;
        if ( Socialtext::Workspace->NameIsIllegal($name) ) {
            # This can only be because the name is too long

            # Truncate the account name, saving room for $suffix
            $name = substr($self->name, 0, 30 - length($suffix));
            $name = Socialtext::String::title_to_id($name . $suffix);

            $main_page_name = substr($self->name, 0, 30 - length($suffix))
                            . $suffix;
        }

        $name =~ s/_/-/g;
        $wksp = Socialtext::Workspace->new(name => $name)
    }

    $wksp = Socialtext::Workspace->create(
        name                => $name,
        title               => $title,
        account_id          => $self->account_id,
        created_by_user_id  => $user->user_id(),
        allows_page_locking => 1,
        skip_default_pages  => $template_ws ? 1 : 0,
    );

    $wksp->assign_role_to_account(account => $self);

    if ($template_ws) {
        $wksp->clone_workspace_pages($template_ws->name);
    }
    else {
        my $share_dir = Socialtext::AppConfig->new->code_base();
        $wksp->load_pages_from_disk(
            clobber => 1,
            dir => "$share_dir/workspaces/central",
            replace => {
                # Replace all pages with YourCo in the title with this account's
                # name
                'YourCo Central' => $main_page_name
            },
        );
    }

    $self->pref_table->set(central_workspace => $wksp->name);
    return $wksp;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

__END__

=head1 NAME

Socialtext::Account - A Socialtext account object

=head1 SYNOPSIS

  use Socialtext::Account;

  my $account = Socialtext::Account->new( account_id => $account_id );

  my $account = Socialtext::Account->new( name => $name );

=head1 DESCRIPTION

This class provides methods for dealing with data from the Account
table. Each object represents a single row from the table.

=head1 METHODS

=over 4

=item Socialtext::Account->new(PARAMS)

Looks for an existing account matching PARAMS and returns a
C<Socialtext::Account> object representing that account if it exists.

PARAMS can be I<one> of:

=over 8

=item * account_id => $account_id

=item * name => $name

=back

=item Socialtext::Account->create(PARAMS)

Attempts to create a account with the given information and returns a
new C<Socialtext::Account> object representing the new account.

PARAMS can include:

=over 8

=item * name - required

=item * is_system_created

=back

=item Socialtext::Account->Resolve( $id_or_name )

Looks up the account either by the account id or the name.

=item $account->update(PARAMS)

Updates the object's information with the new key/val pairs passed in.
This method accepts the same PARAMS as C<new()>, but you cannot change
"is_system_created" after the initial creation of a row.

=item Socialtext::Account->new_from_hash_ref( $hashref )

Given a hash ref of attributes, create a new account object. This
alone will not cause the data to persist, however.

=item $account->delete()

Deletes the account from the DBMS, but this is probably a bad idea if
it has any workspaces.

=item $account->account_id()

=item $account->name()

=item $account->skin_name()

=item $account->custom_workspace_skins(PARAMS)

PARAMS can include:

=over 8

=item * include_workspaces - can be 1 or 0

=back

Return an array ref containing the names of all the workspace-level
custom skins that are used in this account.

If include_workspaces is set to 1, this method will return a hashref
with workspace-level skin names as keys and an arrayref of the
workspaces that use that skin.

=item $account->is_system_created()

Returns the given attribute for the account.

=item $account->all_users_as_hash(%args)

Returns a list of all the Users that have a Role in this Account as a hash,
suitable for serializing.

Accepts a hash of C<%args> that get passed through to help control the amount
of User data contained in the hashes returned.  Refer to
C<Socialtext::User->to_hash()> for more information on acceptable C<%args>.

=item $account->users_as_hash(%args)

Returns a list of all the users for whom this is their primary account
as a hash, suitable for serializing.

Accepts a hash of C<%args> that get passed through to help control the amount
of User data contained in the hashes returned.  Refer to
C<Socialtext::User->to_hash()> for more information on acceptable C<%args>.

=item $account->workspace_count()

Returns a count of workspaces for this account.

=item $account->to_hash()

Returns a hashref containing all the fields of this account.  Useful
for serialization.

=item $account->reset_skin($skin)

Change the skin for the account and its workspaces.

=item $account->workspaces()

Returns a cursor of the workspaces for this account, ordered by
workspace name.

=item $account->add_group(group=>$group, role=>$role)

Adds the given C<$group> to the Account with the specified C<$role>.  If no
C<$role> is provided, a default Role will be used instead.

=item $account->remove_group(group => $group, role=>$role)

Removes the given C<$role> that the given C<$group> may have in the Account.
If no C<$role> is provided, a default Role will be used instead.  If the Group
has no Role in the Account, this method does nothing.

=item $account->has_group($group)

Checks to see if the given C<$group> has a Role in the Account, returning true
if it does, false otherwise.

=item $account->role_for_group($group)

Returns the C<Socialtext::Role> object representing the Role that the given
C<$group> has in this Account.

=item $account->groups()

Returns a cursor of C<Socialtext::Group> objects for Groups that have a Role
in the Account, ordered by Group name.

=item $account->group_count()

Returns the count of Groups that have a Role in the Account.

=item $account->add_user(user=>$user, role=>$role)

Adds the given C<$user> to the Account with the specified C<$role>.  If no
C<$role> is provided, a default Role will be used instead.

=item $account->remove_user(user=>$user, role=>$role)

Removes the specified C<$role> Role that the the C<$user> has in this Account.
If the User has no Role in the Account, this method does nothing.

=item $account->role_for_user($user)

Returns the C<Socialtext::Role> object representing the Role that the given
C<$user> has in the Account (either directly, or which was inferred via Group
or Workspace membership).  If the User has B<no> Role in the Account, this
method returns false.

=item $account->users(PARAMS)

Returns a cursor of the Users in this Account, ordered by Username.

Accepts thes same PARAMS as C<Socialtext::User-E<gt>ByAccountId()>; please
refer to L<Socialtext::User> for more information on acceptable parameters.

=item $account->user_ids(PARAMS)

Returns a list-ref of User Ids, for Users that have access to this Account.

Accepts thes same PARAMS as C<Socialtext::User-E<gt>ByAccountId()>; please
refer to L<Socialtext::User> for more information on acceptable parameters.

=item $account->user_count(PARAMS)

Returns the count of Users in this Account.

Accepts thes same PARAMS as C<Socialtext::User-E<gt>ByAccountId()>; please
refer to L<Socialtext::User> for more information on acceptable parameters.

=item $account->has_user($user)

Returns true if the C<$user> has access to this C<$account> (which would be
either from this being his Primary Account, or from it being a Secondary
Account that the User has access to).

Returns false if the C<$user> has no access to the C<$account>.

=item $account->is_plugin_enabled($plugin)

Returns true if the specified plugin is enabled for this account.  

Note that the plugin still may be disabled for particular users; use C<Socialtext::User>'s can_use_plugin method to check for this.

=item $account->enable_plugin($plugin)

Enables the plugin for the specified account.

=item $account->plugins_enabled

Returns an array ref for the plugins enabled.

=item $account->disable_plugin($plugin)

Disables the plugin for the specified account.

=item $account->logo()

Return the logo for an account.

=item $account->export(dir => $dir)

Export the account data to a file in the specified directory.

=item $account->import_file(file => $file, [ name => $name ])

=item $account->finish_import();

Imports an account from data in the specified file.  If a name
is supplied, that name will be used instead of the original account name.

finish_import is also called after all the workspace data has been imported
to allow plugins to finish the import of their data.

=item $account->hash_representation()

Returns a hash representation of the account.

=item $account->is_using_account_logo_as_desktop_logo()

Checks whether or not the desktop logo is an uploaded custom account logo.

=item $account->has_all_users_workspaces()

Checks whether or not the account has any all users workspaces.

=item Socialtext::Account->Unknown()

=item Socialtext::Account->Socialtext()

=item Socialtext::Account->Default()

=item Socialtext::Account->Deleted()

Returns an account object for specified account.

=item Socialtext::Account->All()

Returns a cursor for all the accounts in the system. It accepts the
following parameters:

=over 8

=item * limit and offset

These parameters can be used to add a C<LIMIT> clause to the query.

=item * order_by - defaults to "name"

This must be one "name", "user_count", or "workspace_count".

=item * sort_order - "ASC" or "DESC"

This defaults to "ASC".

=back

=item Socialtext::Account->Count()

Returns a count of all accounts.

=item Socialtext::Account->EnsureRequiredDataIsPresent()

Inserts required accounts into the DBMS if they are not present. See
L<Socialtext::Data> for more details on required data.

=item Socialtext::Account->PluginsEnabledForAll()

Returns the list of plugin(s) enabled for all accounts.

=item Socialtext::Account->EnablePluginForAll($plugin)

Enables a plugin for all accounts

=item Socialtext::Account->DisablePluginForAll($plugin)

Disables a plugin for all accounts

=item Socialtext::Account::ByName()

Search accounts by name.  Returns a cursor for the matching counts.

=item Socialtext::Account::CountByName()

Returs a count of accounts matched by name.

=back

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005-2006 Socialtext, Inc., All Rights Reserved.

=cut
