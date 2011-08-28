#!perl
# @COPYRIGHT@

use strict;
use warnings;

use mocked 'Apache::Cookie';
use Test::Socialtext tests => 2;
fixtures(qw( empty ));
use Test::Socialtext::CGIOutput;

{
    set_query('Edit%20in%20Place%20Phase%200');

    my ($error, $html) = get_action_output(
        new_hub('empty'), 'display', 'display');

    is($error, '', 'edit page load succeeds');
    like($html, qr/title>.*Edit in Place Phase 0\b/s, "proper title for page");
}
