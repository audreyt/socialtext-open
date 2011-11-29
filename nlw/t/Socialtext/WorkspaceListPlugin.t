#!perl
# @COPYRIGHT@

use strict;
use warnings;
use DateTime;
use Socialtext::Pages;
use Test::Socialtext tests => 4;

fixtures(qw(db));
use_ok 'Socialtext::WorkspaceListPlugin';

# Create a dummy/test Hub
my $hub  = create_test_hub('admin');
my $user = $hub->current_user;

my $output = $hub->workspace_list->widget_workspace_list;
ok( $output ne '', 'output exists' );
unlike( $output, qr/navList/, 'Non wiki page' );
like( $output, qr/target="_blank"/, 'Workspace links open in new window' );

1;
