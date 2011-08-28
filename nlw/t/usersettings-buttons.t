#!perl
# @COPYRIGHT@

use strict;
use warnings;

use mocked 'Apache::Cookie';
use Test::Socialtext;
fixtures(qw( empty ));

my @tests = (
  [ qr{\Q<a class="genericOrangeButton" id="-savelink" href="#" onclick="document.forms['settings'].submit(); return false">\E\s+Save\s+</a>},
    'Submit button is submit' ],
  [ qr{\Q<a class="genericOrangeButton" id="-cancellink" href="#" onclick="document.forms['settings'].reset(); return false">\E\s+Cancel\s+</a>},
    'Cancel button is reset' ],
);

plan tests => scalar @tests;

$ENV{GATEWAY_INTERFACE} = 1;
$ENV{QUERY_STRING} = 'action=users_settings';
$ENV{REQUEST_METHOD} = 'GET';

my $hub = new_hub('empty');

my $settings = $hub->user_settings;
my $result = $settings->users_settings;
for my $test (@tests)
{
    like( $result, $test->[0], $test->[1] );
}
