#!perl
# @COPYRIGHT@

use warnings;
use strict;

# Also see the other t/live/rest test files for more permissions
# related tests.

use Test::HTTP::Socialtext '-syntax', tests => 13;

use Readonly;
use Test::Live; # need everything for extra users
use Test::More;

Readonly my $BASE     => Test::HTTP::Socialtext->url('/data/workspaces');
Readonly my $NEW_BODY => "Aw yeah, it's like that\n";

# Guest access to auth-to-edit
#TODO: {
#    local $TODO="guest user handling not yet implemented";
#
#    test_http "unset user can read but not edit auth-to-edit" {
#        >> GET $BASE/auth-to-edit/pages/start_here
#        >> Accept: text/plain
#
#        << 200
#
#        >> PUT $BASE/auth-to-edit/pages/start_here
#        >> Content-Type: text/x.socialtext-wiki
#        >>
#        >> $NEW_BODY
#
#        << 401
#    }
#}

# made up bullshit user
NOT_USER: {
    foreach my $method qw(GET PUT) {
        run_test(
            name         => 'made up user fails page',
            user         => 'stuffnonsense@socialtext.com',
            password     => 'password',
            method       => $method,
            uri          => "$BASE/admin/pages/start_here",
            accept       => 'text/plain',
            content_type => 'text/x.socialtext-wiki',
            content      => $NEW_BODY,
            status       => 401,
        );
    }
}

# real user bad password
BAD_PASS: {
    foreach my $method qw(GET PUT) {
        run_test(
            name         => 'user with bad password fails',
            user         => 'devnull1@socialtext.com',
            password     => 'XXXXXd3vnu11lXXXX',
            method       => $method,
            uri          => "$BASE/admin/pages/start_here",
            accept       => 'text/plain',
            content_type => 'text/x.socialtext-wiki',
            content      => $NEW_BODY,
            status       => 401,
        );
    }
}

# authed user without access to workspace
NOT_MEMBER: {
    foreach my $method qw(GET PUT DELETE) {
        run_test(
            name         => 'admin as devnull2 gets 403',
            user         => 'devnull2@socialtext.com',
            password     => 'd3vnu11l',
            method       => $method,
            uri          => "$BASE/admin/pages/start_here",
            accept       => 'text/plain',
            content_type => 'text/x.socialtext-wiki',
            content      => $NEW_BODY,
            status       => 403,
        );
    }
}

BAD_WORKSPACE: {
    foreach my $method qw(GET PUT DELETE) {
        run_test(
            name         => 'accessing bad workspace gets a 404',
            user         => 'devnull1@socialtext.com',
            password     => 'd3vnu11l',
            method       => $method,
            uri          => "$BASE/artifice/pages/start_here",
            accept       => 'text/plain',
            content_type => 'text/x.socialtext-wiki',
            content      => $NEW_BODY,
            status       => 404,
        );
    }
}

GOOD_USER: {
    $Test::HTTP::BasicUsername = 'devnull1@socialtext.com';
    $Test::HTTP::BasicPassword = 'd3vnu11l';

    test_http "access admin as devnull1 and succeed" {
        >> GET $BASE/admin/pages/start_here
        >> Accept: text/plain

        << 200

        >> PUT $BASE/admin/pages/start_here
        >> Content-Type: text/x.socialtext-wiki
        >>
        >> $NEW_BODY

        << 204

        >> DELETE $BASE/admin/pages/start_here
        
        << 204

    }
}

sub run_test {
    my %p = @_;

    $Test::HTTP::BasicUsername = $p{user};
    $Test::HTTP::BasicPassword = $p{password};

    my $test = Test::HTTP->new($p{name});
    $test->new_request($p{method} => $p{uri});
    $test->request->header('Accept' => $p{accept}) if $p{accept};
    $test->request->header( 'Content-type' => $p{content_type} )
        if $p{content_type};
    if ($p{content} && ($p{method} eq 'PUT' || $p{method} eq 'POST')) {
        $test->request->content($p{content});
    }

    $test->run_request();

    $test->status_code_is($p{status});
}

