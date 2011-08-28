#!perl -w
# @COPYRIGHT@

use strict;
use warnings;

use Test::More tests => 6;

use Socialtext::File;

my @files;

my %target_files = (
    'test_eucjp.txt' => 'euc-jp',
    'test_jis.txt' => 'iso-2022-jp',
    'test_sjis.txt' => 'shiftjis',
    'test_utf8.txt' => 'utf8',
    'test_unguess.txt.gz' => 'utf8',
    'test_dbl_match.txt' => 'euc-jp' );
my $locale = 'ja';

Get_guess_encoding: {
    foreach( keys %target_files ) {
        my $file_full_path = 't/attachments/l10n/' . $_;
        my $encoding = Socialtext::File::get_guess_encoding( $locale,  $file_full_path );
        is $encoding, $target_files{$_}, "(" . $_ . ") " . $encoding . " = " . $target_files{$_};
    }
}

