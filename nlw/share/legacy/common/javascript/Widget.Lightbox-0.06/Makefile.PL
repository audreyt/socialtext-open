#!/usr/bin/env perl
use strict;
use Module::Build::JSAN;

my $build = Module::Build::JSAN->new(
    module_name => 'Widget.Lightbox',
    license     => 'perl',
    keywords    => [qw(Widget Lightbox)],
    requires    => { 'JSAN' => 0.10 },
);

$build->create_build_script;
