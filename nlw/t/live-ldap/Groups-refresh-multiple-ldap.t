#!/user/bin/perl
# @COPYRIGHT@
use strict;
use warnings;

# This test exists to test out the scenario reported by an appliance customer
# and described in {bz: 3567}.

use Test::Socialtext tests => 11;
use Socialtext::Group;
use Test::Socialtext::Bootstrap::OpenLDAP;

fixtures('db');

my $class = 'Socialtext::Group';
use_ok $class;

# Set up _two_ LDAP servers.
my $ldap1 = Test::Socialtext::Bootstrap::OpenLDAP->new();
ok $ldap1->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added base_dn for ldap1';
ok $ldap1->add_ldif('t/test-data/ldap/people.ldif'),  '... people';
ok $ldap1->add_ldif('t/test-data/ldap/groups-groupOfNames.ldif'), '... groups';

my $ldap2 = Test::Socialtext::Bootstrap::OpenLDAP->new();
ok $ldap2->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added base_dn for ldap2';
ok $ldap2->add_ldif('t/test-data/ldap/people.ldif'),  '... people';
ok $ldap2->add_ldif('t/test-data/ldap/groups-moreGroupOfNames.ldif'), '... groups';

my ($motorhead_id, $sabbath_id);
{ # Two Groups: one from ldap1 and one from ldap2
    my $motorhead_dn = 'cn=Motorhead,dc=example,dc=com';
    my $sabbath_dn   = 'cn=Black Sabbath,dc=example,dc=com';

    my $motorhead = Socialtext::Group->GetGroup({
            driver_unique_id => $motorhead_dn});
    isa_ok $motorhead, 'Socialtext::Group', 'motorhead';
    $motorhead_id = $motorhead->group_id;


    my $sabbath = Socialtext::Group->GetGroup({
        driver_unique_id => $sabbath_dn});
    isa_ok $sabbath, 'Socialtext::Group', 'black sabbath';
    $sabbath_id = $sabbath->group_id;
}

{ # Make sure we can find the proto groups.
    my $proto_motorhead = Socialtext::Group->GetProtoGroup({
            group_id => $motorhead_id });
    ok $proto_motorhead, 'found proto motorhead group';

    my $proto_sabbath = Socialtext::Group->GetProtoGroup({
            group_id => $sabbath_id });
    ok $proto_sabbath, 'found proto sabbath group';
}

exit;
