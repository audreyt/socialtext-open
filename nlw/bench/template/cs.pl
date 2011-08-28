#!/usr/bin/env perl
# @COPYRIGHT@
use warnings;
use strict;

use ClearSilver;

my $iters = shift || 1;
my @list_items = qw(alpha beta gamma);

my $hdf = ClearSilver::HDF->new;
$hdf->setValue(foo => 'bar');
$hdf->setValue(baz => 'quux');
$hdf->setValue(title => 'Test page');
for (my $ii = 0; $ii <= $#list_items; ++$ii) {
    $hdf->setValue("list.$ii" => $list_items[$ii]);
}

my $template = <<'EOT';
<html>
    <head>
        <title><?cs var:title ?></title>
    </head>
    <body>
        <h1><?cs var:title ?></h1>
        <hr/>
        <ul>
        <?cs each:item = list ?>
            <li> <?cs var:item ?> </li>
        <?cs /each ?>
        </ul>
        <hr/>
        <em><?cs var:foo ?> <?cs var:baz ?></em>
    </body>
</html>
EOT

for (1 .. $iters) {
    my $cs = ClearSilver::CS->new($hdf);
    $cs->parseString($template);
    print $cs->render;
}
