#!perl

use strict;
use warnings;
use Test::Socialtext tests => 22;

fixtures(qw( db ));

###############################################################################
# Force People Profile Fields to be automatically created, so we don't have to
# set up the default sets of fields from scratch.
$Socialtext::People::Fields::AutomaticStockFields=1;

###############################################################################
# TEST: Can't get a User's Profile if "people" is not enabled
get_profile: {
    my $acct = create_test_account_bypassing_factory();
    my $user = create_test_user(account => $acct);

    my $profile = $user->profile();
    ok !$profile, 'No profile available when People is not enabled.';

    $acct->enable_plugin('people');

    # Refresh User object and verify that the Profile is now available.
    $user = Socialtext::User->new(username => $user->username);
    $profile = $user->profile();
    ok $profile, '... but is available when People is enabled';
}

###############################################################################
# TEST: Preferred Name is missing if no People Profile is available
no_preferred_name_when_people_not_enabled: {
    my $acct = create_test_account_bypassing_factory();
    my $user = create_test_user(account => $acct);

    my $name = $user->preferred_name;
    ok !$name, 'No Preferred Name when People is not enabled';
}

###############################################################################
# TEST: Preferred Name is missing if field is hidden
no_preferred_name_when_field_is_hidden: {
    my $acct = create_test_account_bypassing_factory();
    my $user = create_test_user(account => $acct);
    $acct->enable_plugin('people');

    my $profile = $user->profile();
    $profile->set_attr('preferred_name', 'Bubba Bo Bob Brain');
    $profile->save();

    my $adapter = Socialtext::Pluggable::Adapter->new();
    my $plugin  = $adapter->plugin_class('people');
    $plugin->SetProfileField( {
        name      => 'preferred_name',
        is_hidden => 1,
        account   => $acct,
    } );

    my $name = $user->preferred_name;
    ok !$name, 'No Preferred Name when field is hidden';
}

###############################################################################
# TEST: Preferred Name is available in Profile
preferred_name_available: {
    my $acct = create_test_account_bypassing_factory();
    my $user = create_test_user(account => $acct);
    $acct->enable_plugin('people');

    my $profile = $user->profile();
    $profile->set_attr('preferred_name', 'Bubba Bo Bob Brain');
    $profile->save();

    my $name = $user->preferred_name;
    is $name, 'Bubba Bo Bob Brain', 'Preferred Name curries';
}

###############################################################################
# TEST: User's "preferred_name" shows up in their BFN
best_full_name: {
    my $acct = create_test_account_bypassing_factory();
    $acct->enable_plugin('people');

    my $user = create_test_user(
        first_name => 'Davey',
        last_name  => 'Jones',
        account    => $acct,
    );

    my $old_bfn = $user->best_full_name();
    is $old_bfn, 'Davey Jones', 'BFN is FN/LN when no Preferred Name present';

    my $profile = $user->profile();
    $profile->set_attr('preferred_name', 'Bubba Bo Bob Brain');
    $profile->save();

    my $new_bfn = $user->best_full_name();
    is $new_bfn, 'Bubba Bo Bob Brain', 'BFN is Preferred Name when present';
}

###############################################################################
# TEST: User's "preferred_name" shows up in their "guess_real_name"
guess_real_name: {
    my $acct = create_test_account_bypassing_factory();
    $acct->enable_plugin('people');

    my $user = create_test_user(
        first_name => 'Sam',
        last_name  => 'Gamgee',
        account    => $acct,
    );

    my $old_bfn = $user->best_full_name();
    is $old_bfn, 'Sam Gamgee', 'GRN is FN/LN when no Preferred Name present';

    my $profile = $user->profile();
    $profile->set_attr('preferred_name', 'Bubba Bo Bob Brain');
    $profile->save();

    my $bfn = $user->guess_real_name();
    is $bfn, 'Bubba Bo Bob Brain', 'GFN is Preferred Name when present';
}

###############################################################################
# TEST: User's "preferred_name" shows up in their "guess_sortable_name"
guess_sortable_name: {
    my $acct = create_test_account_bypassing_factory();
    $acct->enable_plugin('people');

    my $user = create_test_user(
        first_name => 'Oscar',
        last_name  => 'Peterson',
        account    => $acct,
    );

    my $old_bfn = $user->best_full_name();
    is $old_bfn, 'Oscar Peterson', 'GRN is FN/LN when no Preferred Name present';

    my $profile = $user->profile();
    $profile->set_attr('preferred_name', 'Bubba Bo Bob Brain');
    $profile->save();

    my $bfn = $user->guess_sortable_name();
    is $bfn, 'bubba bo bob brain', 'Guess Sortable Name contains preferred_name';
}

###############################################################################
# TEST: User's "proper_name" is always "first/middle/last"
proper_name: {
    my $acct = create_test_account_bypassing_factory();
    $acct->enable_plugin('people');

    my $user = create_test_user(
        first_name  => 'Oscar',
        middle_name => 'Emmanuel',
        last_name   => 'Peterson',
        account     => $acct,
    );

    my $proper    = 'Oscar Emmanuel Peterson';
    my $preferred = 'Bob Bitchin';

    is $user->proper_name, $proper, 'Proper Name is first/middle/last when no Preferred Name present';

    my $profile = $user->profile();
    $profile->set_attr('preferred_name', $preferred);
    $profile->save();

    is $user->proper_name, $proper, 'Proper Name is still first/middle/last when Preferred Name is present';
}

###############################################################################
# TEST: "display_name" is set properly on initial User creation
display_name_set_on_create: {
    my $acct = create_test_account_bypassing_factory();

    # First and Last name only
    my $user = create_test_user(
        first_name  => 'Davey',
        last_name   => 'Jones',
        account     => $acct,
    );
    is $user->display_name, 'Davey Jones',
        'display_name calculated at User creation, w/First+Last';

    # First, Middle, and Last name
    $user = create_test_user(
        first_name  => 'Oscar',
        middle_name => 'Emmanuel',
        last_name   => 'Peterson',
        account     => $acct,
    );
    is $user->display_name, 'Oscar Emmanuel Peterson',
        'display_name calculated at User creation, w/First+Middle+Last';
}

###############################################################################
# TEST: "display_name" gets updated when name changes
display_name_updated_on_user_change: {
    my $acct = create_test_account_bypassing_factory();

    my $user = create_test_user(
        account    => $acct,
        first_name => 'Davey',
        last_name  => 'Jones',
    );
    is $user->display_name, 'Davey Jones',
        'display_name set at User creation';

    # Update "first_name"
    $user->update_store(first_name => 'Christina');
    is $user->display_name, 'Christina Jones', '... display_name updated when first_name changed';

    # Update "middle_name"
    $user->update_store(middle_name => 'Rene');
    is $user->display_name, 'Christina Rene Jones', '... display_name updated when middle_name changed';

    # Update "last_name",
    $user->update_store(last_name => 'Hendricks');
    is $user->display_name, 'Christina Rene Hendricks', '... display_name updated when last_name changed';

    # Clear "first_name"
    $user->update_store(first_name => '');
    is $user->display_name, 'Rene Hendricks', '... display_name updated when first_name cleared';

    # Clear "middle_name"
    $user->update_store(middle_name => '');
    is $user->display_name, 'Hendricks', '... display_name updated when middle_name cleared';

    # Clear "last_name"
    $user->update_store(last_name => '');
    is $user->display_name, $user->guess_real_name, '... display_name updated when last_name cleared';
}
