#!perl
# @COPYRIGHT@
use warnings;
use strict;
use utf8;
use Test::HTTP::Socialtext '-syntax', tests => 4;
use Readonly;
use Socialtext::Page;
use Socialtext::User;
use Socialtext::Workspace;
use Test::Live fixtures => ['admin_with_extra_pages', 'help', 'foobar'];
use Test::More;

Readonly my $BASE =>
    Test::HTTP::Socialtext->url('/data/workspaces/admin/pages');

TODO: {
    local $TODO = "The 2F problem is hairy.";

    test_http "GET existing page with embedded %2F" {
        >> GET $BASE/admin %2Fwiki

            << 200 };
}
                                
TODO: {
    local $TODO = "We should let encoded percents through";

    test_http "GET existing page with %25%20" {
        >> GET $BASE/admin%25%20wiki

            << 200 };
}
    
TODO: {
    local $TODO = "We should let percents through";

    test_http "GET existing page with embedded %" {
        >> GET $BASE/admin %wiki

            << 200 };
}
                                

TODO: {
    local $TODO = "Question marks get totally confused.";

    test_http "GET existing page with embedded ?" {
        >> GET $BASE/admin ?wiki

            << 200 };
}
                                
