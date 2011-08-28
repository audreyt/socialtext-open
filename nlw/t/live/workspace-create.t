#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Live fixtures => ['admin'];

use Test::More;
use Socialtext::Workspace;

plan tests => 3;

my $live = Test::Live->new();
my $base_uri = $live->base_url;
$live->log_in();

{
    $live->mech()->post(
        "$base_uri/admin/index.cgi", {
            action => 'workspaces_create',
            Button => 'Create',
            name   => 'new-workspace1',
            title  => 'New WS Title1',
        },
    );
    like( $live->mech()->content(), qr/just created "New WS Title1"/,
          'check server response for success message' );

    my $ws = Socialtext::Workspace->new( name => 'new-workspace1' );
    ok( $ws, 'created new workspace' );
    is( $ws->title(), 'New WS Title1', 'check new workspace title' );
}

