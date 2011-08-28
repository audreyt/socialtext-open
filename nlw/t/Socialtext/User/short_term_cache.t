#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings FATAL => 'all';
use Test::More tests => 30;
use mocked 'Socialtext::Log', qw(:tests);
use mocked 'Net::LDAP';
use Test::Socialtext;

fixtures( 'ldap_anonymous' );
use_ok 'Socialtext::User::LDAP::Factory';
use_ok 'Socialtext::User::Default::Factory';

my @TEST_LDAP_USERS = (
    { dn            => 'cn=user,dc=example,dc=com',
      cn            => 'FirstLDAP LastLDAP',
      authPassword  => 'abc123',
      gn            => 'FirstLDAP',
      sn            => 'LastLDAP',
      mail          => 'ldapuser@example.com',
    },
    { dn            => 'cn=user,dc=example,dc=com',
      cn            => 'Another LDAPUser',
      authPassword  => 'def987',
      gn            => 'Another',
      sn            => 'LDAPUser',
      mail          => 'ldapuser@example.com',
    },
);


my $appconfig = Socialtext::AppConfig->new();
$appconfig->set('user_factories', 'LDAP;Default');
$appconfig->write();
is (Socialtext::AppConfig->user_factories(), 'LDAP;Default');

Socialtext::User->create(
    email_address => 'dbuser@example.com',
    username => 'dbuser@example.com',
    first_name => 'DB',
    last_name => 'User',
    password => 'password',
);

sub set_names {
    my ($username, $first, $last) = @_;
    # done in an external process, so that its *not* using any in-memory cache
    my $rc = system("st-admin set-user-names --username $username --first-name $first --last-name $last > /dev/null");
    ok !$rc;
}

# Explicitly *DISABLE* the long-term cache used by the LDAP Factory.
#
# This is done *solely* for instrumentation purposes; we want to make sure
# that when we get past the short-term cache that we're able to see that the
# user lookup got down as far as the actual LDAP directory.
#
# With this long-term LDAP cache disabled, we *don't* have to worry about
# expiring users (which not only marks them as expired but also flushes them
# from the short-term cache automatically).  Instead, we just turn the
# long-term cache off; no need to cache-bust then.
{
    no warnings 'once';
    $Socialtext::User::LDAP::Factory::CacheEnabled = 0;
    $Socialtext::User::User::Factory::CacheEnabled = 0;
}

verify_not_caching_is_the_default_behaviour: {
    # Flush LDAP Connection Cache before starting test
    Socialtext::LDAP->ConnectionCache->clear();

    # get a user from LDAP, and verify who they are
    Net::LDAP->set_mock_behaviour(
        search_results => [ $TEST_LDAP_USERS[0] ],
    );
    my $user = Socialtext::User->new(email_address => 'ldapuser@example.com');
    ok $user;
    is $user->best_full_name, "FirstLDAP LastLDAP", "original ldap user bfn";

    # go get the user again, and make sure that we actually went all the way
    # back to LDAP to get them, showing that we haven't cached them in memory.
    Net::LDAP->set_mock_behaviour(
        search_results => [ $TEST_LDAP_USERS[1] ],
    );
    my $user2 = Socialtext::User->new(email_address => 'ldapuser@example.com');
    ok $user2;
    is $user2->best_full_name, "Another LDAPUser", "non-cached ldap user bfn";

    # turn off LDAP results (so it doesn't give us a fake mocked response
    # first), and go get a Default user.  Update that user, go get them again,
    # and make sure we got the updated version; we didn't pull them from any
    # short-term cache in memory.
    Net::LDAP->set_mock_behaviour(search_results => []);
    set_names('dbuser@example.com', qw(DB User));

    my $user3 = Socialtext::User->new(username => 'dbuser@example.com');
    ok $user3;
    is $user3->best_full_name, "DB User", "original db user bfn";

    set_names('dbuser@example.com', qw(AnotherDB User));

    my $user4 = Socialtext::User->new(username => 'dbuser@example.com');
    ok $user4;
    is $user4->best_full_name, "AnotherDB User", "non-cached db user bfn";
}

verify_caching_behaviour: {
    # Flush LDAP Connection Cache before starting test
    Socialtext::LDAP->ConnectionCache->clear();

    # Turn *ON* our short-term in-memory cache.
    no warnings 'once';
    local $Socialtext::User::Cache::Enabled = 1;

    # get a user from LDAP, and verify who they are
    Net::LDAP->set_mock_behaviour(
        search_results => [ $TEST_LDAP_USERS[0] ],
    );
    my $user = Socialtext::User->new(email_address => 'ldapuser@example.com');
    ok $user;
    is $user->best_full_name, "FirstLDAP LastLDAP", "original ldap user bfn";

    # go get the user again, this time expecting that we've used the
    # short-term in memory cache and have *not* gone back to LDAP to get the
    # user again.
    Net::LDAP->set_mock_behaviour(
        search_results => [ $TEST_LDAP_USERS[1] ],
    );
    my $user2 = Socialtext::User->new(email_address => 'ldapuser@example.com');
    ok $user2;
    is $user2->best_full_name, "FirstLDAP LastLDAP", "cached ldap user bfn";
    my $ldap_user_id = $user2->user_id;

    # turn off LDAP results (so it doesn't give us a fake mocked response
    # first), and go get a Default user.  Update that user, go get them again,
    # and make sure that we got the *cached* version (and didn't get the
    # updates).
    Net::LDAP->set_mock_behaviour(search_results => []);
    set_names('dbuser@example.com', qw(DB User));

    my $user3 = Socialtext::User->new(username => 'dbuser@example.com');
    ok $user3;
    is $user3->best_full_name, "DB User", "original db user bfn";

    set_names('dbuser@example.com', qw(AwesomeDB User));

    my $user4 = Socialtext::User->new(username => 'dbuser@example.com');
    ok $user4;
    is $user4->best_full_name, "DB User", "cached db user bfn";
    my $db_user_id = $user4->user_id;

    proactive_user_id_caching: {
        my $user5 = Socialtext::User->new(user_id => $ldap_user_id);
        ok $user5;
        is $user5->best_full_name, "FirstLDAP LastLDAP", "proactive cache of the LDAP user";

        my $user6 = Socialtext::User->new(user_id => $db_user_id);
        ok $user6;
        is $user6->best_full_name, "DB User", "proactive cache of the db user";
    }

    lookup_of_non_existant_user: {
        my $user7 = Socialtext::User->new(email_address => 'notyet@example.com');
        ok !$user7, "this user doesn't exist yet";

        # in another process:
        system('st-admin create-user --email notyet@example.com --username notyet@example.com --first-name Iam --last-name Here --password password');
        my $user8 = Socialtext::User->new(email_address => 'notyet@example.com');
        ok $user8;
        is $user8->best_full_name, "Iam Here", "previous cache miss didn't poison the cache";
    }
}
