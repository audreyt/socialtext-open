#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use IO::All;
use YAML;

my @skins = map {
    $_->filename;
} grep {
    "$_" !~ /\/(common|st)$/
} io('../..')->all_dirs;

unshift @skins, 's2';

@skins = map {
    my $text = $_;
    my $info = YAML::LoadFile("../../$_/info.yaml");
    if ($info->{abstract}) {
        $text .= ' - ' . $info->{abstract};
    }
    $text;
}
@skins;

my $skins = join ",\n", map { qq{"$_"} } @skins;
print <<"...";
AllSkins = [
    $skins
];
...
