#!perl
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::AppConfig;
use Test::Socialtext tests => 13;

fixtures(qw( db ));

use_ok 'Socialtext::Encode';

binmode STDERR, 'utf8'; # So diagnostics don't complain

# Socialtext::Encode::is_valid_utf8
{
    my $invalid = "\x96 \x92";
    ok not(Encode::is_utf8($invalid)),
        "bad string doesn't start out with the utf8 flag set";
    ok not(Socialtext::Encode::is_valid_utf8($invalid)), "doesn't validate";
    ok not(Encode::is_utf8($invalid)), "still no flag set on original string";

    my $valid = Encode::decode_utf8("【ü】");
    ok Encode::is_utf8($valid), 'Good text has utf8 flag';
    ok Socialtext::Encode::is_valid_utf8($valid), 'validates';
    ok Encode::is_utf8($valid), 'still has utf8 flag';
}

# Socialtext::Encode::ensure_is_utf8
{
    my $orig = "Tüst";
    my $str = $orig;

    ok !Encode::is_utf8($str), "plain text does not have the utf8 flag";
    is 5, length($str), "length works bytewise";

    $str = Socialtext::Encode::ensure_is_utf8($str);
    ok Encode::is_utf8($str), "decoding sets the flag";
    ok !Encode::is_utf8($orig), "orig's flag is left alone";

    my $str2 = Socialtext::Encode::ensure_is_utf8($str);
    ok Encode::is_utf8($str2), "ensure_is_utf8 is idempotent";
    is $str, $str2, "both strings are equal";
}
