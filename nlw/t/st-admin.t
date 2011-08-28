#!perl
# @COPYRIGHT@

use strict;
use warnings;
use IPC::Run;

use Test::Socialtext tests => 3;
fixtures( 'db' );

# The purpose of this test is to make sure that st-admin interfaces to
# Socialtext::CLI properly, and that passing it a command does what we
# expect.
#
# However, to test all the commands and the internals of
# Socialtext::CLI, please see t/Socialtext/CLI.t
{
    my @command = qw( bin/st-admin version );

    my ( $in, $out, $err );

    IPC::Run::run( \@command, \$in, \$out, \$err );
    my $return = $? >> 8;

    is( $return, 0, 'command returns proper exit code with simple message' );
    is( $err, '', 'no stderr output with simple message' );
    like( $out, qr/Socialtext v\d+\.\d+\.\d+\.\d+/,
          'Output to STDOUT includes version number' );
}
