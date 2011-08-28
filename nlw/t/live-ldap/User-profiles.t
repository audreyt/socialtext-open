#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 61;
use Test::Socialtext::User;
use Socialtext::Jobs;
use Socialtext::Job::ResolveRelationship;

# Explicitly load these, so we *know* they're loaded (instead of just waiting
# for them to be lazy loaded); we need to set some pkg vars for testing
use Socialtext::People::Profile;
use Socialtext::People::Fields;

# We're destructive, as we monkey around with the People Fields setup for the
# Default Account.  *Far* easier to just mark ourselves as destructive than it
# is to do this cleanly.
fixtures(qw( db destructive ));

###############################################################################
# Force People Profile Fields to be automatically created, so we don't have to
# set up the default sets of fields from scratch.
$Socialtext::People::Fields::AutomaticStockFields=1;

###############################################################################
# Make *ALL* profile lookups synchronous (easier testing)
$Socialtext::Pluggable::Plugin::People::Asynchronous=0;

###############################################################################
# Limit the runnable Jobs to just the ones we care about
Socialtext::Jobs->can_do('Socialtext::Job::ResolveRelationship');

###############################################################################
sub bootstrap_openldap {
    my %p    = @_;
    my $acct = $p{account};

    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP';
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'),
        '.. added data: base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/relationships.ldif'),
        '... added data: relationships';

    # Update the "supervisor" People Field in this Account so its LDAP sourced
    my $people = Socialtext::Pluggable::Adapter->plugin_class('people');
    $people->SetProfileField( {
        name    => 'supervisor',
        source  => 'external',
        account => $acct,
    } );

    # Ensure that the LDAP config maps the "supervisor" field to an LDAP attr
    my $config = $openldap->ldap_config();
    $config->{attr_map}{supervisor} = 'manager';
    Socialtext::LDAP::Config->save($config);

    return $openldap;
}

###############################################################################
# TEST: instantiate User with a Supervisor
instantiate_user_with_supervisor: {
    my $guard = Test::Socialtext::User->snapshot();
    my $acct  = Socialtext::Account->Default;
    my $ldap  = bootstrap_openldap(account => $acct);

    # Load up a User that has a Supervisor, and the Supervisor itself
    my $user = Socialtext::User->new(username => 'Ariel Young');
    ok $user, 'loaded User with a supervisor';

    my $supervisor = Socialtext::User->new(username => 'Adrian Harris');
    ok $supervisor, 'loaded Supervisor';

    # Check that the Supervisor was loaded _into_ the Default Account
    is $supervisor->primary_account_id, $acct->account_id,
        '... who was loaded into the Default Account';

    # Check that the Supervisor is linked in the Profile
    my $profile = Socialtext::People::Profile->GetProfile($user, no_recurse=>1);
    ok $profile, 'got People Profile';

    my $queried = $profile->get_reln('supervisor');
    ok $queried, '... that has a supervisor';
    is $queried, $supervisor->user_id, '... ... and its who we expect';
};

###############################################################################
# TEST: supervisor gets cleared in LDAP
supervisor_cleared: {
    my $guard = Test::Socialtext::User->snapshot();
    my $acct  = Socialtext::Account->Default;
    my $ldap  = bootstrap_openldap(account => $acct);

    # Load up a User that has a Supervisor, and the Supervisor itself
    my $user = Socialtext::User->new(username => 'Ariel Young');
    ok $user, 'loaded User with a supervisor';

    my $supervisor = Socialtext::User->new(username => 'Adrian Harris');
    ok $supervisor, 'loaded Supervisor';

    # Check that the Supervisor is linked in the Profile
    my $profile = Socialtext::People::Profile->GetProfile($user, no_recurse=>1);
    ok $profile, 'got People Profile';

    my $queried = $profile->get_reln('supervisor');
    ok $queried, '... that has a supervisor';
    is $queried, $supervisor->user_id, '... ... and its who we expect';

    # Clear the Supervisor in LDAP, refresh, and make sure it got cleared.
    my $rc = $ldap->modify($user->driver_unique_id, delete => [qw(manager)]);
    ok $rc, 'modified User in LDAP, removing supervisor';

    $user->homunculus->expire();

    $user    = Socialtext::User->new(username => 'Ariel Young');
    $profile = Socialtext::People::Profile->GetProfile($user, no_recurse=>1);
    $queried = $profile->get_reln('supervisor');
    ok !defined $queried, '... removal of supervisor reflected in People Profile';
}

