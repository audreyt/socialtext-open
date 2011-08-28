#!perl -w
# @COPYRIGHT@

use strict;
use warnings;
use utf8;

use Test::More tests => 45;

BEGIN {
    use_ok( 'Socialtext::String' );
}

TRIM: {
    is( Socialtext::String::trim( '   12 x   34   ' ), '12 x   34', 'leading and trailing spaces' );
    is( Socialtext::String::trim( '123  4   ' ), '123  4', 'trailing spaces' );
    is( Socialtext::String::trim( '    1234' ), '1234', 'leading spaces' );
    is( Socialtext::String::trim( '12 34' ), '12 34', 'no extra spaces' );
    is( Socialtext::String::trim( '1 2    3 4' ), '1 2    3 4', 'no extra spaces' );
    is( Socialtext::String::trim( '' ), '', 'empty strings ');
}

URI_ESCAPE: {
    is( Socialtext::String::uri_escape('asd fds'), 'asd%20fds', 'uri_escape' );
}

DOUBLE_SPACE_HARDEN: {
    is( Socialtext::String::double_space_harden('a b  c    d'),
        "a b \x{00a0}c \x{00a0} \x{00a0}d",
        'double_space_harden' );
}

WORD_TRUNCATE: {
    is Socialtext::String::word_truncate('abcd', 15), 'abcd',
        'no ellipsis on short label';
    is Socialtext::String::word_truncate('abcd', 2), 'ab...',
        'Ellipsis on length 2 label';
    is Socialtext::String::word_truncate('abc def', 4), 'abc...',
        'Ellipsis breaks on space';
    is Socialtext::String::word_truncate('abc def', 6), 'abc...',
        'Ellipsis breaks on space if short one';
    is Socialtext::String::word_truncate('abc def', 7), 'abc def',
        'No ellipsis on exact length';
    is Socialtext::String::word_truncate('abc  def efg', 11), 'abc  def...',
        'Whitespace preserved between words';
    is Socialtext::String::word_truncate('abc def', 0), '...',
        'Ellipsis only if length is 0';
    is Socialtext::String::word_truncate('abc def', 2), 'ab...',
        'Proper short word ellipsis with space';

    my $singapore = join '', map { chr($_) } 26032, 21152, 22369;
    is Socialtext::String::word_truncate($singapore, 3), $singapore,
        'UTF8 not truncated';
    is Socialtext::String::word_truncate($singapore, 2),
        substr($singapore, 0, 2) . '...', 'UTF8 truncated with ellipsis';
}

TITLE_TO_ID: {
    use utf8;
    my %cases = (
        'asdf'    => 'asdf',
        '_asdf'   => 'asdf',
        'as_df'   => 'as_df',
        'asdf_'   => 'asdf',
        'a@#$sdf' => 'a_sdf',
        'as > df' => 'as_df',
        "as\ndf"  => 'as_df',
        'as[d]f'  => 'as_d_f',
        'asüf'    => 'as%C3%BCf',
        'hello monKey' => 'hello_monkey',
        'asTro?turf'   => 'astro_turf',
        # XXX - is this really what we want '' to go to?
        ''        => '',
        '-:-'     => '_',
        '0'       => '_'
        # ...any others?
        # You're going to hate me for this, but transliterate your new test to
        # javascript, too please (see main.js). (TODO - OAOO these tests)
    );
    while (my($in, $out) = each %cases) {
        is(Socialtext::String::title_to_id($in), $out, 
            "title_to_id '$in' => '$out'");
    }
}

TITLE_TO_DISPLAY_ID: {
    use utf8;
    my %cases = (
        'asdf'    => 'asdf',
        '_asdf'   => '_asdf',
        'as_df'   => 'as_df',
        'asdf_'   => 'asdf_',
        'a@#$sdf' => 'a%40%23%24sdf',
        'as > df' => 'as%20%3E%20df',
        "as\ndf"  => 'as%20df',
        'as[d]f'  => 'as%5Bd%5Df',
        'Buster Braün' => 'Buster%20Bra%C3%BCn',
        ''        => '',
        '-:-'     => '-%3A-',
        '0'       => '_'
    );
    while (my($in, $out) = each %cases) {
        is(Socialtext::String::title_to_display_id($in), $out, 
            "title_to_display_id '$in' => '$out'");
    }
}

