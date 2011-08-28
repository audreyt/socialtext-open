#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::More;

use File::Basename ();
use Socialtext::ArchiveExtractor;

my %tests = (
    't/attachments/single-file.zip' =>
    [ 'menu.vim' ],

    't/attachments/flat-bundle.zip' =>
    [ qw( html-page-wafl.html index-test.doc socialtext-logo-30.gif ) ],

    't/attachments/with-parens.zip' =>
    [ 'Glump (2).doc', 'Glump.doc' ],

    't/attachments/tree.zip' =>
    [ qw( README.txt blue.vim darkblue.vim
          default.vim delek.vim desert.vim
          elflord.vim evening.vim koehler.vim
          morning.vim murphy.vim pablo.vim
          peachpuff.vim ron.vim shine.vim
          torte.vim zellner.vim ) ],
);

plan tests => ( scalar keys %tests ) + 1;

for my $archive ( sort keys %tests ) {
    my @extracted = 
        sort map { File::Basename::basename($_) }
        Socialtext::ArchiveExtractor->extract( archive => $archive );
    my @expected = sort @{ $tests{$archive} };

    is_deeply( \@extracted, \@expected,
               "Check extracted files for $archive" );
}

ok( ! Socialtext::ArchiveExtractor->extract( archive => 'foo.bad-extension' ),
    'Nothing happens when given a filename with an invalid extension' );
