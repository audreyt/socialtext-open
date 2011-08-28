# @COPYRIGHT@
package Socialtext::CLI;

use strict;
use warnings;

our $VERSION = '0.01';

use Encode;
use File::Basename ();
use File::Spec;
use File::Temp;
use File::Path qw/rmtree/;
use File::Slurp qw(slurp);
use List::MoreUtils qw(uniq any);
use Getopt::Long qw( :config pass_through );
use Socialtext::AppConfig;
use Pod::Usage;
use Readonly;
use Scalar::Util qw/blessed/;
use Try::Tiny;

use Socialtext::Search::AbstractFactory;
use Socialtext::Validate qw( validate SCALAR_TYPE ARRAYREF_TYPE );
use Socialtext::l10n qw(:all);
use Socialtext::Locales qw( valid_code );
use Socialtext::Log qw( st_log st_timed_log );
use Socialtext::Workspace;
use Socialtext::User;
use Socialtext::User::Cache;
use Socialtext::Timer;
use Socialtext::SystemSettings qw/get_system_setting set_system_setting/;
use Socialtext::Pluggable::Adapter;
use Socialtext::DaemonUtil;
use Socialtext::Group;
use Fatal qw/mkdir rmtree/;

my %CommandAliases = (
    '--help' => 'help',
    '-h'     => 'help',
    '-?'     => 'help',
);

{
    Readonly my $spec => { argv => ARRAYREF_TYPE( default => [] ) };

    sub new {
        Socialtext::Timer->Reset();
        my $class = shift;
        my %p     = validate( @_, $spec );

        local @ARGV = @{ $p{argv} };

        my %opts;
        GetOptions(
            'ceqlotron' => \$opts{ceqlotron},
            )
            or exit 1;

        my $self = {
            argv      => [@ARGV],
            command   => '',
            ceqlotron => $opts{ceqlotron},
        };

        return bless $self, $class;
    }
}

sub run {
    my $self = shift;

    my $command = shift @{ $self->{argv} };

    my $script_name = File::Basename::basename($0);

    $self->_error(
        "You must provide a command as the first argument to this script.\n"
            . "Please run '$script_name help' for more details." )
        unless defined $command
        and length $command;

    $command = $CommandAliases{$command}
        if $CommandAliases{$command};
    $self->{command} = $command;
    $command =~ s/-/_/g;

    unless ( $self->can($command) ) {
        $self->_error(
                  "The command you specified, $command, was not valid.\n"
                . "Please run '$script_name help' for more details." );
    }

    if ( $command ne 'help' ) {
        Socialtext::DaemonUtil::Check_and_drop_privs();
    }

    Socialtext::Timer->Continue("CLI_$command");
    $self->$command();
    Socialtext::Timer->Pause("CLI_$command");
}

sub help {
    $_[0]->_print_help( exitval => 0, verbose => 1 );
}

sub _help_as_error {
    $_[0]->_print_help( message => $_[1], exitval => 2 );
}

{
    Readonly my $spec => {
        message => SCALAR_TYPE( default => undef ),
        exitval => SCALAR_TYPE( default => 0 ),
        verbose => SCALAR_TYPE( default => 0 ),
    };

    sub _print_help {
        my $self = shift;
        my %p    = validate( @_, $spec );

        if ( $p{message} ) {
            $p{message} = _clean_msg( $p{message} );
        }

        pod2usage(
            {
                -message => $p{message},
                -input   => $INC{'Socialtext/CLI.pm'},
                -section => 'NAME|SYNOPSIS|COMMANDS',
                -verbose => ( $p{verbose} ? 2 : 0 ),
                -exitval => $p{exitval},
            }
        );
    }
}

sub give_system_admin {
    my $self = shift;
    my $user = $self->_require_user();

    $user->set_technical_admin(1);

    my $username = $user->username();
    $self->_success("$username now has system admin access.");
}

sub give_accounts_admin {
    my $self = shift;
    my $user = $self->_require_user();

    $user->set_business_admin(1);

    my $username = $user->username();
    $self->_success("$username now has accounts admin access.");
}

sub remove_system_admin {
    my $self = shift;
    my $user = $self->_require_user();

    $user->set_technical_admin(0);

    my $username = $user->username();
    $self->_success("$username no longer has system admin access.");
}

sub remove_accounts_admin {
    my $self = shift;
    my $user = $self->_require_user();

    $user->set_business_admin(0);

    my $username = $user->username();
    $self->_success("$username no longer has accounts admin access.");
}

sub set_default_account {
    my $self = shift;
    my $account = $self->_require_account;
    set_system_setting('default-account', $account->account_id);
    $self->_success(loc("account.new-default=name", $account->name));
}

sub _enabled_plugins {
    my ($self, %opts) = @_;
    if ($opts{'all-accounts'}) {
        return Socialtext::Account->PluginsEnabledForAll;
    }
    if ($opts{'all-workspaces'}) {
        return Socialtext::Workspace->PluginsEnabledForAll;
    }
    elsif ($opts{workspace}) {
        my $workspace = Socialtext::Workspace->new( name => $opts{workspace} );
        return $workspace->plugins_enabled
    }
    elsif ($opts{account}) {
        my $account = $self->_load_account($opts{account});
        return $account->plugins_enabled;
    }
}

sub _plugin_before {
    my ($self, %opts) = @_;
    $self->{_plugin_before}
        = { map { $_ => 1 } $self->_enabled_plugins(%opts) };
}

sub _plugin_after {
    my ($self, %opts) = @_;
    my $before = $self->{_plugin_before};
    my %after = map { $_ => 1 } $self->_enabled_plugins(%opts);
    
    my $what = $opts{'all-accounts'} ? 'all accounts'
        : $opts{'all-workspaces'} ? 'all workspaces'
        : $opts{workspace} ? "workspace $opts{workspace}"
        : $opts{account} ? "account $opts{account}"
        : '';

    my @lines;
    push @lines, map { loc("plugin.enabled=plugin,container", $_, $what) }
                 grep { !$before->{$_} } keys %after;
    push @lines, map { loc("plugin.disabled=plugin,container", $_, $what) }
                 grep { !$after{$_} } keys %$before;

    if (@lines) {
        return $self->_success(join "\n", @lines);
    }
    else {
        return $self->_success(loc("cli.no-changes"));
    }
}

sub enable_plugin {
    my $self = shift;
    my $plugins  = $self->_require_plugin;
    my %opts = $self->_get_options('account:s', 'all-accounts', 'workspace:s', 'all-workspaces');

    if (!ref($plugins) && $plugins eq 'all') {
        $plugins = $self->_in_scope_plugins(%opts);
    }

    if ($opts{'all-accounts'}) {
        $self->_plugin_before(%opts);
        eval { Socialtext::Account->EnablePluginForAll($_) for @$plugins; };
        $self->_error($@) if $@;
        return $self->_plugin_after(%opts);
    }
    elsif ($opts{'all-workspaces'}) {
        $self->_plugin_before(%opts);
        eval { Socialtext::Workspace->EnablePluginForAll($_) for @$plugins; };
        $self->_error($@) if $@;
        return $self->_plugin_after(%opts);
    }
    elsif ($opts{account}) {
        my $account = $self->_load_account($opts{account});
        $self->_error(
           loc("error.no-account=name", $opts{account}) )
           unless $account;
        $self->_plugin_before(%opts);
        eval { $account->enable_plugin($_) for @$plugins; };
        return $self->_error($@) if $@;
        return $self->_plugin_after(%opts);
    }
    elsif ($opts{workspace}) {
        my $workspace = $self->_load_workspace( $opts{workspace} );
        $self->_plugin_before(%opts);
        eval { $workspace->enable_plugin($_) for @$plugins; };
        $self->_error($@) if $@;
        return $self->_plugin_after(%opts);
    }
    else {
        $self->_error(
            loc("error.account-or-wiki-required=command", $self->{command}),
        );
    }
}

sub disable_plugin {
    my $self = shift;
    my $plugins  = $self->_require_plugin;
    my %opts = $self->_get_options('account:s', 'all-accounts', 'workspace:s', 'all-workspaces');

    if (!ref($plugins) && $plugins eq 'all') {
        $plugins = $self->_in_scope_plugins(%opts);
    }

    if ($opts{'all-accounts'}) {
        $self->_plugin_before(%opts);
        eval { Socialtext::Account->DisablePluginForAll($_) for @$plugins; };
        $self->_error($@) if $@;
        return $self->_plugin_after(%opts);
    }
    if ($opts{'all-workspaces'}) {
        $self->_plugin_before(%opts);
        eval { Socialtext::Workspace->DisablePluginForAll($_) for @$plugins; };
        $self->_error($@) if $@;
        return $self->_plugin_after(%opts);
    }
    elsif ($opts{account}) {
        my $account = $self->_load_account($opts{account});
        $self->_plugin_before(%opts);
        eval { $account->disable_plugin($_) for @$plugins; };
        $self->_error($@) if $@;
        return $self->_plugin_after(%opts);
    }
    elsif ($opts{workspace}) {
        my $workspace = Socialtext::Workspace->new( name => $opts{workspace} );
        $self->_plugin_before(%opts);
        eval { $workspace->disable_plugin($_) for @$plugins; };
        $self->_error($@) if $@;
        return $self->_plugin_after(%opts);
    }
    else {
        $self->_error(
            loc("error.account-or-wiki-required=command", $self->{command}),
        );
    }
}

sub _in_scope_plugins {
    my $self = shift;
    my %opts = @_;

    my @all = Socialtext::Pluggable::Adapter->plugins();
    return [map { $_->name } @all] unless %opts;

    # Assume that %opts will always contain 'workspace' or 'account' like
    # indeces, if it exists.
    my $scope = (any { $_ =~ /account/ } keys %opts)
        ? 'account' : 'workspace';
        
    return [
        map { $_->name }
        grep { $_->scope eq $scope }
        @all
    ];
}

sub _require_plugin {
    my $self = shift;
    my %opts = $self->_get_options('plugin:s@');
    my $plugin = shift || $opts{plugin};

    $self->_error(loc("error.plugin-required"))
        unless $plugin and scalar(@$plugin);

    my $adapter = Socialtext::Pluggable::Adapter->new;

    return 'all' if $plugin->[0] eq 'all';

    for my $p (@$plugin) {
        $self->_error(loc("error.no-plugin=name!", $p))
            unless $adapter->plugin_exists($p);
    }

    return $plugin;
}

sub list_plugins {
    my $self = shift;
    my $adapter = Socialtext::Pluggable::Adapter->new;
    print "$_\n" for $adapter->plugin_list;
}

sub _pluginPrefTable {
    my ($self, $plugin_class, $account) = @_;
    if ($account) {
        return $plugin_class->GetAccountPluginPrefTable($account->account_id);
    }
    else {
        return Socialtext::PrefsTable->new(
            table    => 'plugin_pref',
            identity => {
                plugin  => $plugin_class->name,
            }
        );
    }
}

sub set_plugin_pref {
    my $self = shift;
    my $account  = $self->_require_account(1);
    my $plugins  = $self->_require_plugin;
    $plugins = $plugins eq 'all' ? $self->_in_scope_plugins : $plugins;

    for my $p (@$plugins) {
        my $plugin_class = Socialtext::Pluggable::Adapter->plugin_class($p);
        return unless $plugin_class;

        my $table = $self->_pluginPrefTable($plugin_class, $account);
        if ($account) {
            $plugin_class->CheckAccountPluginPrefs({ @{$self->{argv}} });
        }
        $table->set(@{$self->{argv}});
    }

    my $to_string = join(', ', sort @$plugins);
    $self->_success(
        loc('pref.updated=plugins', $to_string)
    );
}

sub clear_plugin_prefs {
    my $self = shift;
    my $account  = $self->_require_account(1);
    my $plugins  = $self->_require_plugin;
    $plugins = $plugins eq 'all' ? $self->_in_scope_plugins : $plugins;
    
    for my $p (@$plugins) {
        my $plugin_class = Socialtext::Pluggable::Adapter->plugin_class($p);
        my $table = $self->_pluginPrefTable($plugin_class, $account);
        $table->clear();
    }

    my $to_string = join(', ', @$plugins);
    $self->_success(
        loc('pref.cleared=plugins', $to_string)
    );
}

sub show_plugin_prefs {
    my $self = shift;
    my $plugin  = $self->_require_plugin;
    my $account  = $self->_require_account(1);

    # only accept a single `--plugin` param
    $self->_error(loc('error.show-pref-for-multiple-plugins'))
         if (!ref($plugin) or scalar(@$plugin) > 1);

    $plugin = $plugin->[0];
    my $plugin_class = Socialtext::Pluggable::Adapter->plugin_class($plugin);
    my $table = $self->_pluginPrefTable($plugin_class, $account);
    my $prefs = $table->get();
    my $msg = $account
        ? loc("pref.for=plugin,account", $plugin, $account->name)
        : loc("pref.for=plugin:", $plugin);
    $msg .= "\n";
    if (%$prefs) {
        for my $key (sort keys %$prefs) {
            $msg .= "  $key => $prefs->{$key}\n";
        }
    }
    else {
        $msg .= loc("error.no-preference=plugin", $plugin);
    }
    $msg .= "\n";
    $self->_success($msg);
}

sub _require_account {
    my $self     = shift;
    my $optional = shift;
    my %opts     = $self->_get_options('account:s', 'all-accounts');
    
    return if $opts{'all-accounts'};
    return if $optional and !$opts{account};

    $self->_error(
        loc("error.account-required=command", $self->{command}),
    ) unless $opts{account};

    return $self->{account} = $self->_load_account($opts{account});
}


sub get_default_account {
    my $self = shift;

    my $account = get_system_setting('default-account');
    $self->_success(loc("account.default=name", $account->name));
}

sub export_account {
    my $self = shift;
    my $account = $self->_require_account;
    my %opts     = $self->_get_options('force', 'dir:s');

    my ( $hub, $main ) = $self->_make_hub(
        Socialtext::NoWorkspace->new(),
        Socialtext::User->SystemUser(),
    );

    (my $short_name = lc($account->name)) =~ s#\W#_#g;
    my $dir = $opts{dir} || $self->_export_dir_base
        . "/$short_name.id-"
        . $account->account_id
        . ".export";

    if (-d $dir) {
        if ($opts{force}) {
            print loc("account.deleting-old-export=path", $dir) . "\n";
            rmtree $dir;
        }
        else {
            die loc("error.export-directory-exists=path!", $dir) . "\n";
        }
    }
    mkdir $dir;

    print loc("account.exporting=name", $account->name) . "\n";
    $account->export( dir => $dir, hub => $hub );

    my $workspaces = $account->workspaces;
    while (my $wksp = $workspaces->next) {
        print loc("wiki.exporting=name", $wksp->name) . "\n";
        eval { $wksp->export_to_tarball( dir => $dir ); };
        $self->_error($@) if $@;
    }

    $self->_success(
        "\n" . loc("cli.exported=account,path", $account->name, $dir));
}

sub import_account {
    my $self = shift;
    my %opts = $self->_get_options("directory:s", "name:s", "noindex");
    my $dir = $opts{directory} || '';
    $dir =~ s#/$##;

    $self->_error(loc("error.import-directory-required") . "\n") unless $dir;
    $self->_error(loc("error.no-directory=path", $dir) . "\n") unless -d $dir;

    Socialtext::Events->BlackList(
        { action => 'add_user', event_class => 'group'},
        { action => 'add_to_workspace', event_class => 'group'},
    );

    my ( $hub, $main ) = $self->_make_hub(
        Socialtext::NoWorkspace->new(),
        Socialtext::User->SystemUser(),
    );

    print loc("cli.clearing-caches"),"\n";
    eval {
        require Socialtext::People::ProfilePhoto;
        Socialtext::People::ProfilePhoto->ClearCache();
    };
    eval {
        require Socialtext::Group::Photo;
        Socialtext::Group::Photo->ClearCache();
    };

    print loc("account.importing-data"), "\n";
    my $account = eval { Socialtext::Account->import_file(
        file  => "$dir/account.yaml",
        name  => $opts{name},
        hub   => $hub,
        dir   => $dir,
    ) };
    $self->_alert_error($@) if ($@);

    for my $tarball (glob "$dir/*.1.tar.gz") {
        print loc("wiki.importing=tarball", $tarball), "\n";
        eval {
            my $wksp = Socialtext::Workspace->ImportFromTarball(
                tarball   => $tarball,
                noindex   => $opts{noindex},
            );
            $wksp->update( account_id => $account->account_id );
        };
        warn $@ if $@;
    }

    eval {
        $account->finish_import(
            hub => $hub,
            dir => $dir,
        );
    };
    $self->_alert_error($@) if $@;

    $self->_success(
        "\n" . loc("account.imported=name", $account->name));
}

