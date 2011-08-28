#!perl
# @COPYRIGHT@

use strict;
use warnings;
use DateTime;
use Socialtext::Pages;
use Test::Socialtext tests => 7;

fixtures(qw( admin foobar help no-ceq-jobs ));
use_ok 'Socialtext::WorkspaceListPlugin';

# Create a dummy/test Hub
my $hub  = create_test_hub('admin');
my $user = $hub->current_user;

my $output = $hub->workspace_list->workspace_list;
ok( $output ne '', 'output exists' );
like( $output, qr/recent_changes/, 'S3 furnishings exist' );
unlike( $output, qr/target="_blank".*Socialtext Documentation/, 'Workspace links open in same window' );

$output = $hub->workspace_list->widget_workspace_list;
ok( $output ne '', 'output exists' );
unlike( $output, qr/recent_changes/, 'No S3 furnishings exist' );
like( $output, qr/target="_blank".*Socialtext Documentation/, 'Workspace links open in new window' );

1;
