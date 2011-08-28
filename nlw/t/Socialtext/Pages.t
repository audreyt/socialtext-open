#!perl
# @COPYRIGHT@

use warnings;
use strict;
use Test::Socialtext tests => 14;
use Try::Tiny;

BEGIN {
    use_ok( 'Socialtext::Pages' );
}

###############################################################################
# Fixtures: admin
# - don't need *this* Workspace, but we *do* need the "devnull1" User to have
#   been created (as that's the default User used by 'new_hub()'
fixtures(qw( admin ));

my $wksp = Socialtext::Workspace->create(
    name => "wksp$$",
    title => "wksp$$",
    account_id => Socialtext::Account->Default->account_id,
);
my $hub = new_hub($wksp->name);
isa_ok( $hub, 'Socialtext::Hub' );
$wksp->add_user(user => $hub->current_user);

CREATE_NEW_PAGE: {
    my $page = $hub->pages->create_new_page();

    ok($page->isa('Socialtext::Page'), 'object is a Socialtext Page');
    like($page->title, qr/^devnull1/, 'title starts with the right name');
}

All_ids: {
    my @all_ids = $hub->pages->all_ids;
    ok @all_ids, 'found some ids';
}

All_since: {
    my @pages = $hub->pages->all_since(300);
    ok @pages, 'found some pages';
    @pages = $hub->pages->all_since(300, 1);
    ok @pages, 'found some active pages';
}

Random_page: {
    my $page = $hub->pages->random_page;
    ok $page->name, 'found a random page';
    ok $page->active, 'page is active';
}

All_ids_locked: {
    my @locked = ();
    foreach (qw(Conversations meeting_agendas)) {
        my $page = $hub->pages->new_from_name($_);
        $page->update_lock_status( 1 );
    }

    my @ids = $hub->pages->all_ids_locked;
    is scalar(@ids), 2, 'Two locked pages returned';
    ok grep({ /^conversations$/ } @ids), 'conversations is one of the pages';
    ok grep({ /^meeting_agendas$/ } @ids), 'meeting_agendas is one of the pages';

}

Page_existence: {
    unnamed_pages_shouldnt_exist: {
        try {
            my $page = $hub->pages->new_from_name('');
        } catch {
            pass "unnamed page can't be created. Throws";
        }
    }

    actual_page_exists: {
        my $page = $hub->pages->new_from_name('Conversations');
        ok $page, 'Got "Conversations" page';
        ok $page->exists, '... which exists';
    }
}
