#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 8;
use Socialtext::Page;
use Socialtext::User;
use Socialtext::Jobs;
use Socialtext::WebHook;

fixtures(qw( empty ));

###############################################################################
# At one customer site, a handful of Users got their "email address" and
# "username" out of sync with one another, which resulted in problems
# accessing pages that had been created by or last edited by them before
# things got out of sync.
#
# When attempting to look up the User records by their _old_ e-mail address
# (as had been recorded in the Page metadata) we weren't finding their User
# record and then proceeded to try to create a new one.  This would then fail
# as a User record existed with that e-mail address as its username.
#
# This test suite verifies that when we do User lookups based on the e-mail
# address recorded in the page metadata that we check not only against the 
# "e-mail address" field in the DB but also in the "username" field.
#
# Admittedly, we *shouldn't* need to do this (as for these Users we should be
# able to rely on the "username" and "email address" being in sync).  When
# this isn't the case, though, we should be doing a better job of finding the
# User record (as opposed to exploding and displaying an error page in the
# browser).
###############################################################################

###############################################################################
### TEST DATA
my $old_email  = 'jane_doe@example.com';
my $new_email  = 'jane_smith@example.com';
my $first_name = 'Jane';
my $last_name  = 'Smith';
my $page_id    = 'dummy_page';

###############################################################################
# TEST: User lookups from ST::Page resolve, when username/email don't match
user_lookups_resolve_properly: {
    ### Create the problematic situation...
    create_problematic_situation: {
        # A new User
        my $user = Socialtext::User->create(
            username      => $old_email,
            email_address => $old_email,
            first_name    => $first_name,
            last_name     => $last_name,
        );
        ok $user, 'Created a test User';

        # That has created a Page
        my $hub  = new_hub('empty', $old_email);
        $hub->current_workspace->add_user(
            user => $user,
            role => Socialtext::Role->Member,
        );
        my $page = Socialtext::Page->new(hub => $hub)->create(
            title   => $page_id,
            content => 'some stuff',
            creator => $hub->current_user,
        );
        ok $page, '... who created a page';

        # And which then had their username/e-mail address knocked out of sync
        ok $user->update_store(email_address => $new_email), '... updated User';
        isnt $user->username, $user->email_address,
            '... bringing username and e-mail address out of sync';
    }

    ### Then test that User lookups are resolving properly
    verify_user_resolves: {
        # Now, as a *different* User, access that page
        my $user = create_test_user();
        my $hub  = new_hub('empty', $user->username);

        my $page = $hub->pages->new_from_name($page_id);
        ok $page, 'Found the page';

        my $creator = $page->creator();
        ok $creator, '... and the creator';

        my $last_editor = $page->last_edited_by();
        ok $last_editor, '... and the last editor';

        my $hash = $page->hash_representation;
        ok $hash, '... and the hash representation';
    }
}
