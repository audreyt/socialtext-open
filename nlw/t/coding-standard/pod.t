#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::More;

BEGIN {
    unless ( eval "use Test::Pod 0.95;
                   use File::Find::Rule 0.24; 1;" ) {
        plan skip_all
            => 'These tests require Test::Pod >= 0.95 and File::Find::Rule >= 0.24';
    }
}

Test::Pod->import();


my $startpath = ".";

# From http://use.perl.org/~richardc/journal/6660
my $rule = File::Find::Rule->new;
$rule->or( $rule->new->directory->name('.svn')->prune->discard,
           $rule->new->file->name('*.pl','*.pm','*.t') );
my @files = $rule->in( $startpath );

my $nfiles = scalar @files;
die "No files found!" unless @files;

plan( tests => $nfiles );

for my $filename ( @files ) {
    pod_file_ok( $filename );
}
