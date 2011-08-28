#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use DateTime;
use Socialtext::Group::Factory;
use Socialtext::JobCreator;
use Socialtext::Jobs;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext::Group;
use Test::Socialtext tests => 20;

# Need a DB, but don't care at all what's in it.
# Don't want any leftover Ceq jobs.
fixtures( qw/db no-ceq-jobs/ );

use_ok 'Socialtext::Job::GroupIndex';

# Register workers
Socialtext::Jobs->can_do('Socialtext::Job::GroupIndex');

################################################################################
# TEST: LDAP group w/expired cache.
ldap_group: {
    my $ldap = bootstrap_openldap();

    # Vivify the group, schedule the job.
    my $group = Socialtext::Group->GetGroup(
        { driver_unique_id => 'cn=Motorhead,dc=example,dc=com' } );
    isa_ok $group, 'Socialtext::Group', 'got a group';
    is $group->users->count, 0, '... no users have been added to the group';

    # Force run the job.
    my $job = Socialtext::Jobs->find_job_for_workers();
    ok $job, '... job found.';
    my $rc = Socialtext::Jobs->work_once($job);
    ok $rc, '... job completed';
    is $job->exit_status, 0, '... ... successfully';

    # Cleanup
    Test::Socialtext::Group->delete_recklessly($group);
}

################################################################################
# TEST: LDAP group is freshened again before job is called.
ldap_group_freshened: {
    my $ldap = bootstrap_openldap();

    # Vivify the group, schedule the job.
    my $group = Socialtext::Group->GetGroup(
        { driver_unique_id => 'cn=Motorhead,dc=example,dc=com' } );
    isa_ok $group, 'Socialtext::Group', 'got a group';
    isa_ok $group->homunculus, 'Socialtext::Group::LDAP', '...';
    is $group->users->count, 0, '... no users have been added to the group';

    # Force an update of the group, still no users. Sleep so that we force the
    # jobs to queue in the right order.
    local $Socialtext::Group::Factory::CacheEnabled = 0;
    my $forced = Socialtext::Group->GetGroup(
        { driver_unique_id => 'cn=Motorhead,dc=example,dc=com' } );
    ok $forced->cached_at->hires_epoch > $group->cached_at->hires_epoch,
        '... group was force refreshed.';
    is $forced->users->count, 0, '... still no users';
    local $Socialtext::Group::Factory::CacheEnabled = 1;

    # Run the jobs.
    my $job = Socialtext::Jobs->find_job_for_workers();
    ok $job, 'first job found.';
    my $rc = Socialtext::Jobs->work_once($job);
    ok $rc, '... first job completed';
    is $job->exit_status, 0, '... ... successfully';

    # Cleanup
    Test::Socialtext::Group->delete_recklessly($group);
}

exit;
################################################################################
sub bootstrap_openldap {
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'),  'added people';
    ok $openldap->add_ldif('t/test-data/ldap/groups-groupOfNames.ldif'), 'added groups';
    return $openldap;
}
