#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext tests => 1;
fixtures( 'db' );

use Socialtext::Log;

my $logger_one = Socialtext::Log->new;
my $logger_two = Socialtext::Log->new;

is($logger_one, $logger_two, 'the two loggers are the same');

