#! perl -w
# @COPYRIGHT@
use warnings;
use strict;

use Test::Socialtext tests => 4;

fixtures('foobar', 'help');

use Socialtext::User;
use t::SocialtextTestUtils qw/index_page/;

BEGIN {
    use_ok( 'Socialtext::Search', 'search_on_behalf' );
}

# This search test is testing that the guest user can't see results
# from the private foobar wiki.
# Rather than index everything, lets just index a few pages
index_page('foobar', 'announcements_and_links');
index_page('help-en', 'announcements_and_links');

my $user = Socialtext::User->Guest;
eval {
    search_on_behalf( 'help-en', 'link workspaces:foobar,help-en', '_', $user );
};
isa_ok( $@, 'Socialtext::Exception::Auth', "auth exception on search foobar" );

HIT: {
    my $hits;
    my $hit_count;
    eval {
        ($hits, $hit_count)
            = search_on_behalf( 'help-en', 'link workspaces:foobar,help-en', '_',
            $user, sub { }, sub { } );
    };
    is( $@, '', "No exceptions thrown." );
    for my $hit (@$hits) {
        if ($hit->workspace_name eq 'foobar') {
            fail('No foobar hits for guest user.');
            last HIT;
        }
    }
    pass('No foobar hits for guest user.');
}
