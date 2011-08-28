#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use YAML qw();
use File::Slurp qw(write_file);
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext tests => 8;

use_ok( 'Socialtext::OpenToken::Config' );

###############################################################################
### TEST DATA
###############################################################################
our $yaml = <<EOY;
challenge_uri: http://www.google.com/
token_parameter: my_token
password: abc123
clock_skew: 123
auto_provision_users: 1
EOY

###############################################################################
# TEST: check for required fields
check_required_fields: {
    foreach my $required (qw( challenge_uri password )) {
        clear_log();

        my $data = YAML::Load($yaml);
        delete $data->{$required};

        my $config = Socialtext::OpenToken::Config->new(%{$data});
        ok !defined $config, "instantiation, missing '$required' parameter";

        is logged_count(), 1, '... logged right number of entries';
        next_log_like 'error', qr/missing '$required'/, "... ... missing $required";
    }
}

###############################################################################
# TEST: instantiation w/full config
instantiation: {
    my $data   = YAML::Load($yaml);
    my $config = Socialtext::OpenToken::Config->new(%{$data});
    isa_ok $config, 'Socialtext::OpenToken::Config', 'valid instantiation';
}

