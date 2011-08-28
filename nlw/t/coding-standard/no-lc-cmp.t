#!/usr/bin/evn perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::More tests => 1;
use Test::Differences;

SKIP: {
    skip 'No `ack` available', 1, unless `which ack` =~ /\w/;

    my @bad_files =
        grep { !m{no-lc-cmp.t} }
        `ack --follow --nocolor -l 'lc\\b.*\\bcmp\\b' . | grep -v core`;
    is_deeply \@bad_files, [], 'No "lc $a cmp lc $b" in our source code; use lsort or lcmp from Socialtext::l10n instead';
}
