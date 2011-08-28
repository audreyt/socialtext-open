#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::HTTP::Socialtext '-syntax', tests => 3;
use Readonly;
use Socialtext::User;
use Test::Live fixtures => ['admin'];
use Test::More;

Readonly my $PAGE_BASE => Test::HTTP::Socialtext->url(
    '/data/workspaces/admin/pages');

test_http "check for no cache headers" {
    >> GET $PAGE_BASE
    >> Accept: text/html

    << 200
    ~< Cache-control: no-cache
    ~< Pragma: no-cache
}