###############################################################################
# TEST: recursive relationship A->B->A
recursive_relationship: {
    my $guard = Test::Socialtext::User->snapshot();
    my $acct  = Socialtext::Account->Default;
    my $ldap  = bootstrap_openldap(account => $acct);

    # Update the Users in LDAP, creating the recursive relationship
    my $ariel_dn  = 'cn=Ariel Young,ou=related,dc=example,dc=com';
    my $adrian_dn = 'cn=Adrian Harris,ou=related,dc=example,dc=com';

    my $rc = $ldap->modify($ariel_dn, replace => ['manager' => $adrian_dn]);
    ok $rc, 'Ariel now has Adrian as a manager, in LDAP';

    $rc = $ldap->modify($adrian_dn, replace => ['manager' => $ariel_dn]);
    ok $rc, 'Adrian now has Ariel as a manager, in LDAP';

    # Load up one of the Users; both should get loaded, but we shouldn't end
    # up recursing endlessly.
    my $ariel = Socialtext::User->new(username => 'Ariel Young');
    ok $ariel, 'loaded Ariel user';

    my $adrian = Socialtext::User->new(username => 'Adrian Harris');
    ok $adrian, 'loaded Adrian user';

    # Check that they're each marked as each other's manager
    my $ariel_profile = Socialtext::People::Profile->GetProfile($ariel, no_recurse=>1);
    is $ariel_profile->get_reln('supervisor'), $adrian->user_id,
        'Ariel has Adrian as a manager';

    my $adrian_profile = Socialtext::People::Profile->GetProfile($adrian, no_recurse=>1);
    is $adrian_profile->get_reln('supervisor'), $ariel->user_id,
        'Adrian has Ariel as a manager';
}

###############################################################################
# TEST: supervisor changes
supervisor_changes: {
    my $guard = Test::Socialtext::User->snapshot();
    my $acct  = Socialtext::Account->Default;
    my $ldap  = bootstrap_openldap(account => $acct);

    # instantiate "username => 'Ariel Young'" 
    my $ariel = Socialtext::User->new(username => 'Ariel Young');
    ok $ariel, 'loaded Ariel user';
    my $adrian = Socialtext::User->new(username => 'Adrian Harris');
    ok $adrian, 'loaded Adrian user';
    my $belinda = Socialtext::User->new(username => 'Belinda King');
    ok $belinda, 'loaded Belinda user';

    # change Ariel's manager to Belinda King
    my $ariel_dn  = 'cn=Ariel Young,ou=related,dc=example,dc=com';
    my $belinda_dn = 'cn=Belinda King,ou=related,dc=example,dc=com';

    my $ariel_profile = Socialtext::People::Profile->GetProfile($ariel, no_recurse=>1);

    my $rc = $ldap->modify($ariel_dn, replace => ['manager' => $belinda_dn]);
    ok $rc, 'Ariel now has Belinda as a manager, in LDAP';

    # expire Ariel's user record
    $ariel->homunculus->expire();

    # reload Ariel
    $ariel = Socialtext::User->new(username => 'Ariel Young');
    ok $ariel, 'reloaded Ariel user';

    # Check that Ariel now has Belinda as her manager
    $ariel_profile = Socialtext::People::Profile->GetProfile($ariel, no_recurse=>1);
    is $ariel_profile->get_reln('supervisor'), $belinda->user_id,
        'Ariel has Belinda as a manager after expire';
}

