#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::More tests => 1;

Tests_without_plan: {
    my $np = join('_', 'no', 'plan'); # obfuscate
    my @without_plans = qx(find t -name *.t | xargs grep -l $np);
    chomp @without_plans;
    is_deeply [ sort @without_plans ], [], 'all tests have a plan';
}
