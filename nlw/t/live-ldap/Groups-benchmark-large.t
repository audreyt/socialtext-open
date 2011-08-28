#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use File::Slurp qw(write_file);
use Benchmark qw(timeit timestr);
use Socialtext::SQL qw(:exec);
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext;
use Socialtext::Timer;
use Socialtext::AppConfig;

###############################################################################
# Skip this test entirely unless we're explicitly running benchmark tests.
unless ($ENV{NLW_BENCHMARK}) {
    warn 'Set NLW_BENCHMARK=1 to run; this perf test takes ~30-45mins to run.';
    plan tests => 1;
    ok 1, 'Nothing to do here.';
    exit;
}
plan tests => 8;

###############################################################################
# Set the cache/async job settings for this benchmark.
{
    no warnings 'once';

    require Socialtext::User::Cache;
    $Socialtext::User::Cache::Enabled=1;            # turn on User cache

    require Socialtext::Group::Factory;
    $Socialtext::Group::Factory::CacheEnabled=1;    # turn on Group cache
    $Socialtext::Group::Factory::Asynchronous=0;    # in-process Group lookups
}

###############################################################################
# Fixture: clean db destructive
# - Need a *CLEAN* DB to start
# - We're *DESTRUCTIVE*; we're going to create gobs of crap in the DB, so
#   don't risk having _any_ of that get passed along to another test
fixtures(qw( clean db destructive ));

###############################################################################
# Temp file to hold the LDIF we generate for the benchmark.
my $test_dir = Socialtext::AppConfig->test_dir();
our $LDIF_FILE = "$test_dir/group-perf.$$.ldif";

###############################################################################
# Create an LDIF file that contains a data set with a LARGE number of Users in
# it, that coalesce together into a single large "Staff" Group.
my $CHUNK = 5000;
my @group_dns = _make_ldif( $LDIF_FILE,
    [ 'Management'  => $CHUNK ],
    [ 'Development' => $CHUNK ],
    [ 'QA'          => $CHUNK ],
    [ 'Sales'       => $CHUNK ],
    [ 'Marketing'   => $CHUNK + 1 ],  # with add to make it testable later
    [ 'Partners'    => $CHUNK + 3 ],  # with add to make it testable later
);
my $partner_dn   = pop @group_dns;
my $marketing_dn = pop @group_dns;

###############################################################################
# Bootstrap OpenLDAP, with debug logging *minimized* (otherwise, OpenLDAP
# takes a LOOONNNGGGG time to do stuff as its firehosing to disk).
my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new(
    debug_level => 512
);

###############################################################################
# Feed the LDIF file into OpenLDAP
ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'fed base_dn to LDAP';
ok $openldap->add_ldif('t/test-data/ldap/people.ldif'),  'fed people to LDAP';

diag "Adding Users/Groups to OpenLDAP";
my $t = timeit( 1, sub {
    $openldap->add_ldif($LDIF_FILE);
} );
diag "... " . timestr($t);

###############################################################################
# Create a "Staff" Group manually, which contains several of the sub-Groups as
# members.
my $staff_dn = "cn=Staff,dc=example,dc=com";
my $rc = $openldap->add( $staff_dn,
    cn          => 'Staff',
    objectClass => 'groupOfNames',
    member      => [ @group_dns, $marketing_dn ],
);
ok $rc, 'Created Staff Group in OpenLDAP';

###############################################################################
# Vivify/instantiate the "Staff" Group, importing it into ST
vivify_staff_group: {
    # clear LDAP connection cache
    Socialtext::LDAP->ConnectionCache->clear();

    # Vivify the Staff Group
    my $staff_group;
    diag "Vivifying Staff Group into ST";
    $t = timeit( 1, sub {
        $staff_group = Socialtext::Group->GetGroup( driver_unique_id => $staff_dn );
    } );
    diag "... " . timestr($t);

    my $expected = (4 * $CHUNK) + ($CHUNK + 1);

    # Estimate speed of load
    my $users_per_sec = sprintf( '%0.2f', $expected / $t->real );
    diag "... loaded at rate of $users_per_sec Users/sec";

    # Sanity check the Group
    isa_ok $staff_group, 'Socialtext::Group', 'Staff Group';

    is $staff_group->users->count, $expected,
        "... with correct number of Users ($expected)";

    # Expire the Group, so that subquent lookups cause it to be refreshed
    $staff_group->expire();
}

