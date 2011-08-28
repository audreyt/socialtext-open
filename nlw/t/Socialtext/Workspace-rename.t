#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 3;
use Socialtext::EmailAlias;
use Socialtext::File;
use Socialtext::Paths;
use Socialtext::Account;
use Socialtext::Workspace;

# Fixtures: help
#
# - Need "help" WS in place so that default pages get copied in to new
#   Workspaces.
fixtures(qw( help ));

{
    my $ws = Socialtext::Workspace->create(
        name       => 'short-name',
        title      => 'Longer Title',
        account_id => Socialtext::Account->Socialtext()->account_id,
    );

    $ws->rename( name => 'new-name' );

    is( $ws->name(), 'new-name', 'workspace name is new-name' );

    ok( ! Socialtext::EmailAlias::find_alias('short-name'),
        'short-name alias does not exist after rename' );

    ok( Socialtext::EmailAlias::find_alias('new-name'),
        'new-name alias exists after rename' );
}
