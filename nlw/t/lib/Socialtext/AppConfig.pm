package Socialtext::AppConfig;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::MockBase';

our $DEFAULT_WORKSPACE = 'default';
our $CODE_BASE = '/codebase';
our $SCRIPT_NAME = '/scripts';
our $CUSTOM_HTTP_PORT = 12345;
our $CONFIG_DIR = '/config_dir';

sub db_connect_params {
    my %params = (
        db_name => db_name(),
        user => $ENV{USER},
        schema_name => 'socialtext',
    );
    return wantarray ? %params : \%params;
}

sub db_name { "NLW_$ENV{USER}_testing" }

sub is_appliance { 0 }

sub shortcuts_file {}

sub syslog_level { 1 }

sub ssl_only { 0 }

sub default_workspace { $DEFAULT_WORKSPACE }

sub code_base { $CODE_BASE }
sub script_name { $SCRIPT_NAME }

sub user_factories { 'Default' }
sub group_factories { 'Default' }

sub data_root_dir { '/datadir' }

sub stats { 'stats' }
sub config_dir { $CONFIG_DIR }
sub template_compile_dir { 't/tmp' }

sub locale { 'en' }
sub debug { 0 }

sub web_hostname { 'mock_web_hostname' }
sub custom_http_port { $CUSTOM_HTTP_PORT }
sub instance { Socialtext::AppConfig->new }

sub startup_user_is_human_user { 1 }

sub _user_root { "$ENV{HOME}/.nlw" }

sub web_services_proxy { '' }

sub test_slot {
    return $ENV{HARNESS_JOB_NUMBER};
}

sub test_dir {
    my $slot = test_slot();
    my $base = 't/tmp';
    return $slot ? "$base/$slot" : $base;
}

sub _cache_root_dir { test_dir . "/cache" }

sub Options {}

sub pid_file_dir { test_dir . "/run" }

1;
