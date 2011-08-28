#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::More tests => 2;
use Socialtext::File qw/set_contents/;

# Test Setup - create a test plugin so we find at least one thing.
# More plugins may be found, so manually search for them.
BEGIN {
    my $test_module = "lib/Socialtext/Plugin/Test.pm";
    mkdir "lib/Socialtext/Plugin"; # just in case
    set_contents($test_module, "package Socialtext::Plugin::Test;\n1;\n");
    END { unlink $test_module }

    use_ok 'Socialtext::Plugin';
}

Load_plugins: {
    my %plugins = map { $_ => 1 } Socialtext::Plugin->plugins();
    my %found_plugins = map { s#^lib/##; s#/#::#g; s/\.pm//; $_ => 1 }
                        glob("lib/Socialtext/Plugin/*.pm");
    is_deeply \%plugins, \%found_plugins;
}
