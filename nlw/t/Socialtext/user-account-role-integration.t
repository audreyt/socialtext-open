#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::Workspace;
use Socialtext::UserMetadata;
use Test::Socialtext tests => 17;

fixtures(qw( db ));

################################################################################
create_user_in_default_account: {
    my $account = Socialtext::Account->Default;
    my $user = create_test_user( account => $account );

    ok $account->has_user($user), 'User has role in default account';
}

################################################################################
user_in_non_default_account: {
    my $default = Socialtext::Account->Default;
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user(account => $account);

    ok $account->has_user($user), 'User has role in non-default account';

    ok !$default->has_user($user), 'User has no role in default account';
}

################################################################################
change_user_account: {
    my $old_account = create_test_account_bypassing_factory();
    my $new_account = create_test_account_bypassing_factory();
    my $user        = create_test_user(account => $old_account);
    my $member      = Socialtext::Role->Member();

    ok $old_account->has_user($user), 'User has role in account 1';

    $user->primary_account( $new_account->account_id );
    is $user->primary_account->account_id, $new_account->account_id,
        'primary account updated.';

    ok $old_account->has_user($user), 'User still has role in old account';
    is $old_account->role_for_user($user)->role_id, $member->role_id,
        '... role is member';
    ok $new_account->has_user($user), 'User has role in new account';
}

################################################################################
user_with_secondary_account: {
    my $primary   = create_test_account_bypassing_factory();
    my $secondary = create_test_account_bypassing_factory();
    my $user      = create_test_user( account => $primary );
    my $ws        = create_test_workspace( account => $secondary );

    # Add user to workspace/secondary account
    $ws->add_user( user => $user );

    ok $primary->has_user($user), 'user is in primary account';
    ok $secondary->has_user($user), 'user is in secondary account';

    # Remove user to workspace/secondary account
    $ws->remove_user( user => $user );

    ok $primary->has_user($user), 'user is still in primary account';
    ok !$secondary->has_user($user), 'user is no longer in secondary account';
}

################################################################################
workspace_changes_account: {
    my $primary   = create_test_account_bypassing_factory();
    my $secondary = create_test_account_bypassing_factory();
    my $other     = create_test_account_bypassing_factory();
    my $user      = create_test_user( account => $primary );
    my $ws        = create_test_workspace( account => $secondary );
    
    $ws->add_user( user => $user );
    ok $primary->has_user($user), 'user is in primary account';
    ok $secondary->has_user($user), 'user is in secondary account';

    $ws->update( account_id => $other->account_id );

    ok $primary->has_user($user), 'user is still in primary account';
    ok !$secondary->has_user($user), 'user is no longer in secondary account';
    ok $other->has_user($user), 'user is now in other account';
}
