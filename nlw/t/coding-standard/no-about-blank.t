#!/usr/bin/evn perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::More tests => 1;
use Test::Differences;

SKIP: {
    skip 'No `ack` available', 1, unless `which ack` =~ /\w/;

    my @bad_files =
        grep { !m{no-about-blank.t} }
        `ack --follow --nocolor --all -l about:blank . | grep -v core`;
    is_deeply \@bad_files, [], 'No about:blank in our source code';
}
