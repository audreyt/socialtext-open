#!perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext;
fixtures('db');
use Socialtext::Pages;

plan tests => 9;

$ENV{GATEWAY_INTERFACE} = 1;
$ENV{QUERY_STRING} = 'category=Recent%20Changes';
$ENV{REQUEST_METHOD} = 'GET';

my $hub = create_test_hub;

# Verify that there are no pages in the workspace before we start
my $pages_ref = Socialtext::Pages->All_active(
    workspace_id => $hub->current_workspace->workspace_id,
);
is @$pages_ref, 0, 'no pages found to start';

my $page = Socialtext::Page->new(hub => $hub)->create(
    title => 'a table page',
    creator => $hub->current_user,
    content => '',
);

{
    $page->edit_rev;
    $page->content(<<"EOF");
^^^ Hello Friends

|This table| is for|
|you |and you only|

EOF
    $page->store( user => $hub->current_user );

    my $syndicate = $hub->syndicate;
    isa_ok( $syndicate, 'Socialtext::SyndicatePlugin' );

    my $result = $syndicate->syndicate->as_xml;
    ok( $result, '->syndicate returns a non-empty string' );
    like $result, qr{\Q<td>This table</td>};
    like $result, qr{\Q<table border="1" style="border-collapse:collapse" options="" class="formatter_table">};
}

{
    $page->edit_rev;
    $page->content(<<"EOF");
^^^ Hello Friends

|| border:off
|This table| is for|
|you |and you only|

EOF
    $page->store( user => $hub->current_user );

    my $syndicate = $hub->syndicate;
    isa_ok( $syndicate, 'Socialtext::SyndicatePlugin' );

    my $result = $syndicate->syndicate->as_xml;
    ok( $result, '->syndicate returns a non-empty string' );
    like $result, qr{\Q<td>This table</td>};
    like $result, qr{\Q<table  style="border-collapse:collapse" options="border:off" class="formatter_table borderless">};
}