###############################################################################
# TEST: supervisor is invisible (out of base_dn or filtered out)
supervisor_cannot_be_found: {
    my $guard = Test::Socialtext::User->snapshot();
    my $acct  = Socialtext::Account->Default;
    my $ldap  = bootstrap_openldap(account => $acct);

    # update LDAP config "filter" to be
    #   "(&(objectClass=inetOrgPerson)(manager=*))"
    #   - e.g. only inetOrgPerson records that *have* a manager, which will
    #     ignore Adrian (the manager) because he has no manager
    my $config = $ldap->ldap_config();
    $config->{filter} = '(&(objectClass=inetOrgPerson)(manager=*))';
    Socialtext::LDAP::Config->save($config);

    # instantiate "username => 'Ariel Young'"
    my $ariel = Socialtext::User->new(username => 'Ariel Young');
    ok $ariel, 'loaded Ariel user';

    # Check that Ariel has _no_ manager in her Profile
    my $ariel_profile = Socialtext::People::Profile->GetProfile($ariel, no_recurse=>1);
    ok !$ariel_profile->get_reln('supervisor'),
        'Ariel has no manager because manager is filtered out';
}

###############################################################################
# TEST: multiple supervisors listed in LDAP, _we_ only record one
multiple_managers: {
    my $guard = Test::Socialtext::User->snapshot();
    my $acct  = Socialtext::Account->Default;
    my $ldap  = bootstrap_openldap(account => $acct);

    # update "Ariel Young"'s record in LDAP so that she's got *both*
    # Adrian and Belinda as manager.
    my $ariel_dn   = 'cn=Ariel Young,ou=related,dc=example,dc=com';
    my $belinda_dn = 'cn=Belinda King,ou=related,dc=example,dc=com';
    my $adrian_dn  = 'cn=Adrian Harris,ou=related,dc=example,dc=com';

    my $rc = $ldap->modify(
        $ariel_dn,
        replace => [
            manager => [
                $belinda_dn,
                $adrian_dn 
            ],
        ],
    );
    ok $rc, "LDAP updated to give ariel multiple managers"; 

    # instantiate "username => 'Ariel Young'"
    my $ariel = Socialtext::User->new(username => 'Ariel Young');
    ok $ariel, 'loaded Ariel user';

    my $belinda = Socialtext::User->new(username => 'Belinda King');
    ok $belinda, 'loaded Belinda user';

    # Check that only the first of the manager's is listed in her Profile
    my $ariel_profile = Socialtext::People::Profile->GetProfile($ariel, no_recurse=>1);
    is $ariel_profile->get_reln('supervisor'), $belinda->user_id,
        'Ariel has one manager even though multiple listed in LDAP';
}

###############################################################################
# TEST: *DON'T* recurse to find supervisors; create a Ceq job instead
recurse_asynchronously: {
    my $guard = Test::Socialtext::User->snapshot();
    my $acct  = Socialtext::Account->Default;
    my $ldap  = bootstrap_openldap(account => $acct);

    # Re-enable async lookup
    local $Socialtext::Pluggable::Plugin::People::Asynchronous=1;

    # Clear Ceq queue
    Socialtext::Jobs->clear_jobs();

    # Load up a User that has a Supervisor
    my $user = Socialtext::User->new(username => 'Ariel Young');
    ok $user, 'loaded User with a supervisor';

    # Check that the Supervisor is *NOT* linked into the Profile
    my $profile = Socialtext::People::Profile->GetProfile($user, no_recurse=>1);
    ok $profile, 'got People Profile';

    my $queried = $profile->get_reln('supervisor');
    ok !$queried, '... which has *NO* supervisor (yet)';

    # Check that a Ceq job was created to resolve the Supervisor
    my $job = Socialtext::Jobs->find_job_for_workers();
    ok $job, '... job was found to resolve Supervisor';
    is $job->funcname, 'Socialtext::Job::ResolveRelationship',
        '... ... which *is* a relationship resolver job';

    # Run the Ceq job
    my $rc = Socialtext::Jobs->work_once($job);
    ok $rc, '... job run';
    is $job->exit_status, 0, '... ... successfully';

    # Check that the Supervisor is now linked into the Profile
    my $supervisor = Socialtext::User->new(username => 'Adrian Harris');
    ok $supervisor, 'loaded Supervisor';

    $profile = Socialtext::People::Profile->GetProfile($user, no_recurse=>1);
    $queried = $profile->get_reln('supervisor');
    is $queried, $supervisor->user_id, '... which is the reln target';
}
