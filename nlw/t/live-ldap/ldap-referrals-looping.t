#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use File::Slurp qw(write_file);
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 8;
use Socialtext::AppConfig;

###############################################################################
# FIXTURE: db
#
# Need Pg running, but we don't care what's in it.
fixtures( 'db' );

###############################################################################
# Figure out what test directory we're running under.
my $test_dir = Socialtext::AppConfig->test_dir();

###############################################################################
# bootstrap a pair of OpenLDAP servers
my $lhs = Test::Socialtext::Bootstrap::OpenLDAP->new();
isa_ok $lhs, 'Test::Socialtext::Bootstrap::OpenLDAP', 'referral LHS';

my $rhs = Test::Socialtext::Bootstrap::OpenLDAP->new();
isa_ok $rhs, 'Test::Socialtext::Bootstrap::OpenLDAP', 'referral RHS';

###############################################################################
# generate some LDIF data that'll put the LDAP servers in an infinite referral
# loop, and add that data to the directories
generate_ldif("$test_dir/recurse-lhs.ldif", $rhs->host(), $rhs->port());
ok $lhs->add_ldif("$test_dir/recurse-lhs.ldif"), 'added recursing LDIF to LHS';

generate_ldif("$test_dir/recurse-rhs.ldif", $lhs->host(), $lhs->port());
ok $rhs->add_ldif("$test_dir/recurse-rhs.ldif"), 'added recursing LDIF to RHS';

###############################################################################
# remove the LDAP config for the referral *target*; we only need one of these
# to be present in the config in order to trigger the referral loop.
$rhs->remove_from_user_factories();
$rhs->remove_from_ldap_config();

###############################################################################
# TEST: Authenticate, with looping LDAP referrals; should fail
authenticate_looping_referrals: {
    diag "TEST: authenticate_looping_referrals";
    clear_log();

    # find user; should fail
    my $user = Socialtext::User->new( username => 'John Doe' );
    ok !$user, 'did not find user';

    # make sure we failed because of looping referrals
    logged_like 'warning', qr/max referral depth/, '... due to max referral depth being reached';
}

###############################################################################
# TEST: Search, with looping LDAP referrals; should fail
search_looping_referrals: {
    diag "TEST: search_looping_referrals";
    clear_log();

    # search for users; should return empty handed
    my @users = Socialtext::User->Search('john');
    ok !@users, 'no users returned from search';

    # make sure we failed because of looping referrals
    logged_like 'warning', qr/max referral depth/, '... due to max referral depth being reached';
}





###############################################################################
### Helper method to generate LDIF files, and auto-remove them when we're done.
###############################################################################
my @files_to_remove;
END { unlink @files_to_remove; }

sub generate_ldif {
    my ($file, $host, $port) = @_;
    write_file $file, qq{
dn: dc=example,dc=com
objectClass: dcObject
objectClass: referral
dc: example
ref: ldap://${host}:${port}/dc=example,dc=com
};
    push @files_to_remove, $file;
}
