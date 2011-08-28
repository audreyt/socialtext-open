#!perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Apache::Cookie';
use Test::Socialtext tests => 4;
use Socialtext::Pages;

fixtures( 'db' );

# XXX sigh, cgi->changes is checked to see if we should get the data
$ENV{GATEWAY_INTERFACE} = 1;
$ENV{QUERY_STRING} = 'action=recent_changes;changes=recent';
$ENV{REQUEST_METHOD} = 'GET';

my $hub = create_test_hub();

# make a change
{
    my $page = Socialtext::Page->new(hub => $hub)->create(
        title => 'this is a new page',
        content => 'hello',
        creator => $hub->current_user,
    );
}

{
    my $output = $hub->recent_changes->recent_changes;

    ok($output ne '', 'output exists');
    like($output, qr/this_is_a_new_page"/,
        'output is somewhat reasonable');
    unlike($output, qr/called at lib\/.*line\s\d+/,
        'does not have error output');
    like($output, qr/this is a new page/i, 'expected title is present');
}