sub _alert_error {
    my $self = shift;
    my $message = shift;

    my $snowflakes = '*' x 78;
    my $storm = "$snowflakes\n" x 3;
    $self->_error("\n$storm\n$message\n$storm\n");
}

sub list_accounts {
    my $self  = shift;
    my %opts  = $self->_get_options('ids');
    my $field = ($opts{ids} ? 'account_id' : 'name');

    require Socialtext::Account;
    my $all = Socialtext::Account->All();
    while (my $account = $all->next) {
        print $account->$field, "\n";
    }

    $self->_success();
}

sub list_workspaces {
    my $self         = shift;
    my $column       = $self->_determine_workspace_output(shift);
    my $ws_info_rows = Socialtext::Workspace->AllWorkspaceIdsAndNames();

    for my $ws_info_row (@$ws_info_rows) {
        my ( $ws_id, $ws_name ) = @$ws_info_row;
        if ( $column eq 'workspace_id' ) {
            print $ws_id;
        }
        else {
            print $ws_name;
        }
        print "\n";
    }

    $self->_success();
}

sub _determine_workspace_output {
    my $self = shift;

    my %opts = $self->_get_options('ids');

    return $opts{ids}
        ? 'workspace_id'
        : 'name';
}

sub set_user_names {
    my $self = shift;
    my $user = $self->_require_user;
    my %opts = $self->_require_set_user_names_params(shift);

    $self->_error(
        loc("error.update-remote-user")
    ) unless $user->can_update_store();

    my $result = $user->update_store(%opts);
    if ($result == 0) {
        $self->_error('Names provided match the current names for the user; no change to "' . $user->username() . '".');
    }

    $self->_success( loc('cli.updated-user=name', $user->username) );
}

sub set_user_account {
    my $self = shift;
    my $user = $self->_require_user;
    my $account = $self->_require_account;
    my %opts = $self->_get_options('no-hooks');

    $user->primary_account($account->account_id, no_hooks => $opts{'no-hooks'});

    $self->_success( loc('cli.updated-user=name', $user->username) );
}

sub get_user_account {
    my $self = shift;
    my $user = $self->_require_user;

    my $account = $user->primary_account;
    $self->_success(
        loc('cli.show-primary-account=user,account', $user->username, $account->name)
    );
}

sub set_external_id {
    my $self   = shift;
    my $user   = $self->_require_user;
    my %p      = $self->_get_options('external-id|X:s');
    my $extern = $p{'external-id'};

    if (not defined $extern) {
        $self->_error(
            "The command you called ($self->{command}) requires an external ID to be specified with the --external-id option.\n");
    }

    eval { $user->update_store(private_external_id => $extern) };
    if (my $e = $@) {
        my $err = (ref($e) && ($e->can('full_message')))
            ? $e->full_message
            : "$e";
        $self->_error($err);
    }

    $self->_success(
        loc("cli.set=user,external-id", $user->username, $extern)
    );
}

sub set_user_profile {
    my $self = shift;
    my $user = $self->_require_user;
    my ($key, $val) = @{ $self->{argv} };

    my $profile = $self->_get_profile($user);

    unless ($profile->valid_attr($key)) {
        # non-existent field
        $self->_error(
            loc("error.no-profile-field=name", $key)
        );
    }

    my $field = $profile->fields->by_name($key);
    if ($field->is_hidden) {
        # field hidden
        $self->_error(
            loc("error.update-hidden=field",$key)
        );
    }

    unless ($field->is_user_editable) {
        # externally sourced, cannot be set
        $self->_error(
            loc("error.update-external=field", $key)
        );
    }

    $profile->set_attr($key, $val);
    $profile->save();
    $self->_success(
        loc("profile.set=field,value,user",
            $key, $val, $user->username,
        )
    );
}

sub show_profile {
    my $self = shift;
    my $user = $self->_require_user;

    my $profile = $self->_get_profile($user);
    $profile->is_hidden(0);
    $profile->save;
    $self->_success(
        loc('profile.visible=user', 
            $user->username)
    );
}

sub hide_profile {
    my $self = shift;
    my $user = $self->_require_user;

    my $profile = $self->_get_profile($user);
    $profile->is_hidden(1);
    $profile->save;
    $self->_success(
        loc('profile.hidden=user', $user->username)
    );
}

sub _get_profile {
    my $self = shift;
    my $user = shift;

    unless ($user->can_use_plugin( 'people' )) {
        $self->_error(loc("error.missing-people-plugin"));
    }

    my $adapter = Socialtext::Pluggable::Adapter->new;
    unless ($adapter->plugin_exists('people')) {
        $self->_error(loc("error.no-people-plugin"));
    }

    require Socialtext::People::Profile;
    return Socialtext::People::Profile->GetProfile(
        $user->user_id,
        allow_hidden => 1,
    );
}

sub _require_set_user_names_params {
    my $self = shift;

    my %opts = $self->_get_options(
        'first-name:s',
        'middle-name:s',
        'last-name:s'
    );

    my @utf8_fields = ('first-name', 'middle-name', 'last-name');
    for my $key ( grep { defined $opts{$_} } @utf8_fields ) {
        my $val = $opts{$key};

        unless ( Encode::is_utf8($val) or $val =~ /^[\x00-\xff]*$/ ) {
            $self->_error( "The value you provided for the $key option is not a valid UTF8 string." );
        }
    }

    $opts{email_address} = $self->{user}->email_address;
    $opts{first_name}    = delete $opts{'first-name'} if (defined($opts{'first-name'}));
    $opts{middle_name}   = delete $opts{'middle-name'} if (defined($opts{'middle-name'}));
    $opts{last_name}     = delete $opts{'last-name'} if (defined($opts{'last-name'}));

    return %opts;
}

sub create_user {
    my $self = shift;
    my %user = $self->_require_create_user_params(shift);

    if ( $user{username}
        and Socialtext::User->new( username => $user{username} ) ) {
        $self->_error(
            qq|The username you provided, "$user{username}", is already in use.|
        );
    }

    if ( $user{email_address}
        and Socialtext::User->new( email_address => $user{email_address} ) ) {
        $self->_error(
            qq|The email address you provided, "$user{email_address}", is already in use.|
        );
    }

    $user{username} ||= $user{email_address};
    if (my $account = $self->_require_account('optional')) {
        $self->_ensure_email_passes_filters(
            $user{email_address},
            { account => $account },
        );

        $user{primary_account_id} = $account->account_id;
    }

    my $user
        = eval { Socialtext::User->create( %user, require_password => 1 ) };
    if ( my $e
        = Exception::Class->caught('Socialtext::Exception::DataValidation') )
    {
        my $msg
            = "The following errors occurred when creating the new user:\n\n";
        for my $m ( $e->messages ) {
            $msg .= "  * $m\n";
        }

        $self->_error($msg);
    }
    elsif ( $e = $@ ) {
        die $e;
    }

    $self->_success( 'A new user with the username "'
            . $user->username()
            . '" was created.' );
}

sub _ensure_email_passes_filters {
    my $self           = shift;
    my $email          = shift;
    my $filter_sources = shift;

    my $account = $filter_sources->{account};
    if ($account) {
        $self->_error(
            loc("error.invalid=email,domain",
                $email, $account->restrict_to_domain)
        ) unless $account->email_passes_domain_filter( $email )
    }

    my $workspace = $filter_sources->{workspace};
    if ($workspace) {
        $self->_error(
            loc("error.invalid-invite=email,filter",
                $email, $workspace->invitation_filter)
        ) unless $workspace->email_passes_invitation_filter( $email )
    }
}

sub _require_create_user_params {
    my $self = shift;

    my %opts = $self->_get_options(
        'username:s',
        'email|e:s',
        'password:s',
        'first-name:s',
        'middle-name:s',
        'last-name:s',
        'external-id|X:s',
    );

    my @utf8_fields = ('first-name', 'middle-name', 'last-name');
    for my $key ( grep { defined $opts{$_} } @utf8_fields ) {
        my $val = $opts{$key};

        unless ( Encode::is_utf8($val) or $val =~ /^[\x00-\xff]*$/ ) {
            $self->_error(
                "The value you provided for the $key option is not a valid UTF8 string."
            );
        }
    }

    $opts{email_address}       = delete $opts{email};
    $opts{first_name}          = delete $opts{'first-name'};
    $opts{middle_name}         = delete $opts{'middle-name'};
    $opts{last_name}           = delete $opts{'last-name'};
    $opts{private_external_id} = delete $opts{'external-id'};

    return %opts;
}

sub mass_add_users {
    my $self        = shift;
    my $account     = $self->_require_account('optional');
    my $restriction = $self->_require_restriction('optional');
    my %opts        = $self->_require_mass_add_users_params();

    my $csv = eval { slurp($opts{csv}) };
    if ($@) {
        $self->_error( loc("error.invalid-mass-add-file") );
    }

    require Socialtext::MassAdd;
    my @messages;
    my $has_errors;
    eval {
        my $mass_add = Socialtext::MassAdd->new(
            account => $account,
            pass_cb => sub {
                print $_[0], "\n";
            },
            fail_cb => sub {
                push @messages, $_[0];
                $has_errors++;
            },
            restrictions => $restriction,
        );
        $mass_add->from_csv($csv);
    };
    if ($@) {
        $self->_error($@);
    }

    my $all_messages = join "\n", @messages;
    $has_errors ? $self->_error($all_messages) : $self->_success($all_messages);
}

sub _require_mass_add_users_params {
    my $self = shift;

    return $self->_get_options(
        'csv:s',
    );
}

sub confirm_user {
    my $self = shift;

    my $user = $self->_require_user();
    my $password = $self->_require_string('password');

    my $confirmation = $user->email_confirmation;
    unless ($confirmation) {
        $self->_error( $user->username . ' has already been confirmed' );
    }
    $confirmation->confirm;
    $self->_eval_password_change($user,$password);

    $self->_success( $user->username . ' has been confirmed with password '
                        . $password );
}

sub list_restrictions {
    my $self         = shift;
    my $user         = $self->_require_user();
    my @restrictions = $user->restrictions->all();

    unless (@restrictions) {
        $self->_success( loc("user.no-restrictions") );
    }

    printf '| %20s | %40s |' . "\n",
        loc("user.restriction-type"),
        loc("user.restriction-token");
    foreach my $r (@restrictions) {
        printf '| %20s | %40s |' . "\n",
            $r->restriction_type,
            $r->token;
    }
    $self->_success();
}

sub add_restriction {
    my $self  = shift;
    my $user  = $self->_require_user();
    my $types = $self->_require_restriction();

    foreach my $t (@{$types}) {
        eval {
            my $restriction = $user->add_restriction($t);
            $restriction->send;
        };
        $self->_error($@) if ($@);

        print loc("user.given=name,restriction", $user->username, $t) . "\n";
    }
    $self->_success();
}

sub remove_restriction {
    my $self  = shift;
    my $user  = $self->_require_user();
    my $types = $self->_require_restriction();

    my @restrictions;
    if (!ref($types) && ($types eq 'all')) {
        @restrictions = $user->restrictions->all;
    }
    else {
        foreach my $t (@{$types}) {
            my $restriction = eval { $user->get_restriction($t) };
            if ($restriction) {
                push @restrictions, $restriction;
            }
            else {
                print
                    loc("user.no-such=name,restriction", $user->username, $t)
                    . "\n";
            }
        }
    }

    eval {
        foreach my $r (@restrictions) {
            $r->confirm;
            print loc(
                "user.lifted=restriction,name",
                $r->restriction_type, $user->username,
            ) . "\n";
        }
    };
    $self->_error($@) if ($@);
    $self->_success();
}

sub _require_restriction {
    my $self        = shift;
    my $optional    = shift;
    my %opts        = $self->_get_options('restriction:s@');
    my $restriction = $opts{restriction};

    return if ($optional && !$restriction);

    $self->_error(loc("error.restriction-required"))
        unless $restriction and scalar(@$restriction);

    return 'all' if ($restriction->[0] eq 'all');

    for my $type (@{$restriction}) {
        $self->_error(
            loc("error.unknown-restriction=type", $type)
        ) unless Socialtext::User::Restrictions->ValidRestrictionType($type);
    }

    return $restriction;
}

# revoke a user's access to everything
sub deactivate_user {
    my $self = shift;

    my $user = $self->_require_user();

    if (   $user->user_id eq Socialtext::User->SystemUser->user_id
        || $user->user_id eq Socialtext::User->Guest->user_id ) {

        $self->_error( 'You may not deactivate ' . $user->username );
    }

    my @output = ();

    # remove the user from their workspaces
    my $workspaces = $user->workspaces();
    while ( my $workspace = $workspaces->next() ) {
        push @output, $workspace->name;
    }

    if ($user->is_business_admin()) {
        push @output, "Removed Business Admin";
    }
    if ($user->is_technical_admin()) {
        push @output, "Removed Technical Admin";
    }

    $user->deactivate;
    if (@output) {
        $self->_success(
            $user->username . ' has been removed from workspaces ' . join ', ',
            @output
        );
    } else {
        $self->_success($user->username . ' has been deactivated.');
   }
}

sub add_member {
    my $self = shift;
    my $role = Socialtext::Role->Member();
    my %jump = (
        'user-workspace'  => sub { $self->_add_user_to_workspace_as($role) },
        'group-account'   => sub { $self->_add_group_to_account_as($role) },
        'group-workspace' => sub { $self->_add_group_to_workspace_as($role) },
        'user-group'      => sub { $self->_add_user_to_group_as($role) },
        'user-account'    => sub { $self->_add_user_to_account_as($role) },
        'account-workspace' => sub { $self->_add_account_to_ws_as($role)},
    );
    my $type = $self->_type_of_entity_collection_operation( keys %jump );

    return $jump{$type}->();
}

