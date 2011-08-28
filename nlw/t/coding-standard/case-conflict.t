#!/usr/bin/env perl
# @COPYRIGHT@

# Checks that there are no files that differ from others only by case.
# This protects us from problems in case-insensitive filesystems, as in 
# HFS+ on Mac OS X.

use strict;
use warnings;
use Test::More;

use File::Find;

my @dirs;

find( sub { push @dirs, $File::Find::name if -d }, '.' );
@dirs = grep { !/\.svn/ } @dirs;
plan tests => scalar @dirs;

check_dir($_) for @dirs;

sub check_dir {
    my $dir = shift;

    my @files = glob( "$dir/*" );

    my %lc;
    for ( @files ) {
        push( @{$lc{lc $_}}, $_ );
    }
    my @conflicts = grep { @{$lc{$_}} > 1 } keys %lc;
    if ( @conflicts ) {
        diag "Case conflict in $dir";
        for my $conflict ( @conflicts ) {
            diag "\t$_" for @{$lc{$conflict}};
        }
        fail( $dir );
    }
    else {
        pass( $dir );
    }
}
