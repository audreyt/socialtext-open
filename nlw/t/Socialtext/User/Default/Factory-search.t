#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 15;
use Socialtext::User;

fixtures(qw( clean db ));
use_ok 'Socialtext::User::Default::Factory';

###############################################################################
### CREATE TEST DATA
###############################################################################
my $user = Socialtext::User->create(
    username        => 'test user',
    first_name      => 'Test',
    last_name       => 'User',
    email_address   => 'devnull@socialtext.net',
    password        => 'password',
    );
isa_ok $user, 'Socialtext::User', 'created test user';

###############################################################################
# Search; empty search should return empty handed
search_empty_should_return_empty_handed: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';

    my @users = $factory->Search();
    is scalar(@users), 0, 'search w/empty terms should be empty handed';
}

###############################################################################
# Search; no results
search_no_results: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';

    my @users = $factory->Search('foo');
    is scalar(@users), 0, 'search w/no results has correct number of results';
}

##############################################################################
# Search; single result
search_single_result: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';

    # find user, with match to known username
    my @users = $factory->Search('test');
    is scalar(@users), 1, 'search w/single result has correct number of results';
}

###############################################################################
# Search; internal sanity checks
search_sanity_checks: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';

    # find user, with match to known email address
    my @users = $factory->Search('devnull');
    is scalar(@users), 1, 'got search results';

    # check format/content of results;
    my $user = shift @users;
    isa_ok $user, 'HASH', '... search results are plain hash-refs';
    is scalar(keys(%{$user})), 3, '... has right number of keys';
    is $user->{driver_name}, $factory->driver_name(), '... result key: driver_name';
    is $user->{email_address}, 'devnull@socialtext.net', '... result key: email_address';
    is $user->{name_and_email}, 'Test User <devnull@socialtext.net>', '... result key: name_and_email';
}
