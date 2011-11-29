#!/usr/bin/env perl
use strict;
use Module::Build::JSAN;

my $build = Module::Build::JSAN->new(
    module_name    => 'Widget-Balloon',
    license        => 'perl',
    dist_author    => 'Kang-min Liu <gugod@gugod.org>',
    dist_abstract  => 'Generate pop-up balloons above objects as a hint.',
    dist_version   => '0.02',
    keywords       => [qw(Widget Balloon)],
   );

$build->create_build_script;