sub _type_of_entity_collection_operation {
    my $self     = shift;
    my @possible = @_;

    # Split up the possible combinations into the list of possible entities
    # and collections
    my (@entities, @collections);
    foreach my $combination (@possible) {
        my ($entity, $collection) = split /-/, $combination;
        push @entities, $entity;
        push @collections, $collection;
    }

    # Map the entity/collection types to the CLI options that could be used to
    # get them.
    my %cli_option_map = (
        account   => ['account:s'],
        group     => ['group:s'],
        user      => ['username:s', 'email:s'],
        workspace => ['workspace:s'],
    );

    my @cli_entities    = uniq map { @{ $cli_option_map{$_} } } @entities;
    my @cli_collections = uniq map { @{ $cli_option_map{$_} } } @collections;

    my %opts = $self->_argv_peekahead(@cli_entities, @cli_collections);

    # March through the list of acceptable combinations and see if we've got
    # sufficient args for any of them.
    foreach my $combination (@possible) {
        my ($entity, $collection) = split /-/, $combination;
        my $has_entity =
            grep { exists $opts{$_} }
            map { s/:.*//; $_ }
            @{$cli_option_map{$entity}};
        my $has_collection =
            grep { exists $opts{$_} }
            map { s/:.*//; $_ }
            @{$cli_option_map{$collection}};
        return $combination if ($has_entity && $has_collection);
    }

    # Unable to find args to satisfy any of the combinations; throw error.
    s/:.*// foreach @cli_entities;          # remove ":s"
    s/^/--/ foreach @cli_entities;          # add leading "--"

    s/:.*// foreach @cli_collections;       # remove ":s"
    s/^/--/ foreach @cli_collections;       # add leading "--"

    $self->_error(
        loc(
            "error.required=command,entity,collection",
            $self->{command},
            join(' ', @cli_entities),
            join(' ', @cli_collections),
        )
    );
}

sub add_group_admin {
    my $self  = shift;
    my $admin = Socialtext::Role->Admin();

    $self->_add_user_to_group_as($admin);
}

sub _add_user_to_group_as {
    my $self         = shift;
    my $new_role     = shift;
    my $user         = $self->_require_user();
    my $group        = $self->_require_group();
    my $current_role = $group->role_for_user($user, {direct => 1});

    $self->_error(
        loc("error.update-remote-group")
    ) unless $group->can_update_store;

    if ( $current_role ) {
        $self->_error(
            loc("error.user-role-exists=role,group",
                $current_role->display_name, $group->display_name)
        ) if $current_role->name eq $new_role->name;
    }

    $group->assign_role_to_user( user => $user, role => $new_role );
    $self->_success(
        loc("cli.member-added=user,role,group",
            $user->username, $new_role->name, $group->display_name)
    );
}

sub delete_group {
    my $self = shift;
    my $group = $self->_require_group();
    my $gid = $group->group_id;
    
    eval { $group->delete };
    if ($@) {
        warn $@;
        $self->_error(loc("error.delete-group=id,message", $gid, $@));
    }
    $self->_success(loc("group.deleted=id", $gid));
}

# We don't need to be magical here because there is no 'admin' role for
# Groups within Accounts (yet).
sub _add_group_to_account_as {
    my $self         = shift;
    my $new_role     = shift;
    my $group        = $self->_require_group();
    my $account      = $self->_require_account();
    my $current_role = $account->role_for_group($group);

    $self->_check_account_role(
        cur_role  => $current_role,
        new_role  => $new_role,
        name      => $group->driver_group_name,
        acct_name => $account->name,
    );

    $account->assign_role_to_group( group => $group, role => $new_role );
    $self->_success(
        loc("cli.member-added=name,role,account",
            $group->display_name,
            $new_role->display_name,
            $account->name,
        )
    );
}

sub _add_user_to_account_as {
    my $self         = shift;
    my $new_role     = shift;
    my $user         = $self->_require_user();
    my $account      = $self->_require_account();
    my $current_role = $account->role_for_user($user, direct => 1);

    $self->_check_account_role(
        cur_role  => $current_role,
        new_role  => $new_role,
        name      => $user->username,
        acct_name => $account->name,
    );

    $account->assign_role_to_user( user => $user, role => $new_role );
    $self->_success(
        loc("cli.member-added=name,role,account",
            $user->username,
            $new_role->display_name,
            $account->name,
        )
    );
}

sub _check_account_role {
    my $self = shift;
    my %p    = @_;

    if ($p{cur_role}) {
        $self->_error(
            loc("error.role-exists=user,role,account",
                $p{name}, $p{cur_role}->display_name, $p{acct_name})
        ) if $p{cur_role}->name eq $p{new_role}->name;
    }
}

sub _add_user_to_workspace_as {
    my $self         = shift;
    my $new_role     = shift;
    my $user         = $self->_require_user();
    my $ws           = $self->_require_workspace();
    my $current_role = $ws->role_for_user($user, direct => 1);

    $self->_ensure_email_passes_filters(
        $user->email_address,
        { account => $ws->account, workspace => $ws },
    );

    $self->_check_workspace_role(
        cur_role => $current_role,
        new_role => $new_role,
        name     => $user->username,
        ws_name  => $ws->name,
    );

    $ws->assign_role_to_user( user => $user, role => $new_role );
    $self->_success(
        loc("cli.member-added=name,role,wiki",
        $user->username, $new_role->display_name, $ws->name)
    );
}

sub _add_group_to_workspace_as {
    my $self     = shift;
    my $new_role = shift;
    my $ws       = $self->_require_workspace();
    my $group    = $self->_require_group();

    $self->_add_thingy_to_ws_as($new_role, group => $group, $ws);
}

sub _add_account_to_ws_as {
    my $self     = shift;
    my $new_role = shift;
    my $ws       = $self->_require_workspace();
    my $account  = $self->_require_account();

    eval {
        $self->_add_thingy_to_ws_as($new_role, account => $account, $ws);
    };
    warn $@ if $@;
}

sub _add_thingy_to_ws_as {
    my $self     = shift;
    my $new_role = shift;
    my $type     = shift;
    my $thingy = shift;
    my $ws = shift;

    my $current_role_method = "role_for_$type";
    my $current_role = $ws->$current_role_method($thingy);

    $self->_check_workspace_role(
        cur_role => $current_role,
        new_role => $new_role,
        name     => $thingy->name,
        ws_name  => $ws->name,
    );

    my $assign_method = "assign_role_to_$type";
    eval { $ws->$assign_method($type => $thingy, role => $new_role); };
    if (my $e = $@) {
        $e =~ s/\s+at\s+.+\.pm\s+line\s+\d+.*//;
        $self->_error(loc($e));
    }
    $self->_success(
        loc("cli.member-added=name,role,wiki",
            $thingy->name,
            $new_role->display_name,
            $ws->name)
    );

}

sub _check_workspace_role {
    my $self = shift;
    my %p    = @_;

    if ( $p{cur_role} ) {
        $self->_error(
            loc("error.role-exists=user,role,wiki",
                $p{name}, $p{cur_role}->display_name, $p{ws_name})
        ) if $p{cur_role}->name eq $p{new_role}->name;

        # Do not allow the code to "downgrade" from admin to member,
        # the user has to use remove-workspace-admin for that.
        $self->_error(
            loc("error.admin-role-exists=user,wiki",
                $p{name},
                $p{ws_name}
            )
        ) if $p{cur_role}->name eq Socialtext::Role->Admin()->name;
    }
}

sub remove_member {
    my $self = shift;
    my %jump = (
        'user-workspace'  => sub { $self->_remove_user_from_workspace() },
        'group-workspace' => sub { $self->_remove_group_from_workspace() },
        'group-account'   => sub { $self->_remove_group_from_account() },
        'user-group'      => sub { $self->_remove_user_from_group() },
        'user-account'    => sub { $self->_remove_user_from_account() },
        'workspace-account' => sub { $self->_remove_account_from_ws() },
    );
    my $type = $self->_type_of_entity_collection_operation( keys %jump );

    return $jump{$type}->();
}

sub _remove_user_from_account {
    my $self      = shift;
    my $user      = $self->_require_user();
    my $account = $self->_require_account();

    if ( $user->primary_account_id == $account->account_id ) {
        my $email   = $user->email_address;
        my $account = $account->name;
        my $msg     = join("\n",
            loc("error.remove-user-primary-account"),
            '',
            loc("info.change-primary-account:"),
            " * st-admin set-user-account --email $email --account <account-name>",
            " * st-admin remove-member --email $email --account $account",
            '',
            loc("info.deactivated-user:"),
            " * st-admin deactivate-user --email $email",
        );
        $self->_error($msg);
    }

    $self->_remove_user_from_thing( $user, $account );
}

sub _remove_user_from_workspace {
    my $self      = shift;
    my $user      = $self->_require_user();
    my $workspace = $self->_require_workspace();

    $self->_remove_user_from_thing( $user, $workspace );
}

sub _remove_user_from_thing {
    my $self    = shift;
    my $user    = shift;
    my $thing   = shift; # workspace or account
    my $current = $thing->role_for_user($user, direct => 1);
    my $member  = Socialtext::Role->Member();

    if (!$current) {
        if (my $indirect_role = $thing->role_for_user($user, direct => 0)) {
            $self->_error(
                loc('error.remove-indirect=name,role,container',
                    $user->username, $indirect_role->name, $thing->name)
            );
        }
        else {
            $self->_error(
                loc('error.not-member=name,container',
                    $user->username, $thing->name)
            );
        }
    }

    $self->_error(
        loc("error.no-role=name,role,container",
            $user->username, $member->display_name, $thing->name)
    ) if $current->name ne $member->name;

    $thing->remove_user( user => $user, role => $member );

    # Does the user still have a role in this thing indirectly?
    my $role = $thing->role_for_user($user);
    $self->_success(
        loc("cli.indirect-member=name,role,container",
            $user->username, $role->display_name, $thing->name)
    ) if $role;

    $self->_success(
        loc("cli.member-removed=user,container",
            $user->username, $thing->name)
    );
}

sub remove_group_admin {
    my $self = shift;
    return $self->_remove_user_from_group(downgrade => 1);
}

sub _remove_user_from_group {
    my $self  = shift;
    my %p = (downgrade => 0, @_);

    my $user  = $self->_require_user();
    my $group = $self->_require_group();

    $self->_error(
        loc("error.update-remote-group")
    ) unless $group->can_update_store;

    my $role = $group->role_for_user( $user, {direct => 1});

    $self->_error(
        loc("error.not-member=name,container",
            $user->username, $group->driver_group_name)
    ) unless $role;

    if ($role->name eq 'admin' && $p{downgrade}) {
        $group->assign_role_to_user(
            user => $user,
            role => Socialtext::Role->Member(),
        );
        $self->_success(
            loc("cli.member-added=user,group",
                $user->username, $group->driver_group_name)
        );
    }
    elsif ($role->name eq 'member' && $p{downgrade}) {
        $self->_success(
            loc("error.already-a-member=name,group",
                $user->username, $group->driver_group_name)
        );
    }
    else {
        $group->remove_user( user => $user );
        $self->_success(
            loc("cli.member-removed=name,container",
                $user->username, $group->driver_group_name)
        );
    }

}

sub _remove_group_from_account {
    my $self    = shift;
    my $group   = $self->_require_group();
    my $account = $self->_require_account();

    if ( $account->account_id == $group->primary_account_id ) {
        $self->_error(
            loc("error.remove-primary=account",
                $account->name)
        );
    }

    $self->_remove_thing_from_thing(
        group   => $group,
        account => $account
    );
}

sub _remove_group_from_workspace {
    my $self      = shift;
    my $group     = $self->_require_group();
    my $workspace = $self->_require_workspace();

    $self->_remove_thing_from_thing(
        group     => $group,
        workspace => $workspace
    );
}

sub _remove_account_from_ws {
    my $self      = shift;
    my $workspace = $self->_require_workspace();
    my $account   = $self->_require_account();

    $self->_remove_thing_from_thing(
        account   => $account,
        workspace => $workspace
    );
}

sub _remove_thing_from_thing {
    my $self           = shift;
    my $condemned_type = shift;
    my $condemned      = shift;
    my $container_tupe = shift;
    my $container      = shift;

    my $has_method    = "has_$condemned_type";
    my $remove_method = "remove_$condemned_type";
    my $role_method   = "role_for_$condemned_type";

    unless ($container->$has_method($condemned)) {
       $self->_error(
           loc("error.not-member=name,container",
               $condemned->name, $container->name)
        );
    }

    $container->$remove_method($condemned_type => $condemned);
    my $role = $container->$role_method($condemned);
    my $msg;
    if ($role) {
        $msg = loc("cli.indirect-member=name,role,container",
            $condemned->name, $role->display_name, $container->name);
    }
    else {
        $msg = loc('cli.member-removed=name,container',
            $condemned->name, $container->name);
    }

    return $self->_success($msg);
}

sub _thingy_type {
    my $self   = shift;
    my $thingy = shift;
    return 'user'      if ($thingy->isa('Socialtext::User'));
    return 'group'     if ($thingy->isa('Socialtext::Group'));
    return 'workspace' if ($thingy->isa('Socialtext::Workspace'));
    return 'account'   if ($thingy->isa('Socialtext::Account'));
    die "unknown thingy type";  # XXX: bad error, but what to do?
}

sub _downgrade_thingy_to_member_in_container {
    my $self       = shift;
    my $thingy     = shift;
    my $container  = shift;
    my $from_role  = shift;
    my $MemberRole = Socialtext::Role->Member;

    my $role = Socialtext::Role->new(name => $from_role);

    # figure out what type the "thingy" and "container" are
    my $type = $self->_thingy_type($thingy);
    my $container_type = $self->_thingy_type($container);

    my $has_role_method = "${type}_has_role";
    unless ($container->$has_role_method($type => $thingy, role => $role)) {
        $self->_error(
            loc("error.no-role=name,role,container,type",
                $thingy->display_name, $role->name,
                $container->name, ucfirst($container_type),
            )
        );
    }

    my $role_for_method = "role_for_${type}";
    my $direct_role = $container->$role_for_method($thingy, direct => 1);
    unless ($direct_role) {
        my $indirect_role = $container->$role_for_method($thingy, direct => 0);
        $self->_error(
            loc('error.remove-indirect=name,role,container',
                $thingy->display_name, $indirect_role->name, $container->name,
            )
        )
    }

    my $assign_method = "assign_role_to_${type}";
    $container->$assign_method(
        $type => $thingy,
        role  => $MemberRole,
    );

    # Let the Admin know if the "Thingy" has a Group membership which gives a
    # higher membership level than what the "Thingy" is left with after
    # downgrading their explicit Role.
    my $current_role = $container->$role_for_method($thingy);
    if ($current_role->name ne $MemberRole->name) {
        $self->_error(
            loc("cli.indirect-member=name,role,container",
                $thingy->display_name, $current_role->name, $container->name,
            )
        );
    } 

    $self->_success(
        loc("cli.member-removed=name,role,container,type",
            $thingy->display_name, $from_role,
            $container->name, ucfirst($container_type),
        )
    );
}

sub add_workspace_admin {
    my $self = shift;
    my %jump = (
        'user-workspace' => sub {
            $self->_add_user_to_workspace_as(Socialtext::Role->Admin());
        },
        'group-workspace' => sub {
            $self->_add_group_to_workspace_as(Socialtext::Role->Admin());
        },
    );

    my $type = $self->_type_of_entity_collection_operation(keys %jump);
    return $jump{$type}->();
}

sub remove_workspace_admin {
    my $self = shift;
    my %jump = (
        'user-workspace' => sub {
            $self->_downgrade_user_to_member_in_workspace(Socialtext::Role->Admin());
        },
        'group-workspace' => sub {
            $self->_downgrade_group_to_member_in_workspace(Socialtext::Role->Admin());
        }
    );
    my $type = $self->_type_of_entity_collection_operation(keys %jump);
    return $jump{$type}->();
}

sub add_account_admin {
    my $self = shift;
    return $self->_add_user_to_account_as(Socialtext::Role->Admin());
}

sub remove_account_admin {
    my $self = shift;
    return $self->_downgrade_user_to_member_in_account(Socialtext::Role->Admin);
}

sub _downgrade_user_to_member_in_workspace {
    my $self = shift;
    my $role = shift;
    my $user = $self->_require_user();
    my $ws   = $self->_require_workspace();
    return $self->_downgrade_thingy_to_member_in_container(
        $user, $ws, $role->name,
    );
}

sub _downgrade_group_to_member_in_workspace {
    my $self  = shift;
    my $role  = shift;
    my $group = $self->_require_group();
    my $ws    = $self->_require_workspace();
    return $self->_downgrade_thingy_to_member_in_container(
        $group, $ws, $role->name,
    );
}

sub _downgrade_user_to_member_in_account {
    my $self = shift;
    my $role = shift;
    my $user = $self->_require_user();
    my $acct = $self->_require_account();
    return $self->_downgrade_thingy_to_member_in_container(
        $user, $acct, $role->name,
    );
}

sub _downgrade_group_to_member_in_account {
    my $self  = shift;
    my $role  = shift;
    my $group = $self->_require_group();
    my $acct  = $self->_require_account();
    return $self->_downgrade_thingy_to_member_in_container(
        $group, $acct, $role->name,
    );
}

sub add_workspace_impersonator {
    my $self = shift;
    my %jump = (
        'user-workspace' => sub {
            $self->_add_user_to_workspace_as(Socialtext::Role->Impersonator());
        },
        'group-workspace' => sub {
            $self->_add_group_to_workspace_as(Socialtext::Role->Impersonator());
        },
    );

    my $type = $self->_type_of_entity_collection_operation(keys %jump);
    return $jump{$type}->();
}

sub remove_workspace_impersonator {
    my $self = shift;
    my %jump = (
        'user-workspace' => sub {
            $self->_downgrade_user_to_member_in_workspace(Socialtext::Role->Impersonator());
        },
        'group-workspace' => sub {
            $self->_downgrade_group_to_member_in_workspace(Socialtext::Role->Impersonator());
        }
    );
    my $type = $self->_type_of_entity_collection_operation(keys %jump);
    return $jump{$type}->();
}

sub add_account_impersonator {
    my $self = shift;
    my %jump = (
        'user-account' => sub {
            $self->_add_user_to_account_as(Socialtext::Role->Impersonator());
        },
        'group-account' => sub {
            $self->_add_group_to_account_as(Socialtext::Role->Impersonator());
        },
    );

    my $type = $self->_type_of_entity_collection_operation(keys %jump);
    return $jump{$type}->();
}

sub remove_account_impersonator {
    my $self = shift;
    my %jump = (
        'user-account' => sub {
            $self->_downgrade_user_to_member_in_account(Socialtext::Role->Impersonator());
        },
        'group-account' => sub {
            $self->_downgrade_group_to_member_in_account(Socialtext::Role->Impersonator());
        }
    );
    my $type = $self->_type_of_entity_collection_operation(keys %jump);
    return $jump{$type}->();
}

sub change_password {
    my $self = shift;
    my $user = $self->_require_user();
    my $pw   = $self->_require_string('password');

    $self->_eval_password_change($user,$pw);

    # If the User had a "change my password" action in-flight, clear that out;
    # we've now got a password for the User.
    my $restriction = $user->password_change_confirmation;
    $restriction->clear if $restriction;

    $self->_success(
        loc('user.password-changed=name', $user->username),
    );
}

sub _eval_password_change {
    my $self = shift;
    my $user = shift;
    my $pw = shift;

    $self->_error(
        loc("error.update-remote-password")
     ) unless $user->can_update_store();

    eval { $user->update_store( password => $pw ) };

    if ( my $e
        = Exception::Class->caught('Socialtext::Exception::DataValidation') )
    {
        my $msg
            = "The following errors occurred when changing the password:\n\n";
        for my $m ( $e->messages ) {
            $msg .= "  * $m\n";
        }

        $self->_error($msg);
    }
    elsif ( $e = $@ ) {
        die $e;
    }
}

sub disable_email_notify {
    my $self = shift;

    my $user = $self->_require_user();
    my ( $hub, $main ) = $self->_require_hub($user);

    my $ws = $hub->current_workspace();

    unless ( $ws->has_user( $user ) ) {
        $self->_error( $user->username
                . ' is not a member of the '
                . $ws->name
                . ' workspace.' );
    }

    # XXX - this wipes out other email-related prefs, but that's
    # probably ok for now
    $hub->preferences()->store(
        $user,
        email_notify => { notify_frequency => "0" }
    );

    $self->_success( 'Email notify has been disabled for '
            . $user->username()
            . ' in the '
            . $ws->name()
            . " workspace.\n" );
}

sub set_locale {
    my $self = shift;

    my $user = $self->_require_user();
    my ( $hub, $main ) = $self->_require_hub($user);

    # XXX: ick; we're accessing internal methods in another class.
    my $prefs         = $hub->preferences->_load_all_for_user($user);
    my $display_prefs = $prefs->{display};
    loc_lang( $display_prefs->{locale} || 'en' );

    my $new_locale = $self->_require_string('locale');
    if ( not valid_code($new_locale) ) {
        $self->_error( loc( "error.invalid=locale", $new_locale ) );
    }

    $display_prefs->{locale} = $new_locale;
    $hub->preferences->store( $user, display => $display_prefs );
    loc_lang($new_locale);
    $self->_success(
        loc(
            'lang.changed=user,locale',
            $user->username, $new_locale
        )
    );
}

sub delete_tag {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my @tags = $self->_require_tags($hub)
        or return;

    for my $cat (@tags) {
        $hub->category->delete(
            tag  => $cat,
            user => $hub->current_user(),
        );
    }

    my $msg = 'The following tags were deleted from the ';
    $msg .= $hub->current_workspace()->name() . " workspace:\n";
    $msg .= "  * $_\n" for @tags;

    $self->_success($msg);
}
{
    no warnings 'once';
    *delete_categories = \&delete_tag;
    *delete_category   = \&delete_tag;
}

sub search_tags {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my @tags = $self->_require_tags($hub)
        or return;

    my $msg = "Matched the following tags:\n";
    $msg .= "  * $_\n" for @tags;

    $self->_success($msg);
}
{
    no warnings 'once';
    *search_categories = \&search_tags;
}

sub create_workspace {
    my $self = shift;
    my %ws   = $self->_require_create_workspace_params(shift);

    require Socialtext::Hostname;

    if ( $ws{name} and Socialtext::Workspace->new( name => $ws{name} ) ) {
        $self->_error(
            qq|The workspace name you provided, "$ws{name}", is already in use.|
        );
    }

    if ( $ws{'clone-pages-from'} and !Socialtext::Workspace->new( name => $ws{'clone-pages-from'} ) ) {
        $self->_error(
            qq|The workspace name you provided, "$ws{'clone-pages-from'}", does not exist.|
        );
    }

    my $account = Socialtext::Account->Default();
    if (my $name = delete $ws{account}) {
        $account = $self->_load_account($name);
    }
    $ws{account_id} = $account->account_id();
    my $isAllUsersWorkspace = delete($ws{'all-users-workspace'});

    my $ws = eval {
        my @extra_args;
        push @extra_args, delete($ws{empty}) ? (skip_default_pages => 1) : ();

        push @extra_args,
            (clone_pages_from => delete($ws{'clone-pages-from'}))
            if $ws{'clone-pages-from'};

        Socialtext::Workspace->create( %ws, @extra_args );
    };

    if ( my $e
        = Exception::Class->caught('Socialtext::Exception::DataValidation') )
    {
        my $msg
            = "The following errors occurred when creating the new workspace:\n\n";
        for my $m ( $e->messages ) {
            $msg .= "  * $m\n";
        }

        $self->_error($msg);
    }
    elsif ( $e = $@ ) {
        die $e;
    }

    $ws->assign_role_to_account(account => $account) if ($isAllUsersWorkspace);
    $self->_success(
        'A new workspace named "' . $ws->name() . '" was created.' );
}

sub _require_create_workspace_params {
    my $self = shift;

    return $self->_get_options(
        'name:s',
        'title:s',
        'account:s',
        'clone-pages-from:s',
        'all-users-workspace',
        'empty',
    );
}

sub _load_workspace {
    my ($self, $workspace_name) = @_;
    my $workspace = Socialtext::Workspace->new( name => $workspace_name );
    unless ($workspace) {
        $self->_error(
            loc('error.no-wiki=name', $workspace_name)
        );
    }
}

sub _load_account {
    my $self = shift;
    my $account_name = shift;

    my $account = Socialtext::Account->new( name => $account_name );
    unless ($account) {
        $self->_error(qq|There is no account named "$account_name".|);
    }
    return $account;
}

sub create_account {
    my $self  = shift;
    my $name  = $self->_require_string('name');
    my $type  = $self->_optional_string('type');
    my $user  = Socialtext::User->SystemUser();
    my $ws    = Socialtext::NoWorkspace->new();
    my ($hub) = $self->_make_hub($ws, $user);

    require Socialtext::Account;

    if ( $name and Socialtext::Account->new( name => $name ) ) {
        $self->_error(
            qq|The account name you provided, "$name", is already in use.|);
    }

    my $account = eval { $hub->account_factory->create( 
            is_system_created => 1,
            name => $name,
            ($type ? (account_type => $type) : ()),
        ) };

    if ( my $e
        = Exception::Class->caught('Socialtext::Exception::DataValidation') )
    {
        my $msg
            = "The following errors occurred when creating the new account:\n\n";
        for my $m ( $e->messages ) {
            $msg .= "  * $m\n";
        }

        $self->_error($msg);
    }
    elsif ( $e = $@ ) {
        die $e;
    }

    $self->_success(
        'A new account named "' . $account->name() . '" was created.' );
}

sub set_permissions {
    my $self = shift;

    my $set_name = $self->_require_string('permissions');
    my %opts = $self->_argv_peekahead(qw/workspace:s group:s/);

    my ($object,$name);
    if ($opts{workspace}) {
        my $ws  = $self->_require_workspace();
        $object = 'workspace';
        $name   = $ws->name;

        eval { $ws->permissions->set( set_name => $set_name ); };
        if ($@) {
            $self->_error(
                loc("error.no-permission=name", $set_name));
        }
    }
    elsif ($opts{group}) {
        my $group = $self->_require_group();
        $object = 'group';
        $name   = $group->name;

        eval { $group->update_store({permission_set => $set_name}) };
        if ($@) {
            $self->_error(
                loc("error.update-permission=group", $name));
        }
    }
    else {
        $self->_error(
            loc("error.group-or-wiki-required")
        );
    }

    $self->_success(
        loc("acl.changed=name,object,set",
            $name, $object, $set_name)
    );
}

sub _argv_peekahead {
    my $self = shift;
    my @to_check = @_;

    my $argv = $self->{argv};
    my %opts = $self->_get_options(@to_check); # this is destructive
    $self->{argv} = $argv;

    return %opts;
}

sub add_permission {
    my $self = shift;

    my $ws   = $self->_require_workspace();
    my $perm = $self->_require_permission();
    my $role = $self->_require_role();

    $ws->permissions->add(
        permission => $perm,
        role       => $role,
    );

    $self->_success( 'The '
            . $perm->name()
            . ' permission has been granted to the '
            . $role->display_name()
            . ' role in the '
            . $ws->name()
            . " workspace.\n" );
}

sub remove_permission {
    my $self = shift;

    my $ws   = $self->_require_workspace();
    my $perm = $self->_require_permission();
    my $role = $self->_require_role();

    $ws->permissions->remove(
        permission => $perm,
        role       => $role,
    );

    $self->_success( 'The '
            . $perm->name()
            . ' permission has been revoked from the '
            . $role->display_name()
            . ' role in the '
            . $ws->name()
            . " workspace.\n" );
}

sub show_workspace_config {
    my $self = shift;

    my $msg = $self->_show_config( $self->_require_workspace );

    $self->_success( $msg );
}

sub show_account_config {
    my $self = shift;

    my $account = $self->_require_account;
    my $msg     = $self->_show_config( $account );


    $self->_success( $msg );
}

sub _show_config {
    my $self = shift;
    my $obj  = shift;

    my $thing_name = '';
    if ($obj->isa('Socialtext::Workspace')) {
        $thing_name = "Workspace";
    }
    elsif ($obj->isa('Socialtext::Account')) {
        $thing_name = "Account";
    }

    my $msg = 'Config for ' . $obj->name . " $thing_name\n\n";
    my $fmt = '%-32s: %s';
    my $hash = $obj->to_hash;
    delete $hash->{name};
    delete $hash->{pref_blob};

    for my $c ( sort keys %$hash ) {
        my $val = $hash->{$c};
        $val = 'NULL' unless defined $val;
        $val = q{''} if $val eq '';

        $msg .= sprintf( $fmt, $c, $val );
        $msg .= "\n";
    }

    if ($thing_name eq 'Workspace') {
        $msg .= sprintf( $fmt, 'ping URIs', join ' - ', $obj->ping_uris );
        $msg .= "\n";
        $msg .= sprintf( $fmt, 'custom comment form fields', join ' - ',
            $obj->comment_form_custom_fields );
        $msg .= "\n";
    }

    if ($thing_name eq 'Account') {
        my $prefs = $obj->prefs->all_prefs;
        my $separator = "\n" . " "x34;
        for my $index (keys %$prefs) {
            for my $key (keys %{$prefs->{$index}}) {
                $msg .= sprintf( '%-32s: ', "($index) $key" );
                $msg .= $prefs->{$index}{$key} . "\n";
            }
        }
    }

    my @enabled         = $obj->plugins_enabled;
    my %enabled_as_hash = map { $_ => 1 } @enabled;
    my @installed       = Socialtext::Pluggable::Adapter->new->plugin_list;
    my $separator       = "\n" . " "x34;

    $msg .= sprintf( '%-32s: ', 'modules_installed' );
    foreach my $installed ( @installed ) {
        $msg .= $installed;
        $msg .= ' (enabled)' if defined $enabled_as_hash{$installed};
        $msg .= $separator;
    }

    return $msg;
}

sub set_account_config {
    my $self = shift;

    my $account = $self->_require_account;
    my $pref_ix = $self->_optional_string('index');
    return $self->_update_account_prefs($account => $pref_ix) if $pref_ix;

    my %update;
    while ( my ($key, $value) = splice @{ $self->{argv} }, 0, 2 ) {
        next if $key =~ /_id$/;
        
        $self->_error("$key is not a valid account config key")
            unless ($account->can($key));

        $value = undef if $value eq '-null-';

        $update{$key} = $value;
    }
    eval { $account->update(%update) };
    if ( my $e
        = Exception::Class->caught('Socialtext::Exception::DataValidation') )
    {
        my $msg
            = "The following errors occurred when setting the account config:\n\n";
        for my $m ( $e->messages ) {
            $msg .= "  * $m\n";
        }

        $self->_error($msg);
    }
    elsif ( $e = $@ ) {
        die $e;
    }

    $self->_success(
        'The account config for ' . $account->name() . ' has been updated.' );
}

sub _update_account_prefs {
    my $self = shift;
    my $account = shift;
    my $index = shift;

    my $prefs = $account->prefs->all_prefs->{$index};

    while (my ($key,$value) = splice(@{$self->{argv}}, 0, 2)) {
        $prefs->{$key} = $value;
    }

    eval {
        $account->prefs->save({$index=>$prefs});
    };
    if (my $e = $@) {
        $self->_error($@);
    }

    $self->_success(
        "Updated the $index prefs for the ". $account->name ." account");
}

sub reset_account_skin {
    my $self = shift;
    my $account = $self->_require_account;
    my %opts    = $self->_get_options('skin:s');


    $self->_error("reset-account-skin requires --skin parameter")
        unless defined $opts{skin};

    $self->_error("--skin requires a skin name to be specified")
        unless $opts{skin};

    eval { $account->reset_skin($opts{skin}) };
    if ( my $e
        = Exception::Class->caught('Socialtext::Exception::DataValidation') )
    {
        my $msg
            = "The following errors occurred when setting the account skin\n\n";
        for my $m ( $e->messages ) {
            $msg .= "  * $m\n";
        }

        $self->_error($msg);
    }
    elsif ( $e = $@ ) {
        die $e;
    }

    $self->_success(
        'The skin for account ' . $account->name() . ' and its workspaces has been updated.' );

}

sub set_workspace_config {
    my $self = shift;

    my ($hub, $main) = $self->_require_hub();
    my $ws = $hub->current_workspace;

    # XXX - these checks belong in Socialtext::Workspace->update()
    my %unsettable = map { $_ => 1 } qw( name creation_datetime );
    my %update;
    while ( my ( $key, $value ) = splice @{ $self->{argv} }, 0, 2 ) {
        next if $key =~ /_id$/ and $key ne 'account_id';

        if ($key =~ m/account[-_]name/) {
            my $account = Socialtext::Account->new(name => $value);
            $self->_error(
                loc("error.no-account=name",
                    $value)) unless $account;
            $key = 'account_id';
            $value = $account->account_id;
        }

        if ( $unsettable{$key} ) {
            $self->_error("Cannot change $key after workspace creation.");
        }

        unless ( $ws->can($key) ) {
            $self->_error("$key is not a valid workspace config key.");
        }

        $value = undef if $value eq '-null-';

        $update{$key} = $value;
    }

    eval { $ws->update(%update) };

    if ( my $e
        = Exception::Class->caught('Socialtext::Exception::DataValidation') )
    {
        my $msg
            = "The following errors occurred when setting the workspace config:\n\n";
        for my $m ( $e->messages ) {
            $msg .= "  * $m\n";
        }

        $self->_error($msg);
    }
    elsif ( $e = $@ ) {
        die $e;
    }

    if ( defined $update{allows_page_locking}
        && $update{allows_page_locking} == 0
    ) {
        my @ids = $hub->pages->all_ids_locked();
        for my $page_id ( @ids ) {
            my $page = $hub->pages->new_from_name( $page_id );
            $page->update_lock_status( 0 );
        }
    }

    $self->_success(
        'The workspace config for ' . $ws->name() . ' has been updated.' );
}


sub set_logo_from_file {
    my $self = shift;

    my $ws       = $self->_require_workspace();
    my $filename = $self->_require_string('file');

    eval {
        $ws->set_logo_from_file(
            filename   => $filename,
        );
    };

    if ( my $e
        = Exception::Class->caught('Socialtext::Exception::DataValidation') )
    {
        my $msg
            = "The following errors occurred when trying to use this logo:\n\n";
        for my $m ( $e->messages ) {
            $msg .= "  * $m\n";
        }

        $self->_error($msg);
    }
    elsif ( $e = $@ ) {
        die $e;
    }

    $self->_success( 'The logo file was imported as the new logo for the '
            . $ws->name()
            . ' workspace.' );
}

sub set_comment_form_custom_fields {
    my $self = shift;

    my $ws = $self->_require_workspace();

    $ws->set_comment_form_custom_fields( fields => $self->{argv} );

    $self->_success( 'The custom comment form fields for the '
            . $ws->name()
            . ' workspace have been updated.' );
}

sub set_ping_uris {
    my $self = shift;

    my $ws = $self->_require_workspace();

    $ws->set_ping_uris( uris => $self->{argv} );

    $self->_success( 'The ping uris for the '
            . $ws->name()
            . ' workspace have been updated.' );
}

sub rename_workspace {
    my $self = shift;

    my $ws = $self->_require_workspace();

    my $name = $self->_require_string('name');

    my $old_name = $ws->name();
    $ws->rename( name => $name );

    $self->_success("The $old_name workspace has been renamed to $name.");
}

sub show_acls {
    my $self = shift;

    my $ws = $self->_require_workspace();

    require List::Util;
    require Socialtext::Permission;
    require Socialtext::Role;

    my @perms = Socialtext::Permission->All()->all();

    my $msg = "ACLs for " . $ws->name . " workspace\n\n";
    my $setname = $ws->permissions->current_set_name();
    $msg .= "  permission set name: "
        . $setname . 
        ($Socialtext::Workspace::Permissions::DeprecatedPermissionSets{ $setname } ? " (deprecated)" : ""  ).
        "\n\n";

    my $first_col = '<' x List::Util::max( map { length $_->name } @perms );

    my $format = "| \@$first_col| ";

    # We want the Roles in a specific order; lowest-highest effectiveness,
    # with custom Roles appearing afterwards in alphabetical order.
    my %all_roles = map { $_->name() => $_ } 
        grep { Socialtext::Workspace::Permissions->IsValidRole($_) }
        Socialtext::Role->All()->all();
    my @roles = map { delete $all_roles{$_} }
        grep { exists $all_roles{$_} }
        Socialtext::Role->DefaultRoleNames;
    push @roles, lsort_by name => values %all_roles;

    for my $role (@roles) {
        my $col = '|' x length $role->display_name();
        $format .= "\@$col\@|";
    }
    $format .= "\n";

    # Holy crap, a (more or less) legitimate use for Perl's formats
    # feature! I'd prefer Text::Reform but it seems silly to add a
    # dependency for this one command.
    #
    # See the end of "perldoc perlform" for an explanation of formline
    # and $^A;
    formline $format, q{ }, map { $_->display_name() => '|' } @roles;

    for my $perm (@perms) {
        my @marks;
        for my $role (@roles) {
            push @marks,
                $ws->permissions->role_can( role => $role, permission => $perm )
                ? 'X'
                : ' ';
        }

        formline $format, $perm->name(), map { $_ => '|' } @marks;
    }

    $msg .= $^A;
    $self->_success( $msg, "no indent" );
}

sub show_members {
    my $self = shift;

    my %opts = do {
        local $self->{argv} = $self->{argv};
        $self->_get_options("account:s", "workspace:s","group:s");
    };

    if ( exists $opts{account}) {
        return $self->_show_account_members();
    }
    elsif ( exists $opts{workspace}) {
        return $self->_show_workspace_members();
    }
    elsif ( exists $opts{group}) {
        return $self->_show_group_members();
    }

    $self->_error(
            "The command you called ($self->{command}) "
            . "requires a workspace, account, or group \n"
            . "to be specified.\n"
            . "A workspace is identified by name with the --workspace option.\n"
            . "An account is identified by name with the --account option.\n"
            . "A group is identified by group id with the --group option.\n"
    );
    return;
}

sub _show_account_members {
    my $self = shift;
    my %opts = $self->_get_options('direct');

    my $account = $self->_require_account();

    my $msg = "Members of the " . $account->name . " account\n\n";
    $msg .= "| Email Address | First | Last |\n";

    my $user_cursor =  $account->users(
        primary_only => ( $opts{direct} ) ? 1 : 0,
    );

    while (my $user = $user_cursor->next) {
        $msg .= '| ' . join(' | ', $user->email_address, $user->first_name, $user->last_name) . " |\n";
    }

    $self->_success($msg, "no indent");
}

sub _show_workspace_members {
    my $self = shift;
    my %opts = $self->_get_options('direct');

    my $ws = $self->_require_workspace();

    my $msg = "Members of the " . $ws->name . " workspace\n\n";
    $msg .= "| Email Address | First | Last | Role |\n";

    my $user_cursor = Socialtext::Workspace::Roles->UsersByWorkspaceId(
        workspace_id => $ws->workspace_id,
        direct => $opts{direct} ? 1 : 0,
    );
    while (my $user = $user_cursor->next) {
        my $role = $ws->role_for_user($user);
        $msg .= '| ' . join(' | ', $user->email_address, $user->first_name, $user->last_name, $role->name) . " |\n";
    }
    $self->_success($msg, "no indent");
}

sub _show_group_members {
    my $self  = shift;
    my $group = $self->_require_group();

    my $urs = $group->user_roles();
    my $msg = loc("cli.members-of=group", $group->driver_name) . "\n\n";
    $msg .= '| ' . join(' | ', loc("cli.email"), loc("cli.first-name"), loc("cli.last-name"), loc("cli.role")) . " |\n";

    while ( my $ur = $urs->next() ) {
        my ($user,$role) = @$ur;
        $msg .= '| '
            . join(' | ',
                $user->email_address,
                $user->first_name,
                $user->last_name,
                $role->name
            ) . " |\n";
    }

    $self->_success($msg);
}

sub show_admins {
    my $self = shift;

    my $ws = $self->_require_workspace();

    my $msg = "Admins of the " . $ws->name . " workspace\n\n";
    $msg .= "| Email Address | First | Last |\n";

    my $user_cursor = $self->_get_container_users_cursor($ws);
    my $entry;
    while ($entry = $user_cursor->next) {
        my ($user, $role) = @$entry;
        next if ($role->name ne 'admin');
        $msg .= '| ' . join(' | ', $user->email_address, $user->first_name, $user->last_name) . " |\n";
    }

    $self->_success($msg, "no indent");
}

sub show_account_admins {
    my $self = shift;

    my $acct = $self->_require_account();

    my $msg = "Admins of the " . $acct->name . " account\n\n";
    $msg .= "| Email Address | First | Last |\n";

    my $user_cursor = $self->_get_acct_users_cursor($acct);
    my $entry;
    while ($entry = $user_cursor->next) {
        my ($user, $role) = @$entry;
        next if ($role->name ne 'admin');
        $msg .= '| ' . join(' | ', $user->email_address, $user->first_name, $user->last_name) . " |\n";
    }

    $self->_success($msg, "no indent");
}

sub show_impersonators {
    my $self = shift;

    my $ws = $self->_require_workspace(undef, 'optional');
    my $acct = $self->_require_account('optional');
    unless ($ws or $acct) {
        $self->_error(
            loc("error.account-or-wiki-required=command", $self->{command}),
        );
    }

    my $thingy = $ws ? 'workspace' : 'account';
    my $msg = "Impersonators in the " . ($ws || $acct)->name . " $thingy\n\n";
    $msg .= "| Email Address | First | Last |\n";

    my $user_cursor = $self->_get_container_users_cursor($ws || $acct);
    my $entry;
    while ($entry = $user_cursor->next) {
        my ($user, $role) = @$entry;
        next if ($role->name ne 'impersonator');
        $msg .= '| ' . join(' | ', $user->email_address, $user->first_name, $user->last_name) . " |\n";
    }

    $self->_success($msg, "no indent");
}

sub _get_container_users_cursor {
    my $self      = shift;
    my $container = shift;
    my %opts      = $self->_get_options('direct');
    return $container->user_roles(%opts);
}

sub _get_acct_users_cursor {
    my $self = shift;
    my $acct = shift;
    my %opts = $self->_get_options('direct');
    return $acct->user_roles( %opts );
}

sub purge_page {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my $page = $self->_require_page($hub);

    my $title = $page->name;
    $page->purge();

    $self->_success( 
        loc('page.purged=title,wiki',
            $title, $hub->current_workspace()->name())
    );
}

sub lock_page {
    my $self = shift;
    $self->_toggle_page_lock( 1 );
}

sub unlock_page {
    my $self = shift;
    $self->_toggle_page_lock( 0 );
}

sub _toggle_page_lock {
    my $self = shift;
    my $status = shift;
    my ( $hub, $main ) = $self->_require_hub();
    my $page = $self->_require_page($hub);
    my $workspace = $hub->current_workspace;

    $self->_error(loc(
        "wiki.disabled-locking=title",
        $workspace->title()
    )) unless ( $workspace->allows_page_locking );

    $page->update_lock_status( $status );

    if ($status) {
        $self->_success(loc(
            "page.locked=name,wiki",
            $page->name, $workspace->title(),
        ));
    }
    else {
        $self->_success(loc(
            "page.unlocked=name,wiki",
            $page->name, $workspace->title(),
        ));
    }
}


sub can_lock_pages {
    my $self = shift;
    my ( $hub, $main ) = $self->_require_hub();
    my $user = $self->_require_user();

    $hub->current_user($user);
    my $can_lock = $hub->checker->check_permission('lock') && $hub->current_workspace->allows_page_locking;

    if ($can_lock) {
        $self->_success(loc(
            "wiki.enabled-locking=user",
            $user->username
        ));
    }
    else {
        $self->_success(loc(
            "wiki.disabled-locking=user",
            $user->username
        ));
    }
}

sub locked_pages {
    my $self         = shift;
    my ($hub, $main) = $self->_require_hub();
    my $ws           = $hub->current_workspace();
    my @page_ids     = $hub->pages->all_ids_locked();
    my $msg;

    if ( @page_ids > 0 ) {
        $msg = loc("page.list-locked=wiki:", $ws->title);
        for my $id ( @page_ids ) {
            $msg .= "\n* " . $hub->pages->new_from_name( $id )->title;
        }
    }
    else {
        $msg = loc("page.nothing-locked=wiki", $ws->title);
    }

    $self->_success("$msg\n\n");
}

sub purge_attachment {
    my $self = shift;
    my ( $hub, $main ) = $self->_require_hub();
    my $page = $self->_require_page($hub);
    my $attachment = $self->_require_page_attachment($page);

    my $title = $page->name;
    my $filename = $attachment->filename;
    $attachment->purge($page);

    $self->_success( "The $filename attachment was purged from "
                      . "$title page in the "
                      . $hub->current_workspace()->name() . " workspace.\n" );
}

sub purge_signal_attachment {
    my $self = shift;
    my ($signal, $attachment) = $self->_require_signal_attachment;

    my $filename = $attachment->filename;
    my $signal_id = $attachment->signal_id;
    $attachment->purge;

    $self->_success( "The $filename attachment was purged from "
                      . "signal $signal_id.\n");
}

sub _require_signal_attachment {
    my $self = shift;

    my %opts = $self->_get_options('signal:s', 'attachment:s');
    unless ($opts{signal} and $opts{attachment}) {
        $self->_error(
            "The command you called ($self->{command}) requires --signal and "
            . "--attachment arguments."
        );
    }

    require Socialtext::Signal;
    my $signal = eval { Socialtext::Signal->Get($opts{signal}) };
    if ($@ or !$signal) {
        $self->_error(
            "$self->{command} requires a valid signal id or hash. $opts{signal}"
            . " is not valid."
        );
    }

    require Socialtext::Signal::Attachment;
    my $attachment = Socialtext::Signal::Attachment->GetForSignalFilename(
        $signal, $opts{attachment}
    );
    unless ($attachment) {
        $self->_error(
            "$opts{attachment} is not a valid filename for an attachment of "
            . " signal $opts{signal}."
        );
    }
    return ($signal,$attachment);
}


sub html_archive {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my $file = Cwd::abs_path( $self->_require_string('file') );

    require Socialtext::HTMLArchive;
    $file = Socialtext::HTMLArchive->new( hub => $hub )->create_zip($file);

    $self->_success( 'An HTML archive of the '
            . $hub->current_workspace()->name()
            . " workspace has been created in $file.\n" );
}

sub export_workspace {
    my $self = shift;

    my $ws = $self->_require_workspace();
    my $file = $self->_export_workspace($ws);
    $self->_success(loc("wiki.exported=name,file",
            $ws->name, $file));
}

sub _export_workspace {
    my $self = shift;
    my $ws   = shift;

    my $name = lc( $self->_optional_string('name') || $ws->name );
    my $dir = $self->_export_dir_base;

    my $msg = '';
    eval { $msg = $ws->export_to_tarball( dir => $dir, name => $name ); };
    if ( my $e = $@ ) {
       $self->_error($e);
    }

    return $msg;
}

sub _export_dir_base {
    my $self = shift;
    my $dir = $self->{export_dir};
    $dir ||= $self->_optional_string('dir');
    $dir ||= $ENV{ST_EXPORT_DIR};
    $dir ||= File::Spec->tmpdir();
    return $dir;
}

sub import_workspace {
    my $self = shift;
    my %opts
        = $self->_get_options("tarball:s", "overwrite", "name:s", "noindex");
    $self->_error("--tarball required.")
        unless defined $opts{tarball};

    Socialtext::Workspace->ImportFromTarball(
        $opts{name} ? ( name => $opts{name} ) : (),
        tarball   => $opts{tarball},
        overwrite => $opts{overwrite},
        noindex   => $opts{noindex},
    );

    $self->_success('Workspace has been imported');
}

sub clone_workspace {
    my $self = shift;
    my $timer = Socialtext::Timer->new;
    my $ws        = $self->_require_workspace();
    my %opts      = $self->_get_options( "target:s", "overwrite" );

    $self->_error("--target required.") unless defined $opts{target};
    $opts{target} = lc $opts{target};

    my $dir = File::Temp::tempdir( CLEANUP => 1 );
    my $file = $ws->export_to_tarball( dir => $dir, name => $opts{target} );

    Socialtext::Workspace->ImportFromTarball(
        name      => $opts{target},
        tarball   => $file,
        overwrite => $opts{overwrite},
    );

    st_log()
        ->info( 'CLONE,WORKSPACE,old_workspace:'
                . $ws->name . '(' . $ws->workspace_id . '),'
                . 'new_workspace:' . $opts{target}
                . '(' . $ws->workspace_id . '),'
                . '[' . $timer->elapsed . ']');

    $self->_success( 'The '
            . $ws->name()
            . " workspace has been cloned to $opts{target}." );
}

sub delete_workspace {
    my $self = shift;

    my $ws = $self->_require_workspace();

    if ( $ws->is_all_users_workspace ) {
        $self->_error(loc("error.delete-auw-workspace", $ws->account->name));
    }

    my $skip_export = $self->_boolean_flag('no-export');

    my $file = $self->_export_workspace($ws)
        unless $skip_export;

    $ws->delete();

    my $name = $ws->name();
    my $msg = "The $name workspace has been ";
    $msg .= "exported to $file and " unless $skip_export;
    $msg .= 'deleted.';

    $self->_success($msg);
}

sub index_page {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my $page = $self->_require_page($hub);
    my $attachments_too = $self->_boolean_flag('attachments');

    my $ws_name = $hub->current_workspace()->name();

    require Socialtext::Search::AbstractFactory;
    my @indexers = Socialtext::Search::AbstractFactory->GetIndexers($ws_name);
    my $attachments = $attachments_too
                        ? $hub->attachments->all(page_id => $page->id) : [];
    for my $indexer (@indexers) {
        $indexer->index_page( $page->id() );
        foreach my $attachment (@$attachments) {
            $indexer->index_attachment($page->id, $attachment);
        }
    }

    $self->_success( 'The '
            . $page->name
            . " page in the $ws_name workspace has been indexed." );
}

sub index_attachment {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my $page       = $self->_require_page($hub);
    my $attachment = $self->_require_page_attachment($page);

    my $search_config = $self->_optional_string('search-config') || 'live';
    my $ws_name       = $hub->current_workspace()->name();

    require Socialtext::Search::AbstractFactory;
    my @indexers = Socialtext::Search::AbstractFactory->GetIndexers($ws_name);
    for my $indexer (@indexers) {
        $indexer->index_attachment( $page->id, $attachment->id );
        $indexer->index_page( $page->id );
    }

    $self->_success( 'The '
            . $attachment->filename()
            . " attachment in the $ws_name workspace has been indexed." );
}

sub index_workspace {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();

    my $search_config = $self->_optional_string('search-config') || 'live';
    if ( $self->_get_options("sync") ) {
        my $ws_name = $hub->current_workspace()->name();
        require Socialtext::Search::AbstractFactory;
        my @indexers = Socialtext::Search::AbstractFactory->GetIndexers($ws_name);
        for my $indexer (@indexers) {
            $indexer->index_workspace($ws_name);
        }
        $self->_success("The $ws_name workspace has been indexed.");
    }

    $hub->current_workspace->reindex_async($hub, $search_config);

    $self->_success( 'The '
            . $hub->current_workspace()->name()
            . ' workspace is being indexed.' );
}

sub delete_search_index {
    my $self = shift;

    my $ws = $self->_require_workspace();
    $ws->delete_search_index();

    $self->_success( 'The search index for the '
            . $ws->name()
            . ' workspace has been deleted.' );
}

sub index_people {
    my $self = shift;

    my $adapter = Socialtext::Pluggable::Adapter->new;
    unless ($adapter->plugin_exists('people')) {
        $self->_error(loc("error.no-people-plugin"));
    }

    Socialtext::JobCreator->insert('Socialtext::Job::Upgrade::ReindexPeople');
    $self->_success( "Scheduled people for re-indexing." );
}

sub index_groups {
    my $self = shift;

    my $adapter = Socialtext::Pluggable::Adapter->new;
    unless ($adapter->plugin_exists('groups')) {
        $self->_error(loc("error.no-people-plugin"));
    }
    Socialtext::JobCreator->insert('Socialtext::Job::Upgrade::ReindexGroups');
    $self->_success( "Scheduled groups for re-indexing." );
}

sub index_signals {
    my $self = shift;

    my $adapter = Socialtext::Pluggable::Adapter->new;
    unless ($adapter->plugin_exists('signals')) {
        $self->_error(loc("error.no-signals-plugin"));
    }
    Socialtext::JobCreator->insert('Socialtext::Job::Upgrade::ReindexSignals');
    $self->_success( "Scheduled signals for re-indexing." );
}

sub send_email_notifications {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();

    unless ( $hub->current_workspace()->email_notify_is_enabled() ) {
        $self->_error( 'Email notifications are disabled for the '
                . $hub->current_workspace()->name()
                . ' workspace.' );
    }

    my $page = $self->_require_page($hub);

    Socialtext::JobCreator->send_page_email_notifications($page);

#  $hub->email_notify()->maybe_send_notifications( $page->id() );

    $self->_success( 'Email notifications were sent for the '
            . $page->name
            . ' page.' );
}

sub send_watchlist_emails {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my $page = $self->_require_page($hub);

    Socialtext::JobCreator->send_page_watchlist_emails($page);
#    $hub->watchlist()->maybe_send_notifications( $page->id() );

    $self->_success( 'Watchlist emails were sent for the '
            . $page->name
            . ' page.' );
}

sub send_blog_pings {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();

    unless ( $hub->current_workspace()->ping_uris() ) {
        $self->_error( 'The '
                . $hub->current_workspace()->name()
                . ' workspace has no ping uris.' );
    }

    my $page = $self->_require_page($hub);

    require Socialtext::WeblogUpdates;
    Socialtext::WeblogUpdates->new( hub => $hub )->send_ping($page);

    $self->_success( 'Pings were sent for the '
            . $page->name
            . ' page.' );
}
*send_weblog_pings = \&send_blog_pings;

sub mass_copy_pages {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my $target_ws = $self->_require_target_workspace();
    my $prefix    = $self->_optional_string('prefix');
    $prefix ||= '';

    $hub->duplicate_page()
        ->mass_copy_to( $target_ws->name(), $prefix, $hub->current_user() );

    my $msg = 'All of the pages in the '
        . $hub->current_workspace()->name()
        . ' workspace have been copied to the '
        . $target_ws->name()
        . ' workspace';
    $msg .= qq|, prefixed with "$prefix"| if $prefix;
    $msg .= '.';

    $self->_success($msg);
}

sub add_users_from {
    my $self = shift;

    my $ws        = $self->_require_workspace();
    my $target_ws = $self->_require_target_workspace();
    my $acct      = $target_ws->account;
    my $users     = $ws->users();

    my (@added, @rejected);
    while ( my $user = $users->next() ) {
        next if $target_ws->has_user( $user );

        if ( ! $acct->email_passes_domain_filter($user->email_address) ) {
            push @rejected, $user->username;
            next;
        }

        if ( ! $target_ws->email_passes_invitation_filter($user->email_address) ) {
            push @rejected, $user->username;
            next;
        }

        $target_ws->add_user( user => $user );
        push @added, $user->username();
    }

    if ( @added || @rejected ) {
        my $msg;
        if (@added) {
            $msg .= 'The following users from the '
                . $ws->name()
                . ' workspace were added to the '
                . $target_ws->name()
                . " workspace:\n\n";

            $msg .= " - $_\n" for sort @added;
        }

        if (@rejected) {
            $msg .= 'The following users from the '
                . $ws->name()
                . ' workspace were rejected when adding to the '
                . $target_ws->name()
                . " workspace:\n\n";

            $msg .= " - $_\n" for sort @rejected;
        }

        $self->_success($msg);
    }
    else {
        $self->_success( 'There were no users in the '
                . $ws->name()
                . ' workspace not already in the '
                . $target_ws->name()
                . ' workspace.' );
    }
}

sub update_page {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();
    my $user  = $self->_require_user();
    my $title = $self->_require_string('page');

    $hub->current_user($user);

    my $content = do { local $/; <STDIN> };
    unless ( defined $content and length $content ) {
        $self->_error(
            'update-page requires that you provide page content on stdin.');
        return;
    }

    my $page = $hub->pages()->new_from_name($title);
    my $verb = $page->revision_num == 0 ? 'created' : 'updated';
    my $rev = $page->edit_rev();
    $rev->body_ref(\$content);
    $page->update();

    $self->_success(qq|The "$title" page has been $verb.|);
}

# This command is quiet since it's really only designed to be run by
# an MTA, and should be quiet on success.
sub deliver_email {
    my $self = shift;

    my $ws = $self->_require_workspace();

    require Socialtext::EmailReceiver::Factory;

    eval {
        my $locale = system_locale();
        my $email_receiver = Socialtext::EmailReceiver::Factory->create({
            locale => $locale,
            handle => \*STDIN,
            workspace => $ws
        });

        $email_receiver->receive();
    };

    if ( my $e = Exception::Class->caught('Socialtext::Exception::Auth') ) {
        die $e->error() . "\n";
    }
    elsif ( $e = $@ ) {
        die "$e\n";
    }
}

sub customjs {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();

    if ($hub->skin->customjs_name()) {
        $self->_success(
            'Custom JS URI for ' .
            $hub->current_workspace()->name .
            ' workspace is ' .
            $hub->skin->customjs_name() .
            '.'
        );
    }
    elsif ($hub->current_workspace()->customjs_uri()) {
        $self->_success(
            'Custom JS URI for ' .
            $hub->current_workspace()->name .
            ' workspace is ' .
            $hub->current_workspace()->customjs_uri() .
            '.'
        );
    } else {
        $self->_success(
            'The ' .
            $hub->current_workspace()->name .
            ' workspace has no custom Javascript set.'
        );
    }
}

sub clear_customjs {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();

    $hub->current_workspace()->update('customjs_uri', '');
    $hub->current_workspace()->update('customjs_name', '');
    $self->_success(
        'Custom JS URI cleared for ' .
        $hub->current_workspace()->name .
        ' workspace.'
    );
}

sub set_customjs {
    my $self = shift;

    my ( $hub, $main ) = $self->_require_hub();

    my %opts = $self->_get_options( 'uri:s', 'name:s' );

    $hub->current_workspace()->update('customjs_uri', '');
    $hub->current_workspace()->update('customjs_name', '');

    if ($opts{uri}) {
        $hub->current_workspace()->update('customjs_uri', $opts{uri});
        $self->_success(
            'Custom JS URI for ' .
            $hub->current_workspace()->name .
            ' workspace set to ' .
            $opts{uri} .
            '.'
        );
    }
    elsif ($opts{name}) {
        $hub->current_workspace()->update('customjs_name', $opts{name});
        $self->_success(
            'Custom JS name for ' .
            $hub->current_workspace()->name .
            ' workspace set to ' .
            $opts{name} .
            '.'
        );
    }
}

sub rebuild_pagelinks {
    my $self = shift;

    my %opts = $self->_get_options( 'workspace:s' );
    $self->_error('You must specify a workspace')
        if (!$opts{workspace});
    my $workspace = $self->_load_workspace($opts{workspace});

    Socialtext::JobCreator->insert(
        'Socialtext::Job::Upgrade::RebuildPageLinks',
        {
            workspace_id => $workspace->workspace_id,
        },
    );

    my $ws_name = $workspace->name;
    $self->_success("A job has been created to rebuild page links for the "
        . "$ws_name workspace.");
}

sub invite_user {
    my $self = shift;

    $self->{command} = 'invite_user';

    my %opts = $self->_get_options( 'workspace:s', 'email:s', 'from:s', 'secure' );

    if ($opts{secure}) {
        $Socialtext::URI::default_scheme = 'https';
    }

    $self->_error('You must specify a workspace')
        if (!$opts{workspace});
    my $workspace = $self->_load_workspace($opts{workspace});

    $self->_error('You must specify an invitee email address')
        if (!$opts{email});

    $self->_ensure_email_passes_filters(
        $opts{email},
        { account => $workspace->account, workspace => $workspace },
    );

    $self->_error('You must specify an inviter email address')
        if (!$opts{from});

    my $to_user = Socialtext::User->new( email_address => $opts{email});
    if ( $to_user && $workspace->has_user($to_user)) {
        $self->_error(
            qq|The email address you provided, "$opts{email}", is already a member of the "|
            . $opts{workspace} .'" workspace.'
        );
    }

    my $from_user = Socialtext::User->new(email_address => $opts{from});
    if (!$from_user || !$workspace->has_user($from_user)) {
        $self->_error(
            qq|The from email address you provided, "$opts{from}", is not a member of the workspace.|
        );
    }

    require Socialtext::WorkspaceInvitation;

    my $invitation = Socialtext::WorkspaceInvitation->new(
        workspace => $workspace,
        from_user => $from_user,
        invitee   => $opts{email},
        extra_text => '',
        viewer => undef
    );
    $invitation->send();

    $self->_success(
        'An invite has been sent to "' . $opts{email}
        . '" to join the "' . $workspace->title . '" workspace.'
    );
}

sub _require_field_options {
    my $self = shift;

    my $adapter = Socialtext::Pluggable::Adapter->new;
    unless ($adapter->plugin_exists('people')) {
        $self->_error(loc("error.no-people-plugin"));
    }

    my $acct = $self->_require_account('optional');
    $acct ||= Socialtext::Account->Default();

    my %opts = $self->_get_options(
        'name=s',
        'title=s',
        'field-class=s',
        'source=s',
        'hidden',
        'visible',
    );

    $self->_error(loc("error.not-both-visible-and-hidden"))
        if ($opts{hidden} && $opts{visible});

    if ($opts{hidden} || $opts{visible}) {
        $opts{is_hidden} = $opts{hidden} ? 1 : 0;
    }

    $opts{_plugin} = $adapter->plugin_class('people');
    $opts{field_class} = delete $opts{'field-class'};

    $opts{name} = lc Socialtext::String::trim($opts{name})
        if defined $opts{name};

    $opts{_account} = $acct;

    return %opts;
}

sub add_profile_field {
    my $self = shift;

    my %opts = $self->_require_field_options();
    my $plugin = delete $opts{_plugin};
    my $acct = delete $opts{_account};

    my $field;
    eval {
        $field = $plugin->AddProfileField({
            %opts,
            account => $acct,
        });
    };
    $self->_error($@) if $@;
    $self->_success(loc("profile.created-field=title,account",
                        $field->title, $acct->name));
}

sub set_profile_field {
    my $self = shift;

    my %opts = $self->_require_field_options();
    my $plugin = delete $opts{_plugin};
    my $acct = delete $opts{_account};

    my ($field, $old_title);
    eval {
        ($field, $old_title) = $plugin->SetProfileField({
            %opts,
            account => $acct,
        });
    };
    $self->_error($@) if $@;
    $self->_success(loc("profile.updated=field,account",
                        $old_title, $acct->name));
}

sub list_groups {
    my $self = shift;
    my %opts = $self->_get_options('account:s', 'workspace:s');

    my %param;
    if ($opts{account}) {
        my $account = $self->_load_account( $opts{account} );
        $param{account_id} = $account->account_id();
        $param{sort_order} = 'desc';
        $param{order_by}   = 'user_count';
    }
    if ($opts{workspace}) {
        my $workspace = $self->_load_workspace( $opts{workspace} );
        $param{workspace_id} = $workspace->workspace_id();
        $param{order_by}   = 'driver_group_name';
        $param{sort_order} = 'asc';
    }

    eval {
        my $groups = Socialtext::Group->All(
            include_aggregates => 1,
            %param,
        );
        die loc("error.no-groups") . "\n" if $groups->count == 0;
        print loc("cli.displaying-all-groups")."\n\n";
        printf '| %4s | %20s | %7s | %7s | %15s | %10s | %20s |' . "\n",
            loc("cli.group-id"), loc("cli.group-name"),
            loc("cli.group-wikis"), loc("cli.group-users"), loc("cli.group-primary-account"),
            loc("cli.created"), loc("cli.created-by");

        while (my $g = $groups->next) {
            printf '| %4d | %20s | %7d | %7d | %15s | %10s | %20s |' . "\n",
                $g->group_id, $g->driver_group_name,
                $g->workspace_count, $g->user_count, $g->primary_account->name,
                $g->creation_datetime->ymd, $g->creator->username;
        }
    };
    $self->_error($@) if $@;
    $self->_success();
}

sub create_group {
    my $self    = shift;
    my %opts    = $self->_get_options(
        'ldap-dn:s', 'name:s', 'email:s', 'permissions:s');

    $opts{account} = $self->_require_account('optional')
        || Socialtext::Account->Default();

    return $self->_create_ldap_group(%opts) if $opts{'ldap-dn'};

    my $name = $opts{name};
    unless ($name) {
        $self->_error(
            loc("error.group-name-or-ldap-dn-required")
        );
    }

    my $email = $opts{email};
    $self->_error( loc("error.group-email-required") )
        unless $email;

    my $user = Socialtext::User->new(email_address => $opts{email});
    $self->_error( loc("error.no-user=email", $email) )
        unless $user;

    my $account = $opts{account} || Socialtext::Account->Default;
    my $group = eval {
        Socialtext::Group->Create({
            driver_group_name => $name,
            primary_account_id => $account->account_id,
            created_by_user_id => $user->user_id,
            permission_set => $opts{permissions},
        });
    };
    if (my $err = $@) {
        if ($err =~ m/duplicate key value violates/) {
            $self->_error(
                loc("error.already-added=group",
                    $name,
                )
            );
        }
        elsif (blessed($err)) {
            $err = $err->as_string();
        }
        my ($msg) = ($err =~ m{(.+?)(?:^Trace begun)? at \S+ line .*}ims);
        $self->_error(loc("error.create-group=message", $msg));
    }
    $self->_success(
        loc("group.created=name,id",
            $group->driver_group_name,
            $group->group_id,
        )
    );
}

sub _create_ldap_group {
    my $self = shift;
    my %opts = @_;
    my $ldap_dn = $opts{'ldap-dn'};

    # Check to make sure LDAP Group Factories have been configured.
    unless (grep { /^LDAP:/ } Socialtext::Group->Drivers) {
        $self->_error(
            loc("error.no-ldap-group-factories")
        );
    }

    # Check if Group already exists
    my $proto = Socialtext::Group->GetProtoGroup(driver_unique_id => $ldap_dn);
    if ($proto) {
        $self->_error(
            loc("error.already-added=group",
                $proto->{driver_group_name},
            )
        );
    }

    # Vivify the Group, thus loading it into ST.
    my $group = Socialtext::Group->GetGroup(
        driver_unique_id   => $ldap_dn,
        primary_account_id => $opts{account}->account_id,
    );

    unless ( $group ) {
        $self->_error(
            loc("error.no-group=ldap-dn", $ldap_dn)
        );
    }

    $self->_success(
        loc("group.created=name,account",
            $group->driver_group_name,
            $opts{account}->name,
        )
    );
}

sub show_group_config {
    my $self  = shift;
    my $group = $self->_require_group();

    my %group = (
        'Group Name'           => $group->driver_group_name,
        'Group ID'             => $group->group_id,
        'Number Of Users'      => $group->user_count,
        'Primary Account ID'   => $group->primary_account_id,
        'Primary Account Name' => $group->primary_account->name,
        'Source'               => $group->driver_key
    );

    my $msg = loc("config.for=group:", $group->driver_group_name) . "\n\n";
    $msg .= join("\n",
        map { sprintf('%-21s: %s', $_, $group{$_}) } sort keys %group );

    $self->_success( $msg );
}

sub _require_group {
    my $self = shift;
    my %opts = $self->_get_options('group:s');

    $self->_error(
        loc("error.group-required=command",
            $self->{command}),
    ) unless exists $opts{group};

    return $self->{group} = $self->_load_group($opts{group});
}

sub _load_group {
    my $self     = shift;
    my $group_id = shift;

    my $group = Socialtext::Group->GetGroup( group_id => $group_id );

    $self->_error(
        loc("error.no-group=id", $group_id)
    ) unless $group;

    return $group;
}

# Called by Socialtext::Ceqlotron
sub from_input {
    my $self  = shift;
    my $class = ref $self;

    local $Socialtext::User::Cache::Enabled = 1;

    my %opts = $self->_get_options( 'from-fixture' );

    {
        no warnings 'redefine';
        *_exit          = sub { };
        *_help_as_error = sub { die $_[1] };
    }

    my $errors;
    while ( my $input = <STDIN> ) {
        chomp $input;

        eval {
            my @argv = split( chr(0), $input );
            $class->new( argv => \@argv )->run();
        };
        my $err = $@;
        $errors .= $err if $err;

        eval { Socialtext::User::Cache->Clear() };

        if ($opts{'from-fixture'}) {
            print "Errors: $err" if $err;
            print "Completed $input\n";
        }
    }

    die $errors if $errors;
}

sub version {
    my $self = shift;

    require Socialtext;

    $self->_success( Socialtext->version_paragraph() );
}

sub _require_user {
    my $self = shift;

    return $self->{user} if exists $self->{user};

    my %opts = $self->_get_options( 'username:s', 'email:s' );

    unless ( grep { defined and length } @opts{ 'username', 'email' } ) {
        $self->_error(
            "The command you called ($self->{command}) requires a user to be specified.\n"
                . "A user can be identified by username (--username) or email address (--email).\n"
        );
    }

    my $user;
    if ( $opts{username} ) {
        $user = Socialtext::User->new( username => $opts{username} )
            or $self->_error(
            qq|No user with the username "$opts{username}" could be found.|);
    }
    elsif ( $opts{email} ) {
        $user = Socialtext::User->new( email_address => $opts{email} )
            or $self->_error(
            qq|No user with the email address "$opts{email}" could be found.|
            );
    }

    return $self->{user} = $user;
}

sub _require_workspace {
    my $self = shift;
    my $key  = shift || 'workspace';
    my $optional = shift;

    my %opts = $self->_get_options("$key:s");

    return if $optional and !$opts{$key};
    unless ( $opts{$key} ) {
        $self->_error(
            "The command you called ($self->{command}) requires a workspace to be specified.\n"
                . "A workspace is identified by name with the --$key option.\n"
        );
        return;
    }

    my $ws = Socialtext::Workspace->new( name => $opts{$key} );

    unless ($ws) {
        $self->_error(qq|No workspace named "$opts{$key}" could be found.|);
    }

    return $ws;
}

sub _require_target_workspace {
    my $self = shift;

    return $self->_require_workspace('target');
}

sub _require_hub {
    my $self = shift;

    my $user = shift || Socialtext::User->SystemUser();
    my $ws = shift || $self->_require_workspace();
    return $self->_make_hub($ws, $user);
}

sub _make_hub {
    my $self = shift;
    my $ws = shift;
    my $user = shift;

    require Socialtext;
    my $main = Socialtext->new();
    $main->load_hub(
        current_workspace => $ws,
        current_user      => $user,
    );
    $main->hub()->registry()->load();

    return ( $main->hub(), $main );
}

sub _require_tags {
    my $self = shift;
    my $hub  = shift;

    my %opts = $self->_get_options( 'tag:s', 'category:s', 'search:s' );
    $opts{tag} ||= $opts{category};

    unless ( grep { defined and length } @opts{ 'tag', 'search' } ) {
        $self->_error(
            "The command you called ($self->{command}) requires one or more tags to be specified.\n"
                . "You can specify a tag by name (--tag) or by a search string (--search)."
        );
    }

    if ( $opts{tag} ) {
        unless ( $hub->category->exists( $opts{tag} ) ) {
            $self->_error(
                loc('error.no-tag=tag,wiki',
                    $opts{tag}, $hub->current_workspace()->name())
            );
        }

        return $opts{tag};
    }
    else {
        my @matches = $hub->category->match_categories( $opts{search} );

        unless (@matches) {
            $self->_error(
                loc('error.no-tag=query,wiki',
                    $opts{search}, $hub->current_workspace()->name())
            );
        }

        return @matches;
    }
}

sub _require_page {
    my $self = shift;
    my $hub  = shift;

    my %opts = $self->_get_options('page:s');

    unless ( $opts{page} ) {
        $self->_error(
            "The command you called ($self->{command}) requires a page to be specified.\n"
                . "You can specify a page by id with the --page option." );
    }

    my $page = $hub->pages()->new_page( $opts{page} );
    unless ( $page and $page->exists() ) {
        $self->_error( 
            loc('error.no-page=id,wiki',
                $opts{page}, $hub->current_workspace()->name())
        );
    }

    return $page;
}

sub _require_page_attachment {
    my $self = shift;
    my $page = shift;

    my %opts = $self->_get_options('attachment:s');

    unless ($opts{attachment}) {
        $self->_error(
            "The command you called ($self->{command}) ".
            "requires an attachment id to be specified.\n".
            "You can specify an attachment with the --attachment option."
        );
    }

    return try { 
        $page->hub->attachments->load(
            page_id => $page->id,
            id => $opts{attachment}
        );
    }
    catch {
        my $ws = $page->hub->current_workspace->name;
        $self->_error(qq(There is no attachment with the id ).
            qq("$opts{attachment}" in the $ws workspace.\n"));
    };
}

sub _require_permission {
    require Socialtext::Permission;

    my $self = shift;

    my %opts = $self->_get_options('permission:s');

    unless ( $opts{permission} ) {
        $self->_error(
            "The command you called ($self->{command}) requires a permission to be specified.\n"
                . "A permission is identified by name with the --permission option.\n"
        );
        return;
    }

    my $perm = Socialtext::Permission->new( name => $opts{permission} );

    unless ($perm) {
        $self->_error(qq|There is no permission named "$opts{permission}".|);
    }

    return $perm;
}

sub _require_role {
    require Socialtext::Role;

    my $self = shift;

    my %opts = $self->_get_options('role:s');

    unless ( $opts{role} ) {
        $self->_error(
            "The command you called ($self->{command}) requires a role to be specified.\n"
                . "A role is identified by name with the --role option.\n" );
        return;
    }

    my $role = Socialtext::Role->new( name => $opts{role} );

    unless ($role) {
        $self->_error(qq|There is no role named "$opts{role}".|);
    }

    return $role;
}

sub _require_string {
    my $self = shift;
    my $name = shift;
    my $desc = shift || $name;

    my %opts = $self->_get_options("$name:s");

    unless ( defined $opts{$name} and length $opts{$name} ) {
        $self->_error(
            "The command you called ($self->{command}) requires a $desc to be specified with the --$name option.\n");
    }

    return $opts{$name};
}

sub _optional_string {
    my $self = shift;
    my $name = shift;

    my %opts = $self->_get_options("$name:s");

    return $opts{$name};
}

sub _boolean_flag {
    my $self = shift;
    my $name = shift;

    my %opts = $self->_get_options("$name");

    return $opts{$name};
}

sub _get_options {
    my $self = shift;

    local @ARGV = @{ $self->{argv} };

    my %opts;
    GetOptions( \%opts, @_ ) or exit 1;

    $self->{argv} = [@ARGV];

    if (exists $opts{password}) {
        # if args contained a password, we need to sanitize before logging
        $self->{_args_contained_password}=1;
    }

    return %opts;
}

sub _success {
    my $self = shift;
    my $msg  = _clean_msg( shift, shift );

    print $msg
        if defined $msg
        and not $self->{ceqlotron};

    my $data = {
        # This *NEEDS* to be the original ARGV, not $self->{argv}, so we can
        # show the full set of args we were given; $self->{argv} is not
        # guaranteed to be preserved.
        #
        # It also needs to be sanitized, so that we don't accidentally log a
        # password provided on the CLI to nlw.log
        args => join(' ', $self->_sanitize_args(@ARGV)),
    };
    st_timed_log(
        'info', 'CLI', $self->{command},
        Socialtext::User->SystemUser(),
        $data,
        Socialtext::Timer->Report()
    );

    _exit(0);
}

sub _error {
    my $self = shift;
    my $msg  = _clean_msg(shift);

    print STDERR $msg
        if defined $msg
        and not $self->{ceqlotron};

    _exit( $self->{ceqlotron} ? 0 : 1 );
}

sub _sanitize_args {
    my $self = shift;
    my @argv = @_;

    if ($self->{_args_contained_password}) {
        my $found_pw = 0;
        @argv = map {
            s/./x/g if ($found_pw);         # blank out password
            $found_pw = ($_ =~ /^--?p/);    # does next field contain password?
            $_;                             # return (possibly mangled) arg
        } @argv;
    }

    return @argv;
}

# This exists so it can be overridden by tests and from_input.
sub _exit { exit shift; }

sub _clean_msg {
    my $msg       = shift;
    my $no_indent = shift || 0;

    return unless defined $msg;

    # adds NL at beginning and two at the end
    $msg =~ s/^\n*/\n/;
    $msg =~ s/\n*$/\n\n/;

    # Indent every non-empty line by one space
    $msg =~ s/^(.*\S.*)/ $1/gm unless $no_indent;

    # Now make sure it's a proper Unicode string before we print it out.
    unless (Encode::is_utf8($msg)) {
        $msg = Encode::decode_utf8($msg);
    }

    return $msg;
}

1;

__END__

=head1 NAME

Socialtext::CLI - Provides the implementation for the st-admin CLI script

=head1 USAGE

  st-admin <command> <options> [--ceqlotron]

=head1 SYNOPSIS

  USERS

  create-user [--account] --email [--username] --password [--first-name --middle-name --last-name --external-id]
  invite-user --email --workspace --from [--secure]
  confirm-user --email --password
  deactivate-user [--username or --email]
  change-password [--username or --email] --password
  add-member [--username or --email] --workspace
  add-member [--username or --email] --account
  remove-member [--username or --email] --workspace
  remove-member [--username or --email] --account
  add-workspace-admin [--username or --email] --workspace
  remove-workspace-admin [--username or --email] --workspace
  add-workspace-impersonator [--username or --email] --workspace
  remove-workspace-impersonator [--username or --email] --workspace
  add-account-admin [--username or --email] --account
  remove-account-admin [--username or --email] --account
  add-account-impersonator [--username or --email] --account
  remove-account-impersonator [--username or --email] --account
  add-group-admin [--username or --email] --group
  remove-group-admin [--username or --email] --group
  disable-email-notify [--username or --email] --workspace
  set-locale [--username or --email] --workspace --locale
  set-user-names [--username or --email] --first-name --middle-name --last-name
  set-user-account [--username or --email] --account
  get-user-account [--username or --email]
  set-external-id [--username or --email] --external-id
  set-user-profile [--username or --email] KEY VALUE
  show-profile [--username or --email]
  hide-profile [--username or --email]
  can-lock-pages [--username or --email] --workspace
  locked-pages --workspace
  mass-add-users --csv --account --restriction
  list-restrictions [--username or --email]
  add-restriction [--username or --email] --restriction
  remove-restriction [--username or --email] --restriction

  WORKSPACES

  set-permissions --workspace --permissions
    [public | member-only | authenticated-user-only | public-read-only
    | public-comment-only | public-join-to-edit | self-join | intranet]

  add-permission --workspace --role --permission
  remove-permission --workspace --role --permission
  show-acls --workspace
  show-members --workspace [--direct]
  show-admins --workspace
  show-impersonators [--workspace or --account]
  set-workspace-config --workspace <key> <value>
  show-workspace-config --workspace
  create-workspace --name --title --account [--empty] [--all-users-workspace] [--clone-pages-from]
  delete-workspace --workspace [--dir] [--no-export]
  export-workspace --workspace [--dir] [--name]
  import-workspace --tarball [--overwrite] [--name] [--noindex]
  clone-workspace --workspace --target [--overwrite]
  rename-workspace --workspace --name
  list-workspaces [--ids]
  html-archive --workspace --file
  mass-copy-pages --workspace --target [--prefix]
  lock-page --workspace --page
  unlock-page --workspace --page
  purge-page --workspace --page
  purge-attachment --workspace --page --attachment
  purge-signal-attachment --signal --attachment
  search-tags --workspace --search
  delete-tag --workspace [--tag or --search]
  add-users-from --workspace --target
  customjs --workspace
  set-customjs --workspace [--uri or --name]
  clear-customjs --workspace
  rebuild-pagelinks --workspace

  INDEXING

  index-workspace --workspace [--sync] [--search-config]
  delete-search-index --workspace
  index-page --workspace --page [--attachments]
  index-attachment --workspace --page --attachment [--search-config]

  ACCOUNTS

  create-account --name [--type]
  list-accounts [--ids]
  show-members --account [--direct]
  give-accounts-admin [--username or --email]
  remove-accounts-admin [--username or --email]
  give-system-admin [--username or --email]
  remove-system-admin [--username or --email]
  set-default-account [--account]
  get-default-account
  export-account --account [--force] 
  import-account --directory [--name] [--noindex]
  set-account-config --account <key> <value>
  show-account-config --account
  reset-account-skin --account <account> --skin <skin>

  PLUGINS

  list-plugins
  enable-plugin  [--account | --all-accounts | --workspace]
                 --plugin <name>
  disable-plugin [--account | --all-accounts | --workspace]
                 --plugin <name>
  set-plugin-pref    --plugin <name> [ --account <name> ] KEY VALUE
  show-plugin-prefs  --plugin <name> [ --account <name> ]
  clear-plugin-prefs --plugin <name> [ --account <name> ]

  EMAIL

  send-email-notifications --workspace --page
  send-watchlist-emails --workspace --page
  deliver-email --workspace

  SEARCH

  index-people
  index-groups
  index-signals

  PROFILE (only available with Socialtext People)

  add-profile-field --name [--account] [--title --field-class --source]
                    [--hidden | --visible]
  set-profile-field --name [--account] [--title --field-class --source]
                    [--hidden | --visible]

  GROUPS

  list-groups [--account or --workspace]
  show-group-config --group
  create-group (--ldap-dn or --name) [--account] [--email] [--permissions]
  show-members --group 
  add-member --group [ --account or --workspace ]
  add-member [ --username or --email ] --group 
  add-workspace-admin --group  --workspace
  remove-workspace-admin --group --workspace
  add-workspace-impersonator --group --workspace
  remove-workspace-impersonator --group --workspace
  add-account-impersonator --group  --account
  remove-account-impersonator --group --account
  add-group-admin --group [ --username or --email ]
  remove-group-admin --group [ --username or --email ]
  remove-member --group [--account or --workspace]
  remove-member [ --username or --email ] --group
  delete-group --group
  set-permissions --group --permissions [self-join | private]

  OTHER

  set-logo-from-file --workspace --file /path/to/file.jpg
  set-comment-form-custom-fields --workspace <field> <field>
  set-ping-uris --workspace <uri> <uri>
  send-blog-pings --workspace --page
  update-page --workspace --page [--username or --email] < page-body.txt
  from-input < <list of commands>
  version
  help

=head1 COMMANDS

The following commands are provided:

=head2 create-user [--account] --email [--username] --password [--first-name --middle-name --last-name --external-id]

Creates a new user, optionally in a specified account. An email address and
password are required. If no username is specified, then the email address
will also be used as the username.

=head2 invite-user --email --workspace --from [--secure]

Invite a user to join a workspace. Along with the user's email address, an email
address for the person sending the invitation and the workspace to join are
also required. If the --secure option is specified, the link in the email is a
secure (https) link.

=head2 confirm-user --email --password

Confirms a new user and assigns the listed password to that user.  Requires
an email address and a password.

=head2 deactivate-user [--username or --email]

Remove a user from all their workspaces. If the user is a business or
technical admin, revoke those privileges. This is useful for when a
a user departs the system for some reason.

=head2 change-password [--username or --email] --password

Change the given user's password.

=head2 add-member [--username or --email] --workspace

Given a user and a workspace, this command adds the specified user to
the given workspace.

=head2 add-member [--username or --email] --account

Given a user and an account, this command adds the specified user to
the given account.

=head2 remove-member [--username or --email] --workspace

Given a user and a workspace, this command removes the specified user
from the given workspace.

=head2 remove-member [--username or --email] --account

Given a user and an account, this command removes the specified user
from the given account.

=head2 add-workspace-admin [--username or --email] --workspace

Given a user and a workspace, this command makes the specified user an
admin for the given workspace.

=head2 remove-workspace-admin [--username or --email] --workspace

Given a user and a workspace, this command remove admin privileges for
the specified user in the given workspace, and makes them a normal
workspace member.

=head2 add-workspace-impersonator [--username or --email] --workspace

Given a user and a workspace, this command makes the specified user an
impersonator for the given workspace.

=head2 remove-workspace-impersonator [--username or --email] --workspace

Given a user and a workspace, this command remove impersonate privileges for
the specified user in the given workspace, and makes them a normal workspace
member.

=head2 add-account-admin [--username or --email] --account

Given a user and an account, this command makes the specified user an
admin for the given account.

=head2 remove-account-admin [--username or --email] --account

Given a user and a account, this command remove admin privileges for
the specified user in the given account, and makes them a normal
account member.

=head2 add-account-impersonator [--username or --email] --account

Given a user and an Account, this command makes the specified user an
impersonator for the given Account.

=head2 remove-account-impersonator [--username or --email] --account

Given a user and an Account, this command remove impersonate privileges for
the specified user in the given Account, and makes them a normal Account
member.

=head2 add-group-admin [--username or --email] --group

Given a user and a group, this command makes the specified user an
admin for the given group.

=head2 remove-group-admin [--username or --email] --group

Given a user and a group, this command remove admin privileges for
the specified user in the given group, and makes them a normal
group member.

=head2 disable-email-notify [--username or --email] --workspace

Turns off email notifications from the specified workspace for the
given user.

=head2 set-locale --username --workspace --locale

Sets the language locale for user on a workspace.  Locale codes are 2 letter
codes.  Eg: en, fr, ja, de

=head2 set-user-names [--email or --username] --first-name --middle-name --last-name

Set the first, middle, and last names for an existing user.

=head2 set-user-account [--email or --username] --account

Set the primary account of the specified user.

=head2 get-user-account [--email or --username]

Print the primary account of the specified user.

=head2 set-external-id [--email or --username] --external-id

Set the external ID for a user.

=head2 set-user-profile [--email or --username] KEY VALUE

Sets the People Profile field to the given value, for the specified User.

The KEY provided must be the underlying name for the Profile Field, not its
visible/display representation.

=head2 show-profile [--email or --username]

=head2 hide-profile [--email or --username]

Show or hide the user's profile in the people system.

=head2 can-lock-pages [--email or --username] --workspace

Show whether a user can lock pages in the workspace.

=head2 locked-pages --workspace

List the locked pages for a given workspace.

=head2 mass-add-users --csv --account --restriction

Bulk adds/updates users from the given CSV file.

Each row within the CSV file represents a single user.  A username and email
address are required for each user, all other fields are optional.

If a user with a matching username exists already, the information for that
user is updated to match the information provided in the CSV file.  Otherwise,
a new user record is created.  If no password is provided for newly created
users, they are sent an e-mail message which includes a link that they may use
to set their password.

When adding users, if no account is specified, the users will be added to the
default account.

When updating users, if no account is specified, the user will be left in the
account that they are currently assigned to.  If an account is provided when
updating users, the users will be (re-)assigned to that account.

If the C<--restriction> option is provided, one or more restrictions can be
applied to Users en-masse (either during the creation of new Users, or the
update of existing ones).  To set multiple restrictions, use the
C<--restriction> option multiple times.  For more information on available
restrictions, see L</add-restriction>.

=head2 list-restrictions [--username or --email]

Lists the restrictions that are in place against a User record.  Each of the
listed restrictions will prevent the User from being able to log in until the
restriction has been removed/lifted.

=head2 add-restriction [--username or --email] --restriction

Adds a restriction to a User record.  Once restricted, the User will B<not> be
able to log in to the system until the restriction has been lifted.

To add multiple restrictions, use the C<--restriction> option multiple times.

Available restrictions include:

=over

=item email_confirmation

Requires that the User re-confirm their e-mail address.

=item password_change

Requires that the User to change their password.

=back

=head2 remove-restriction [--username or --email] --restriction

Removes a restriction from a User record, by confirming it and sending any
notifications necessary.

Can accept multiple C<--restriction> options, when specifying multiple
restrictions that are to be removed for the User.  Alternatively, you may
specify C<--restriction all> to remove I<all> of the restrictions that are
placed on the User's account.

Refer to C<add-restriction> for a list of acceptable restrictions.

=head2 set-permissions --workspace --permissions

Sets the permission for the specified workspace to the given named
permission set. Valid set names are:

=over 8

=item * public

=item * member-only

=item * authenticated-user-only

=item * public-read-only

=item * public-comment-only

=item * self-join

=item * public-join-to-edit

=item * intranet

=back

See the C<Socialtext::Workspace> documentation for more details on
permission sets.

=head2 add-permission --workspace --role -permission

Grants the specified permission to the given role in the named
workspace.

=head2 remove-permission --workspace --role -permission

Revokes the specified permission from the given role in the named
workspace.

=head2 show-acls --workspace

Prints a table of the workspace's role/permissions matrix to standard
output.

=head2 show-members [--workspace or --account] [--direct]

Prints a table of the workspace/account's members to standard output.

You may also pass --direct, which will cause show-members to only display
members who are directly associated with the workspace or account, eg _not_
through a group membership.

=head2 show-admins --workspace

Prints a table of the workspace's admins to standard output.

=head2 show-impersonators --workspace

Prints a table of the workspace's impersonators to standard output.

=head2 set-workspace-config --workspace <key> <value>

Given a valid workspace configuration key, this sets the value of the
key for the specified workspace. Use "-null-" as the value to set the
value to NULL in the DBMS. You can pass multiple key value pairs on
the command line.

If you are setting allows_locked_pages to false, this command will
forcibly unlock any pages.

=head2 show-workspace-config --workspace

Prints all of the specified workspace's configuration values to
standard output.

=head2 search-tags --workspace --search

Lists all tags matching the specified string.

=head2 delete-tag --workspace [--tag or --search]

Deletes the specified tags from the given workspace. You can
specify a single tag by name with C<--tag> or all tags
matching a string with C<--search>.

=head2 create-workspace --name --title --account [--empty] [--all-users-workspace] [--clone-pages-from]

Creates a new workspace with the given settings.  The usual account is
Socialtext. Accounts are used for billing.  If --empty is given then no pages
are inserted into the workspace, it is completely empty. If --all-users-workspace
is given then the workspace is an "all-users" workspace.

=head2 delete-workspace --workspace [--dir] [--no-export]

Deletes the specified workspace. Before the workspace is deleted, it
will first be exported to a tarball. To skip this step pass the
"--no-export" flag. See the L<export-workspace> command documentation
for details on where the exported tarball is created.

=head2 export-workspace --workspace [--dir] [--name]

Exports the specified workspace as a tarball suitable for importing
via the import-workspace command. If no directory is provided, it
checks for an env var named C<ST_EXPORT_DIR>, and finally defaults to
saving the tarball in the directory returned by C<<
File::Spec->tmpdir() >>.

If --name is given then the workspace is renamed on export.

=head2 import-workspace --tarball [--overwrite] [--name]

Imports the workspace from a tarball generated by workspace delete or
workspace export.

Overwrite an existing workspace if --overwrite is given.

If --name is passed in, use its value as the name for the new workspace.

=head2 clone-workspace --workspace --target [--overwrite]

Clone --workspace into --target.  The target workspace should not exist.  If
you wish to overwrite an existing target workspace then add the --overwrite
option.

This command is implemented as an export-workspace followed by an
import-workspace.  During the course of operations this command will
temporarily use 3 times the disk space required to store the original
workspace: the orignal copy, the exported tarball (deleted when finished), and
the new copy.

=head2 rename-workspace --workspace --name

Renames the specified workspace with the given name.

=head2 list-workspaces [--ids]

Provides a newline separated list of all the workspace names in the
system. If you pass "--ids", it lists workspace ids instead.

=head2 clear-customjs --workspace

Remove the custom Javascript for a workspace.

=head2 set-customjs --workspace [--uri or --name]

Set the URI or name for the custom Javascript for a workspace.

=head2 customjs --workspace

Show the URI or name for the custom Javascript assigned to a workspace.

=head2 rebuild-pagelinks --workspace

Re-create the backlinks for the specified workspace.

=head2 html-archive --workspace --file

Creates an archive of HTML pages containing the pages and attachments
to the specified file. The filename given must end in ".zip".

=head2 add-users-from --workspace --target

Adds all in the users who are a member of one workspace to the target
workspace I<as workspace members>. If a user is already a member of
the target workspace they are skipped.

=head2 mass-copy-pages --workspace --target [--prefix]

This command copies I<every> page in the specified workspace to the
target workspace. If a prefix is provided, this is prepended to the
page names in the target workspace.

=head2 lock-page --workspace --page

Lock the specified page in the given workspace. Only a workspace
admin can edit a locked a page. The page must be specified by 
its I<page id>, which is the name used in URIs.

=head2 unlock-page --workspace --page

Unlock the specified page in the given workspace. The page must 
be specified by its I<page id>, which is the name used in URIs.

=head2 purge-page --workspace --page

Purges the specified page from the given workspace. The page must be
specified by its I<page id>, which is the name used in URIs.

=head2 purge-attachment --workspace --page --attachment

Purges the specified attachment from the given page and workspace. The
attachment must be specified by its I<attachment id>, which is the
name used in URIs.

=head2 purge-signal-attachment --signal --attachment

Purges the specified attachment from the given signal. The attachment
must be specified by its I<filename>.  The signal can be specified by
its I<signal_id> or I<signal hash>.

=head2 index-workspace --workspace [--sync] [--search-config]

(Re-)indexes all the pages and attachments in the specified workspace.
If --sync is given the indexing is done syncronously, otherwise change
events are created and indexing is done asyncronously. If
--search-config is given, use an alternate configuration (from
live.yaml) to specify indexing parameters.

=head2 delete-search-index --workspace

Deletes the search index for the specified workspace.

=head2 index-page --workspace --page [--attachments]

(Re-)indexes the specified page in the given workspace.

If --attachments is specified, that page's attachments will
also be re-indexed.

=head2 index-attachment --workspace --page --attachment [--search-config]

(Re-)indexes the specified attachment in the given workspace. The
attachment must be specified by its id and its page's id.

=head2 index-people

(Re-)indexes all active people.

=head2 set-logo-from-file --workspace --file /path/to/file.jpg

Given a path to an image file, makes that file the specified
workspace's logo.

=head2 set-comment-form-custom-fields --workspace <field> <field>

This sets the workspace's comment form custom fields to the given
field names, replacing any that already exist. If called without any
field names, it will simply remove all existing custom fields.

=head2 set-ping-uris --workspace <uri> <uri>

Given a set of URIs, this sets the workspace's ping URIs to the given
URIs, replacing any that already exist. If called without any URIs, it
will simply remove all the existing ping URIs.

=head2 send-blog-pings --workspace --page

Given a page, this command send blog pings for that page. It pings
the URIs defined for the workspace. If the workspace has no ping URIs,
it does nothing.

=head2 send_email_notifications --workspace --page

Sends and pending emali notifications for the specified page.

=head2 send_watchlist_emails --workspace --page

Sends any pending watchlist change notifications for the specified
page.

=head2 update-page --workspace --page --username < page-body.txt

Update (or create) a page with the given title in the specified
workspace. The user argument sets the author of the page.

=head2 deliver-email --workspace

Deliver an email to the specified workspace. The email message should
be provided on STDIN.

=head2 list-accounts [--ids]

List accounts on this machine.  Alternatively, give the account IDs instead of
the names.

=head2 create-account --name

Creates a new account with the given name.

=head2 give-accounts-admin [--username or --email]

Gives the specified user accounts admin privileges.

=head2 remove-accounts-admin [--username or --email]

Remove the specified user's accounts admin privileges.

=head2 give-system-admin [--username or --email]

Gives the specified user system admin privileges.

=head2 remove-system-admin [--username or --email]

Remove the specified user's system admin privileges.

=head2 set-default-account --account

Set the default account new users should belong to.

=head2 get-default-account

Prints out the current default account.

=head2 export-account [--force]

Exports the specified account to /tmp. --force to overwrite an existing export.

=head2 import-account --directory [--name] [--noindex]

Imports an account from the specified directory.

=head2 from-input < <list of commands>

Reads a list of commands from STDIN and executes them. Each line must
contain a list of arguments separated by a null character (\0). The
first argument should be the command to be run.

=head2 set-account-config --account <key> <value>

Given a valid account configuration key, this sets the value of the
key for the specified account. Use "-null-" as the value to set the
value to NULL in the DBMS. You can pass multiple key value pairs on
the command line.

=head2 show-account-config --account

Given a valid account, this shows all key/value pair combinations for
that account.

=head2 reset-account-skin --account --skin <skin>

Set the skin for the specified account and its workspaces.

=head2 list-plugins

List all installed plugins.

=head2 enable-plugin --plugin [--account | --all-accounts | --workspace ]

Enable a plugin for the specified account (perhaps all) or workspace.

Enabling for all accounts will also enable the plugin for accounts created in the future.

You may pass in multiple `--plugin` params if you wish to enable multiple
plugins. Additionally, you may pass in `all` as a value to `--plugin` and
enable all plugins for the account(s) or workspace(s) specified.

=head2 disable-plugin --plugin [--account | --all-accounts | --workspace ]

Disable a plugin for the specified account (perhaps all) or workspace.

Disabling for all accounts will also disable the plugin for accounts created in the future.

You may pass in multiple `--plugin` params if you'd like to disable multiple
plugins. Additionally, you may pass in `all` as a value to `--plugin` and
disable all plugins for the account(s) or workspace(s) specified.

=head2 set-plugin-pref --plugin PluginName KEY VALUE

Sets a server-wide preference for the specified plugin.

You may pass in multiple `--plugin` params if you'd like to set the same pref
for multiple plugins. If you pass in `all` as a param, you will set a pref for
all plugins.

=head2 show-plugin-prefs --plugin PluginName

Shows all preferences set for the specified plugin.

=head2 clear-plugin-prefs --plugin PluginName

Clears all preferences set for the specified plugin.

If you wish, you may pass in multiple `--plugin` params if you wish to clear
the params for multiple plugins. Additionally, you may pass in `all` as a
param, you can clear the prefs for all your plugins.

=head2 add-profile-field --name [--account] [--title] [--field-class] [--source] [--visible | --hidden]

Set up a profile field for use under the specified account.  If the account name is not specified, the system default account is used.

If C<--field-class> is omitted, a regular text attribute will be created.  Valid classes include: attribute, contact, relationship (reference to another person).

If C<--source> is omitted, it defaults to "user".  Fields marked "external" cannot be changed by the user and will be set by some external data source (for example, an LDAP directory).

If C<--hidden> and C<--visible> are omitted, C<--visible> is the default.  Using C<--hidden> will hide this field from the UI for end-users.  ReST API queries will still include hidden fields and values.

=head2 set-profile-field --name [--account] [--title] [--field-class] [--source] [--visible | --hidden]

Changes an exiting profile field identified by name to have new properties.  Options that are omitted preserve the existing value of that property.  See add-profile-field above for more details.

Note: A field's class cannot currently be changed to or from the 'relationship' class.

=head2 list-groups [--account or --workspace]

Display an overview of Groups (in Socialtext wiki table format).  Includes the number of Workspaces each group belongs to.  Includes the number of Users that are members of each Group.

If C<--account> is specified, limits the display to groups in association with that account.

If C<--workspace> is specified, limits the display to groups in association
with that workspace.

=head2 show-group-config --group

Show the Group configuration for the specified C<--group> (which must be
provided as a Group Id).

=head2 create-group (--ldap-dn or --name) [--account] [--email] [--permissions]

Creates a new Socialtext Group.  If C<--name> is provided, a regular 
group will be created.  If C<--ldap-dn> is provided, the group will
be loaded from LDAP.

Loads a Group from LDAP, as identified by the given C<--ldap-dn> into
Socialtext, placing it in the specified C<--account>.  

If no C<--account> is specified, the default system Account will be used.

If no C<--email> is specified, regular groups will be created by the
System User.

If no C<--permissions> name is specified, the "private" set will be used.  The
"self-join" value can be used to create a group where people can freely join
via the web UI.  Other values will eventually be introduced.

=head2 delete-group --group

Deletes a Socialtext Group. C<--group> must be a Group ID.

=head2 set-permissions --group --permissions

Sets the permission for the specified group to the given named
permission set. Valid set names are:

=over 8

=item * private

=item * self-join

=back

=head2 add-member --group [--account or --workpsace]

Given a Group and an Account or Workspace, add the Group as a Member of the
Account or Workspace, if it exists.

=head2 show-members --group

Given a Group, list its members.

=head2 add-member [ --username or --email ] --group

Given a Group and a User, add the User as a Member of the Group.

=head2 add-workspace-admin --group --workspace

Given a Group and a Workspace, add the Group as an Admin of the Workspace, if
it exists.

=head2 remove-workspace-admin --group --workspace

Given a Group and a Workspace, this command removes admin privileges for the
specified group in the given workspace, and makes it a normal workspace
member.

=head2 add-workspace-impersonator --group --workspace

Given a Group and a Workspace, this command makes the specified Group an
impersonator for the given workspace.

=head2 remove-workspace-impersonator --group --workspace

Given a Group and a Workspace, this command remove impersonate privileges for
the specified Group in the given workspace, and makes them a normal workspace
member.

=head2 add-account-impersonator --group --account

Given a Group and an Account, this command makes the specified Group an
impersonator for the given Account.

=head2 remove-account-impersonator --group --account

Given a Group and an Account, this command remove impersonate privileges for
the specified Group in the given Account, and makes them a normal Account
member.

=head2 add-group-admin [--username or --email] --group

Given a user and a group, this command makes the specified user an
admin for the given group.

=head2 remove-member --group [--account or --workspace]

Given a Group and an Account or Workspace, remove the Group from the Account
or Workspace, if it exists.

=head2 remove-member [ --username or --email ] --group

Given a User and a Group, remove the User from the Group.

=head2 remove-group-admin [--username or --email] --group

Given a user and a group, this command remove admin privileges for
the specified user in the given group, and makes them a normal
group member.

=head2 version

Displays the product version information.

=head2 help

What you're reading now.

=head1 EXIT CODES

If a command completes successfully, the exit code of the process will
be 0. If it cannot complete for some non-fatal reason, the exit code
is 1. An example of this would be if the "send-email-notifications"
command is called for a workspace which has email notifications
disabled. Another example would be passing a "--workspace" argument
and specifying a non-existent workspace.

Fatal errors cause an exit code of 2 or higher. Not passing required
arguments is a fatal error.

=head1 BEHAVIOR UNDER --ceqlotron

All the commands accept an additional "--ceqlotron" argument which tells
them they are running under the ceqlotron. When this is passed,
commands to do not generate any success or failure output, and unless
there is a fatal error, the exit code of the process will always be 0.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005-2006 Socialtext, Inc., All Rights Reserved.

=cut
