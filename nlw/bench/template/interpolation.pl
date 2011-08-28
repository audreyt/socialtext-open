#!/usr/bin/env perl
# @COPYRIGHT@
use warnings;
use strict;

my $iters = shift || 1;
my @list_items = qw(alpha beta gamma);

my %config = (
    foo => 'bar',
    baz => 'quux',
    title => 'Test page',
    list => \@list_items,
);

for (1 .. $iters) {
    my $list = join '', map { "<li>$_</li>\n" } @{$config{list}};
    my $result = <<"EOHTML";
<html>
    <head>
        <title>$config{title}</title>
    </head>
    <body>
        <h1>$config{title}</h1>
        <hr/>
        <ul>
$list
        </ul>
        <hr/>
        <em>$config{foo} $config{baz}</em>
    </body>
</html>
EOHTML
}

