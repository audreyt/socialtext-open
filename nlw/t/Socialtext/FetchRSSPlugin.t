#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use mocked 'Socialtext::Hub';
use Socialtext::File qw/get_contents/;
use Test::Socialtext;

my $have_net_access;
BEGIN {
    $have_net_access = $ENV{NLW_TEST_FETCHRSS} || $ENV{NLW_TEST_NETWORK};
    my $tests = 7;
    my $net_tests = $have_net_access ? 1 : 0;
    plan tests => $tests + $net_tests;
    use_ok 'Socialtext::FetchRSSPlugin';
}

fixtures(qw( db ));

my $testcases = [
    { 
        desc => 'Movable type rss',
        file => 'movable-type',
        matches => [
            qr/Glacial Erratics/,
        ],
    },
    { 
        desc => 'caching does not blow up',
        file => 'movable-type',
        matches => [
            qr/Glacial Erratics/,
        ],
    },
    { 
        desc => 'html should not parse',
        file => 'html',
        error => qr/Cannot detect feed type/,
    },
    { 
        desc => 'atom wafl',
        file => 'atom',
        matches => [ qr/iraq - Google News/ ],
    },
    { 
        desc => 'fix absolute links',
        file => 'not-absolute-links',
        matches => [
            qr#\Q<a href="http://foo/index.cgi/Grep/log">Revision Log - </a>\E#,
            qr#\Q<a href="http://foo/index.cgi/Grep/revision?rev=160">\E#,
        ],
    },
];

if ($have_net_access) {
    push @$testcases, {
        desc => 'fetch 404',
        # use the real _get_content for this test
        get_content => \&Socialtext::FetchRSSPlugin::_get_content,
        feed_url => 'http://www.example.com/wontwork',
        error => qr/404 Not Found/,
    };
}

feed_tester($_) for @$testcases;
exit;

sub feed_tester {
    my $p = shift;

    no warnings 'redefine';
    local *Socialtext::FetchRSSPlugin::_get_content = $p->{get_content} || sub {
        return get_contents("t/test-data/rss/$p->{file}");
    };

    my $mock_hub = Socialtext::Hub->new;
    my $fetchrss = Socialtext::FetchRSS::Wafl->new( 
        hub => $mock_hub,
        arguments => $p->{feed_url} || 'http://foo/rss full',
    );
    my $html = $fetchrss->html;
    for my $r ( @{ $p->{matches} } ) {
        like $html, $r, $p->{desc};
    }

    if ($p->{error}) {
        like $mock_hub->fetchrss->error, $p->{error}, $p->{desc};
    }
}

