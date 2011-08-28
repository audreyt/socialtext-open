#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 16;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Output qw(combined_from combined_like);
use Socialtext::LDAP::Operations;

###############################################################################
# Need a DB, doesn't matter if there's anything in it.
fixtures(qw( db ));

###############################################################################
# Sets up OpenLDAP, adds some test data, and adds the OpenLDAP server to our
# list of Group Factories.
sub set_up_openldap {
    my $groups_file = shift || 't/test-data/ldap/groups-groupOfNames.ldif';
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();

    $openldap->add_ldif('t/test-data/ldap/base_dn.ldif');
    $openldap->add_ldif('t/test-data/ldap/people.ldif');
    $openldap->add_ldif($groups_file) if (-e $groups_file);
    return $openldap;
}

###############################################################################
# TEST: List Groups for a specific LDAP Group Factory
with_a_driver: {
    my $openldap  = set_up_openldap();
    my $driver_id = $openldap->ldap_config->id();
    my $output    = combined_from(
        sub {
            Socialtext::LDAP::Operations->ListGroups( driver => $driver_id );
        },
    );
    like $output, qr/Factory: $driver_id/, 'Group list for this Driver';
    unlike $output, qr/Factory:.*Factory:/s, '... and only one Driver';

    my @groups = grep { /Group:/ } split /^/, $output;
    is scalar @groups, 5, '... containing correct number of Groups';
    like $output, qr/Group:\s+Circular A/, '... ... Circular A';
    like $output, qr/Group:\s+Circular B/, '... ... Circular B';
    like $output, qr/Group:\s+Hawkwind/,   '... ... Hawkwind';
    like $output, qr/Group:\s+Motorhead/,  '... ... Motorhead';
    like $output, qr/Group:\s+With Hash/,  '... ... WithHash';
}

###############################################################################
# TEST: List Groups for _multiple_ LDAP Group Factories
without_a_driver: {
    my $openldap1  = set_up_openldap();
    my $driver_id1 = $openldap1->ldap_config->id();

    my $openldap2  = set_up_openldap('t/test-data/ldap/groups-moreGroupOfNames.ldif');
    my $driver_id2 = $openldap2->ldap_config->id();

    my $output = combined_from(
        sub {
            Socialtext::LDAP::Operations->ListGroups();
        },
    );

    like $output, qr/Factory: $driver_id1/, 'List contains first Factory';
    like $output, qr/Group: Motorhead/, '... and a Group from first Factory';

    like $output, qr/Factory: $driver_id2/, 'List contains second Factory';
    like $output, qr/Group: Black Sabbath/, '... and a Group from second Factory';
}

###############################################################################
# TEST: List Groups with invalid Group Factory
with_an_invalid_driver: {
    my $openldap = set_up_openldap();
    my $output   = combined_like(
        sub {
            Socialtext::LDAP::Operations->ListGroups( driver => 'ENOSUCH' );
        },
        qr/No factory for Driver 'ENOSUCH'/,
        'Displays error on unknown LDAP Group Factory driver',
    );
}

###############################################################################
# TEST: List Groups from an *empty* LDAP Group Factory
with_no_groups: {
    # Bootstrap OpenLDAP, but *without* any Groups in it (although it *is*
    # still configured as an LDAP Group Factory).
    my $openldap  = set_up_openldap('bogus-groups-file');
    my $driver_id = $openldap->ldap_config->id();

    my $output = combined_from(
        sub {
            Socialtext::LDAP::Operations->ListGroups();
        },
    );

    like $output, qr/Factory: $driver_id/, 'List contains empty Group Factory';
    unlike $output, qr/Group:/,          '... which has *no* Groups in it';
    like $output,   qr/No Groups found/, '... and which displays warning';
}
