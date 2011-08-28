#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::More;

my @stringifiers = glob("lib/Socialtext/File/Stringify/*.pm");
plan tests => scalar @stringifiers;

for my $stringifier (@stringifiers) {
    my $ok = 1;
    open my $fh, $stringifier or die "Can't open $stringifier: $!";
    while (my $line = <$fh>) {
        if ($line =~ m{\b(shell_run|system)\b}) {
            $ok = 0;
            my ($name) = $stringifier =~ m{/([^/]+)\.pm$};
            diag "$name stringifier should use backtick on line $.\n";
            diag $line;
        }
    }
    ok $ok, $stringifier;
    close $fh;
}