###############################################################################
# Update "Staff", changing membership around a bit; add one Group, remove
# another.
update_staff_group: {
    my $rc = $openldap->modify( $staff_dn,
        replace => [
            member => [@group_dns, $partner_dn],
        ],
    );
    ok $rc, 'Modified Staff Group';
}

###############################################################################
# Re-vivify the "Staff" Group, causing it to get refreshed from LDAP.
revivify_staff_group: {
    # clear LDAP connection cache
    Socialtext::LDAP->ConnectionCache->clear();

    # Re-vivify the Staff Group
    my $staff_group;
    diag "Re-vivify updated Staff Group";
    $t = timeit( 1, sub {
        $staff_group = Socialtext::Group->GetGroup( driver_unique_id => $staff_dn );
    } );
    diag "... " . timestr($t);

    my $expected = (4 * $CHUNK) + ($CHUNK + 3);

    # Estimate speed of refresh
    my $users_per_sec = sprintf( '%0.2f', $expected / $t->real );
    diag "... refreshed at rate of $users_per_sec Users/sec";

    # Sanity check the Group
    isa_ok $staff_group, 'Socialtext::Group', 'Staff Group';

    is $staff_group->users->count, $expected,
        "... with correct number of Users ($expected)";
}

###############################################################################
# CLEANUP: Force nuke the users/groups tables in the DB, and remove tmp files.
cleanup: {
    sql_execute( qq{ DELETE FROM groups WHERE driver_key ~* 'LDAP' } );
    sql_execute( qq{ DELETE FROM users  WHERE driver_key ~* 'LDAP' } );
    unlink $LDIF_FILE;
}

###############################################################################
# Dump Socialtext Timer report, so we've got some idea where all the time was
# spent.
diag "\nSocialtext::Timer report\n";
my $report = Socialtext::Timer->Report();
foreach my $key (sort { $report->{$b} <=> $report->{$a} } keys %{$report}) {
    my $str = sprintf( '%30s => %0.4f', $key, $report->{$key} );
    diag $str;
}

###############################################################################
# All done.
exit;






###############################################################################
# Create an LDIF file containing a number of Groups with Users.  Returns the
# DNs for the Groups that have been created.
my $counter = 0;
sub _make_ldif {
    my ($file, @base_groups) = @_;
    my @group_dns;
    my $ldif = '';

    while (@base_groups) {
        my ($group_name, $user_count) = @{ shift @base_groups };
        my ($group_dn, $group_ldif)   = _make_ldif_group($group_name);

        for (1 .. $user_count) {
            my ($user_dn, $user_ldif) = _make_ldif_user($counter++);

            # Add LDIF for User to final LDIF
            $ldif .= "$user_ldif\n";

            # Add User as member of this Group
            $group_ldif .= "member: $user_dn\n";
        }

        # Add LDIF for Group to final LDIF
        $ldif .= "$group_ldif\n";
        push @group_dns, $group_dn;
    }

    # Write the LDIF out to file
    write_file($file, $ldif);

    # Return the list of Group DNs
    return @group_dns;
}

###############################################################################
# Returns the ($dn, $ldif) for a new Group, based on the provided $cn.
sub _make_ldif_group {
    my $cn = shift;
    my $dn = "cn=$cn,dc=example,dc=com";
    my $ldif = qq{
dn: $dn
objectClass: groupOfNames
cn: $cn
};
    return ($dn, $ldif);
}

###############################################################################
# Returns the ($dn, $ldif) for a new User, based on the provided $counter.
sub _make_ldif_user {
    my $counter = shift;
    my $cn      = "User $counter";
    my $dn      = "cn=$cn,dc=example,dc=com";
    my $email   = "user-$counter\@ken.socialtext.net";

    my $ldif = qq{
dn: $dn
objectClass: inetOrgPerson
cn: $cn
gn: User
sn: $counter
mail: $email
};
    return ($dn, $ldif);
}
