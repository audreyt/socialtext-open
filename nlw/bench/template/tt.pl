#!/usr/bin/env perl
# @COPYRIGHT@
use warnings;
use strict;

use Template;

my $iters = shift || 1;
my @list_items = qw(alpha beta gamma);

my $t = Template->new({INCLUDE_PATH => '.',
                       COMPILE_DIR => '/tmp/nlw-bench-tt2-data',
                       COMPILE_EXT => '.compiled'});

my %vars = (
    foo => 'bar',
    baz => 'quux',
    title => 'Test page',
    list => \@list_items,
);

for (1 .. $iters) {
    $t->process('templ.tt2', \%vars);
}

