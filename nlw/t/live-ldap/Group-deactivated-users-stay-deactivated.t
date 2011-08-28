#!perl

use strict;
use warnings;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 11;
use Test::Socialtext::Group;
use Socialtext::Group::Factory;

fixtures(qw( db ));

###############################################################################
# IMPORTANT: Force Group lookups to be synchronous.
local $Socialtext::Group::Factory::Asynchronous = 0;

###############################################################################
sub bootstrap_openldap {
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif', 'added base dn');
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif', 'added people');
    ok $openldap->add_ldif('t/test-data/ldap/groups-groupOfNames.ldif', 'added groups');
    return $openldap;
}

###############################################################################
# TEST: Deactivated Users *stay* deactivated after Group refresh
#
# Bug {bz: 4954} - When a User has been explicitly deactivated and moved to
# the "Deleted Account" but they're still listed in LDAP as being in a Group,
# they should *NOT* be re-added back to the Group.
deactivated_users_stay_deactivated: {
    my $openldap = bootstrap_openldap();
    my $group_dn = 'cn=Motorhead,dc=example,dc=com';
    my $user_dn  = 'cn=Phil Taylor,dc=example,dc=com';

    # Vivify the test Group and User.
    my $group = Socialtext::Group->GetGroup(driver_unique_id => $group_dn);
    ok $group, 'Found test Group in LDAP';

    my $user = Socialtext::User->new(driver_unique_id => $user_dn);
    ok $user, 'Found test User in LDAP';
    ok $group->has_user($user), '... who is a member of Group';
    ok !$user->is_deactivated, '... and who has not been deactivated (yet)';

    # Deactivate the User, thus relinquishing *all* of his privileges
    $user->deactivate;
    ok $user->is_deactivated, 'User has been deactivated';
    ok !$group->has_user($user), '... and is not a member of Group';

    # Refresh the Group
    $group->expire;
    $group = Socialtext::Group->GetGroup(driver_unique_id => $group_dn);

    # VERIFY: User is still considered deactivated, and is NOT in Group
    ok $user->is_deactivated, 'User is still considered deactivated';
    ok !$group->has_user($user), '... and was not added back into the Group';

    # CLEANUP
    Test::Socialtext::Group->delete_recklessly($group);
}
