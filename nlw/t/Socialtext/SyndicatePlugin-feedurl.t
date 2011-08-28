#!perl
# @COPYRIGHT@

use strict;
use warnings;

use DateTime;
use Test::Socialtext;

BEGIN {
    eval 'use Test::MockObject';
    plan skip_all => 'This test requires Test::MockObject' if $@;
    plan tests => 3;
    use_ok( 'Socialtext::SyndicatePlugin' );
}

fixtures(qw( empty ));

# REVIEW: See t/syndicate-page.t for a less regular expression intensive
# way to do feed tests

my $hub = new_hub('empty');

# We have to call syndicate off the hub to initialize Socialtext::CGI :(
my $syndicator = $hub->syndicate;


# feed_uri_root: non-event workspace
{
    my $workspace = Test::MockObject->new();
    $workspace->mock('is_public', sub { return 0; } );
    $workspace->mock('name', sub { return 'testspace'; } );
    my $uri_root = $syndicator->feed_uri_root($workspace);
    is($uri_root, '/feed/workspace/testspace', 'non-event workspace URI is correct');
}

# feed_uri_root: event workspace
{
    my $event_workspace = Test::MockObject->new();
    $event_workspace->mock('is_public', sub { return 1; } );
    $event_workspace->mock('name', sub { return 'testspace'; } );
    my $uri_root = $syndicator->feed_uri_root($event_workspace);
    is($uri_root, '/feed/workspace/testspace', 'event workspace URI is correct');
}
