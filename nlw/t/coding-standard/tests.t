#!perl
# @COPYRIGHT@

# Check all the *.t files for shebangs, warnings and strict.

use warnings;
use strict;

use Test::More;
use File::Slurp qw( read_file );

BEGIN {
    eval 'use File::Next 0.30';
    plan skip_all => 'This test requires File::Next' if $@;

    eval 'use List::MoreUtils qw( any )';
    plan skip_all => 'This test requires List::MoreUtils' if $@;
}


my $dir = '.';
my $iter =
    File::Next::files( {
        descend_filter => sub { $_ ne '.svn' },
        file_filter => sub { /\.t$/ },
        sort_files => 1,
    }, $dir );

my @checkers;
while ( my $filename = $iter->() ) {
    next if $filename =~ m#share/skin/common/submodule#;
    push( @checkers, $filename );
}

plan tests => scalar @checkers * 3 - 1;

for my $filename ( @checkers ) {
    my @lines = read_file( $filename );

    like( $lines[0], qr/^#!.*perl/, "$filename: First line is a shebang" );
    has_line_like( \@lines, qr/^use warnings/m, "$filename uses warnings" );
    next if $filename =~ m/UserSetGraph/;
    has_line_like(
        \@lines, 
        qr/^\s*use (?:strict|Moose|Mouse|Moose::Role|MooseX::Singleton|5\.12\.\d+)(?:\(\))?;\s*$/m,
        "$filename uses strict"
    );
}

sub has_line_like {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my ( $lines_ref, $regex, $description )  = @_;

    ok( ( any { /$regex/ } @$lines_ref ), $description );
}
