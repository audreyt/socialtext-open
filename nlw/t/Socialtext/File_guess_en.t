#!perl -w
# @COPYRIGHT@

use strict;
use warnings;

use Test::More tests => 2;

use Socialtext::File;

my @files;

my %target_files = (
    'test_utf8.txt' => 'utf8',
    'test_unguess.txt.gz' => 'utf8',
);

my $locale = 'en';

Get_guess_encoding: {
    foreach( keys %target_files ) {
        my $file_full_path = 't/attachments/l10n/' . $_;
        my $encoding = Socialtext::File::get_guess_encoding( $locale,  $file_full_path );
        is $encoding, $target_files{$_}, "(" . $_ . ") " . $encoding . " = " . $target_files{$_};
    }
}

