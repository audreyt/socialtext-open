#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext;

BEGIN {
    unless (
        eval {
            require Test::Output;
            Test::Output->import();
            1;
        }
        ) {
        plan skip_all => 'These tests require Test::Output to run.';
    }
}

plan tests => 3;

use File::Temp ();
use Socialtext::AppConfig;
use Socialtext::CLI;
use Socialtext::DaemonUtil;

our $LastExitVal;
no warnings 'redefine';
local *Socialtext::CLI::_exit = sub { $LastExitVal = shift; die 'exited'; };
local *Socialtext::DaemonUtil::_exit = sub { $LastExitVal = shift; die 'exited'; };

our $HelpWasCalled;
local *Socialtext::CLI::help = sub { $HelpWasCalled = 1 };

my $data_root = File::Temp::tempdir( CLEANUP => 1 );
Socialtext::AppConfig->set( data_root_dir => $data_root );

chmod 0400, $data_root
    or die "Cannot chmod $data_root to 0400: $!";

Socialtext::CLI->new( argv => [qw( help )] )->run();
ok( $HelpWasCalled, 'help works even when data root dir is not writeable' );

stderr_like(
    sub {
        eval {
            Socialtext::CLI->new( argv => [qw( give-system-admin )] )->run();
        };
    },
    qr/is not writeable by this process/,
    'cannot run other commands when data root is not writeable',
);
is( $LastExitVal, 1, 'exited with exit code 1' );
