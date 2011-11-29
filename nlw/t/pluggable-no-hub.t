#!/usr/bin/env perl
# @COPYRIGHT@
use 5.12.0;
use warnings;

use Test::More;

my @plugins = grep { !m{/(?:Default|CSSKit)\.pm$} }
              glob("lib/Socialtext/Pluggable/Plugin/*.pm");

plan tests => scalar @plugins;

for my $plugin (@plugins) {
    my ($name) = $plugin =~ m{/([^/]+)\.pm$};
    my $ok = 1;
    open my $fh, $plugin or die "Can't open $plugin: $!";
    while (<$fh>) {
        if (m{(\S*->hub\S*)}) {
            $ok = 0;
            diag "$name plugin uses the hub directly: $1";
        }
    }
    local $TODO = "The $name plugin intentionally uses ->hub (for now), instead of contributing to the plugin architecture"
        if $name ~~ [qw[ Push Like Analytics CKEditor Homepage ]];
    ok $ok, $plugin;
    close $fh;
}
