#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext;

use Cwd;
use File::Basename ();
use File::Spec;
use Socialtext::Build qw( get_build_setting );
use Socialtext::AppConfig;
use Socialtext::File;
use User::pwent;
use YAML ();

my %config_data;
my $config_file;

BEGIN {
    %config_data = (
        status_message_file => 't/tmp/etc/Socialtext/status-message',
        db_user             => 'yomama',
    );

    $config_file = Test::Socialtext->setup_test_appconfig_dir(
        config_data => \%config_data,
    );
    delete $ENV{NLW_APPCONFIG};
}

plan tests => 69;

my $user = getpwuid($>);

ok( Socialtext::AppConfig->is_default('user_factories'), 'using the default value' );

is( Socialtext::AppConfig->self_registration, 0, 'Self-registraction is off by default' );

is( Socialtext::AppConfig->file, $config_file, 'config file is taken from ENV' );

for my $k ( sort keys %config_data ) {
    is( Socialtext::AppConfig->$k(), $config_data{$k}, "check value of $k" );
}

if ( $> ) {
    like( Socialtext::AppConfig->MAC_secret(), qr/needs a better secret/,
          'MAC_secret is generated for non-root user' );
}
else {
    eval { Socialtext::AppConfig->MAC_secret() };
    like( $@, qr/cannot generate a MAC secret/i,
          'error is thrown if MAC_secret was not defined for root user' );
}

my $addr = get_build_setting( 'support-address' );
is( Socialtext::AppConfig->support_address, $addr,
    'support_address is default value before file is changed' );

Update_the_config_file: {
    my $test_address = 'testing@example.com';
    (my $config_dir = $config_file) =~ s#(.+)/.+#$1#;
    $config_file = Test::Socialtext->setup_test_appconfig_dir(
        write_config_only => 1,
        dir => $config_dir,
        config_data => {
            %config_data,
            support_address => $test_address,
        },
    );

    is( Socialtext::AppConfig->support_address, $test_address,
        'config file is reloaded when it changes' );
}

my $last_mod = Socialtext::AppConfig->_last_mod_time();
# must make sure we're at least one second later than earlier tests
sleep 1;
Socialtext::AppConfig->support_address();
is( $last_mod, Socialtext::AppConfig->_last_mod_time(),
    'config file was not reloaded unnecessarily' );

{
    my $file = '/etc/passwd';

    local $ENV{NLW_APPCONFIG} = "status_message_file=$file";

    is( Socialtext::AppConfig->status_message_file, $file,
        'single environment override works' );
}

{
    my $domain = 'foo';
    my $file = '/etc/passwd';

    local $ENV{NLW_APPCONFIG}
        = "cookie_domain=$domain,status_message_file=$file";

    is( Socialtext::AppConfig->status_message_file, $file,
        'double environment override works 1' );
    is( Socialtext::AppConfig->cookie_domain, $domain,
        'double environment override works 2' );

    $ENV{NLW_APPCONFIG}
        = "status_message_file=$file,cookie_domain=$domain";

    is( Socialtext::AppConfig->status_message_file, $file,
        'double environment override works 1 (other order)' );
    is( Socialtext::AppConfig->cookie_domain, $domain,
        'double environment override works 2 (other order)' );
}

{
    my $dir = File::Basename::dirname( Socialtext::AppConfig->file );
    my $file = Socialtext::File::catfile( $dir, 'shortcuts.yaml' );

    open my $fh, '>', $file
        or die "Cannot write to $file: $!";
    close $fh;

    like( Socialtext::AppConfig->shortcuts_file, qr/shortcuts\.yaml$/,
          'found shortcuts.yaml file in same dir as socialtext.conf' );
}

