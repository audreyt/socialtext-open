#!perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 12;
use Sys::Hostname;

fixtures(qw( clean populated_rdbms destructive ));

BEGIN {
    use_ok( 'Socialtext::Account' );
}

# Delete the per-hostname account to make the ordering of these
# tests much simpler.  Otherwise they would depend on the hostname.
my $hostname = hostname();
eval {
    Socialtext::Account->new(name => $hostname)->delete;
};

Search: {
    my @search_tests = (
        {
            desc => 'search',
            args => { name => 'Social' },
            results => ['Socialtext'],
        },
        {
            desc => 'search - case sensitive',
            args => { name => 'social' },
            results => [],
        },
        {
            desc => 'search - case insensitive',
            args => { name => 'social', case_insensitive => 1 },
            results => ['Socialtext'],
        },
        {
            desc => 'search - case insensitive',
            args => { name => 'sOcIaL', case_insensitive => 1 },
            results => ['Socialtext'],
        },
        {
            desc => 'search - case insensitive',
            args => { name => 'THER', case_insensitive => 1 },
            results => ['Other 1', 'Other 2'],
        },
    );
    for my $s (@search_tests) {
        my $accounts = Socialtext::Account->ByName( %{ $s->{args} } );
        is_deeply(
            [ map { $_->name } $accounts->all() ],
            $s->{results},
            $s->{desc},
        );
        is( Socialtext::Account->CountByName( %{ $s->{args} } ), 
            scalar(@{ $s->{results} }), 
            'count matches'
        );
    }

    Search_through_all: {
        my $args = { name => 'sOcIaL', case_insensitive => 1 };
        my $accounts = Socialtext::Account->All( %$args );
        is_deeply(
            [ map { $_->name } $accounts->all() ],
            ['Socialtext'],
            'Searching through All()',
        );
    }
}
