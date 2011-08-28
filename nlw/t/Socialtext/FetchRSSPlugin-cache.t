#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext;
fixtures(qw( empty ));

my $url = 'http://www.burningchrome.com/~cdent/mt/index2.xml';
my $bogus_url = 'http://www.burningchrome/~cdent/mt/index3.xml';
my @tests = (
    [ "{fetchrss $url 0 3}" =>
    qr{Glacial Erratics}],
    [ "{fetchrss $bogus_url 0 3}" =>
    qr{There was an error: }],
);

my $test_count = scalar @tests + 6;
plan tests => $test_count;

my $hub = new_hub('empty');
my $viewer = $hub->viewer;
my $fetchrss = $hub->fetchrss;

SKIP: {
    skip "fetchrss accesses the network", $test_count
        unless ($ENV{NLW_TEST_FETCHRSS} || $ENV{NLW_TEST_NETWORK});
        
    # XXX \n needed to insure wafl is seen
    my $result = $viewer->text_to_html( $tests[0]->[0] . "\n");
    like( $result, $tests[0]->[1], $tests[0]->[0] . ' produced output');

    is($fetchrss->cache_dir, Socialtext::Paths::plugin_directory( $hub->current_workspace->name ),
        'cache_dir is correct');
    ok(defined($fetchrss->_get_cached_result($url)), 'cache file exists');

    my $cache_content = $fetchrss->_get_cached_result($url);
    like($cache_content, $tests[0]->[1], 'cache content contains good info');

    is($fetchrss->expire, 3, 'expire time is set to three seconds');
    sleep 3;

    $cache_content = $fetchrss->_get_cached_result($url);
    ok(!defined($cache_content), 'cache_content has expired');

    $result = $viewer->text_to_html( $tests[1]->[0] . "\n");
    like( $result, $tests[1]->[1], $tests[1]->[0] . ' produced second output');
    ok(!defined($fetchrss->_get_cached_result($url)),
        'content not cached on error');
}