{
    my $addr = 'hello@example.com';
    my $user_factories = 'LDAP:Default';
    isnt( Socialtext::AppConfig->support_address, $addr,
        'some other support_address before calling set()' );
    Socialtext::AppConfig->set( support_address => $addr );
    Socialtext::AppConfig->set( user_factories => $user_factories );
    is( Socialtext::AppConfig->support_address, $addr,
        'support_address changed after calling set()' );
    is( Socialtext::AppConfig->user_factories, $user_factories,
        'user_factories changed after calling set()' );

    Socialtext::AppConfig->write();

    open my $fh, '<', $config_file
        or die "Cannot read $config_file: $!";
    my $config = do { local $/; <$fh> };
    like( $config, qr/support_address:\s+["']?hello\@example\.com["']?/,
          'Calling write() changed the support_address in the config file' );
}

NOT_DEFAULT: {
    # change it to not default
    ok( ! Socialtext::AppConfig->is_default('user_factories'),
        'not using the default value' );

}

{
    # Call ->new() each time to make the module not re-use an existing
    # singleton.
    {
        # have to call ->_default_data_root() directly, as ->new->data_root()
        # only allows for calculation of the default _once_.
        local $ENV{HARNESS_JOB_NUMBER} = 'x';
        like( Socialtext::AppConfig->_default_data_root, qr{t/tmp/x/root$},
            'default data_root_dir ends in t/tmp/x/root when HARNESS_JOB_NUMBER=x' );

        local $ENV{HARNESS_JOB_NUMBER} = '';
        like( Socialtext::AppConfig->_default_data_root, qr{t/tmp/root$},
            'default data_root_dir ends in t/tmp/root when HARNESS_JOB_NUMBER is unset' );

        local $ENV{HARNESS_ACTIVE} = 0;
        like( Socialtext::AppConfig->_default_data_root, qr{\.nlw/root$},
              'default data_root_dir ends in .nlw/root when HARNESS_ACTIVE=0' );
    }

    isnt( Socialtext::AppConfig->new->code_base, '/usr/share/nlw',
          'default code_base is not /usr/share/nlw' );

    like( Socialtext::AppConfig->new->admin_script, qr{(?!/local/)bin/st-admin$},
          'default admin_script ends in bin/st-admin, but is not */local/bin/st-admin' );

    {
        # have to call ->_default_db_name() directly, as ->new->db_name() only
        # allows for calculation of the default _once_.
        my $db_base = 'NLW_' . $user->name;

        local $ENV{HARNESS_JOB_NUMBER} = 'x';
        is( Socialtext::AppConfig->_default_db_name, "${db_base}_testing_x",
            "default db_name is ${db_base}_testing_x when HARNESS_JOB_NUMBER=x" );

        local $ENV{HARNESS_JOB_NUMBER} = '';
        is( Socialtext::AppConfig->_default_db_name, "${db_base}_testing",
            "default db_name is ${db_base}_testing when HARNESS_JOB_NUMBER is unset" );

        local $ENV{HARNESS_ACTIVE} = 0;
        is( Socialtext::AppConfig->_default_db_name, $db_base,
            "default db_name is ${db_base} when HARNESS_ACTIVE=0" );
    }

    is( Socialtext::AppConfig->new->db_user, $user->name,
          'default db_user is ' . $user->name );

    ok( -d File::Spec->catdir( Socialtext::AppConfig->_user_checkout_dir, 'share', 'skin', 's2', 'template' ),
        'the _user_checkout_dir/share Socialtext::AppConfig finds has a template subdir' );

    Socialtext::AppConfig->_set_startup_user(0);
    is( Socialtext::AppConfig->_default_data_root, '/var/www/socialtext',
        'default data root is /var/www/socialtext for root' );
    Socialtext::AppConfig->_set_startup_user($>);
}

CHECK_ALL_METHODS: {
    # This isn't all.  Just the ones I'm most interested in right now.
    my @methods = qw(
        admin_script
        benchmark_mode
        ceqlotron_max_concurrency
        ceqlotron_period
        ceqlotron_synchronous
        change_event_queue_dir
        code_base
        cookie_domain
        custom_http_port
        data_root_dir
        db_host
        db_password
        db_port
        db_name
        db_user
        debug
        email_errors_to
        email_hostname
        enable_weblog_archive_sidebox
        formatter_cache_dir
        login_message_file
        MAC_secret
        pid_file_dir
        script_name
        search_factory_class
        shortcuts_file
        ssl_port
        ssl_only
        stats
        status_message_file
        support_address
        syslog_level
        template_compile_dir
        unauthorized_returns_forbidden
        web_hostname
        web_services_proxy
        search_warning_threshold
        search_time_threshold
    );

    for my $method ( @methods ) {
        ok( Socialtext::AppConfig->can( $method ), "Has $method method" );
    }
}
