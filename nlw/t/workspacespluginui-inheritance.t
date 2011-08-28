#!perl
# @COPYRIGHT@

# this test validates that the correct workspace customization attributes
# are "inherited" by newly created workspaces via the web UI

use strict;
use warnings;
use Test::Socialtext tests => 20;

###############################################################################
# Fixtures: empty destructive
# - we knowingly stomp on the test-env, so mark it as needing cleanup
fixtures(qw( empty destructive ));

use_ok( "Socialtext::WorkspacesUIPlugin" );

my $custom_header_logo_link_uri = "http://foo";

my %custom_params = (
    cascade_css => 0,
    customjs_name => "somecustomjsname",
    customjs_uri => "http://somecustomjsuri",
    skin_name => 'common',
    show_welcome_message_below_logo => 0,
    show_title_below_logo => 0,
    header_logo_link_uri => "http://foo",
);

sub toggle {
    my $value = shift;
    return 0 if( $value );
    return 1;
}

{
    $ENV{GATEWAY_INTERFACE} = 1;
    $ENV{QUERY_STRING} = 'name=new-workspace&title=New%20Title';
    $ENV{REQUEST_METHOD} = 'GET';
    my $hub = new_hub('empty');

    my $workspaces_plugin = $hub->workspaces_ui;

    ok( $workspaces_plugin, "can't even create plugin" );

    my $ws = $hub->current_workspace;

# customize settings by making sure we change values
# use toggle routine to change the booleans
    $custom_params{'show_welcome_message_below_logo'} = 
        toggle($ws->show_welcome_message_below_logo );
    $custom_params{'show_title_below_logo'} = 
        toggle($ws->show_title_below_logo );
    $custom_params{'cascade_css'} =
        toggle($ws->cascade_css);

    $ws->update( %custom_params );

    my $new_ws = $workspaces_plugin->_create_workspace();
    
    ok( $new_ws, "_create_workspace failed: $@" );
    # NOTE: I had some trouble figuring out how to update the settings
    # these tests just confirm that things got changed. Just a sanity
    # check, move along
    is( $ws->header_logo_link_uri, 
        $custom_params{'header_logo_link_uri'},
        "couldn't customize empty logo link uri");
    is( $ws->show_welcome_message_below_logo,
        $custom_params{'show_welcome_message_below_logo'},
        "couldn't customize show_welcome_message_below_logo" );
}

{
    # reload hubs, and workspaces and then check to make sure things
    # match our expectations and each other.

    my $hub = new_hub('empty');
    my $new_hub = new_hub('new-workspace');
    my $ws = $hub->current_workspace;
    my $new_ws = $new_hub->current_workspace;

    is( $new_ws->account_id, 
        $ws->account_id, "account_id didn't match" );

    is( $new_ws->show_title_below_logo, 
        $ws->show_title_below_logo, 
        "show_title_below_logo didn't match empty ws" );

    is( $new_ws->show_title_below_logo, 
        $custom_params{'show_title_below_logo'},, 
        "show_title_below_logo didn't match our toggle" );

    is( $new_ws->show_welcome_message_below_logo, 
        $ws->show_welcome_message_below_logo,
        "show_welcome_message_below_logo didn't match empty ws" );

    is( $new_ws->show_welcome_message_below_logo, 
        $custom_params{'show_welcome_message_below_logo'},
        "show_welcome_message_below_logo didn't match our toggle" );

    is( $new_ws->cascade_css,
        $ws->cascade_css,
        "cascade_css didn't match empty ws" );
    
    is( $new_ws->cascade_css,
        $custom_params{'cascade_css'},
        "cascade_css didn't match our toggle" );    

    is( $new_ws->customjs_name,
        $ws->customjs_name,
        "customjs_name matched empty ws" );

    is( $new_ws->customjs_name,
        $custom_params{'customjs_name'},
        "customjs_name matched our new value" );

    is( $new_ws->customjs_uri,
        $ws->customjs_uri,
        "customjs_uri matched empty ws" );

    is( $new_ws->customjs_uri,
        $custom_params{'customjs_uri'},
        "customjs_uri matched our new value" );

    is( $new_ws->header_logo_link_uri, 
        $ws->header_logo_link_uri,
        "header_logo_link_uri didn't match empty ws" );

    is( $new_ws->header_logo_link_uri, 
        $custom_params{'header_logo_link_uri'},
        "header_logo_link_uri didn't match our new value" );

    is( $new_ws->skin_name,
        $ws->skin_name,
        "skin_name didn't match empty ws" );

    is( $new_ws->skin_name,
        $custom_params{'skin_name'},
        "skin_name didn't match our new value" );

}
