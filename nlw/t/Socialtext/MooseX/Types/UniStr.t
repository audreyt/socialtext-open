#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 15;
use Test::Fatal;
use Moose::Util::TypeConstraints;
use Socialtext::MooseX::Types::UniStr;

my $str      = 'abc123';
my $utf8_str = 'Groß Blah Blah';

###############################################################################
# TEST: UniStr
unistr: {
    my $type = Moose::Util::TypeConstraints::find_or_parse_type_constraint(
        'UniStr'
    );
    ok $type, 'Found UniStr type';

    is exception { $type->assert_coerce($str) }, undef,
        '... coerces w/string value';
    is exception { $type->assert_coerce($utf8_str) }, undef,
        '... coerces w/utf8 string value';
    like exception { $type->assert_coerce(undef) },
        qr/Validation failed for 'UniStr' with value undef/,
        '... coerce fails w/undef';
}

###############################################################################
# TEST: MaybeUniStr
maybe_unistr: {
    my $type = Moose::Util::TypeConstraints::find_or_parse_type_constraint(
        'MaybeUniStr'
    );
    ok $type, 'Found MaybeUniStr type';

    is exception { $type->assert_coerce($str) }, undef,
        '... coerces w/string value';
    is exception { $type->assert_coerce($utf8_str) }, undef,
        '... coerces w/utf8 string value';
    is exception { $type->assert_coerce(undef) }, undef,
        '... coerces w/undef';
}

###############################################################################
# TEST: Coercion via class instantiation
coercion_at_instantiation: {
    package Foo;
    use Moose;
    use Socialtext::MooseX::Types::UniStr;
    has 'unistr' => (is => 'rw', isa => 'UniStr', coerce => 1);
    has 'maybe_unistr' => (is => 'rw', isa => 'MaybeUniStr', coerce => 1);

    package main;
    pass 'Instantiation tests';

    unistr: {
        is exception { Foo->new(unistr => $str) }, undef,
            '... UniStr w/Str value';
        is exception { Foo->new(unistr => $utf8_str) }, undef,
            '... UniStr w/UniStr value';
        like exception { Foo->new(unistr => undef) },
            qr/Validation failed for 'UniStr' with value undef/,
            '... UniStr w/undef fails validation';
    }

    maybe_unistr: {
        is exception { Foo->new(maybe_unistr => $str) }, undef,
            '... MaybeUniStr w/Str value';
        is exception { Foo->new(maybe_unistr => $utf8_str) }, undef,
            '... MaybeUniStr w/UniStr value';
        is exception { Foo->new(maybe_unistr => undef) }, undef,
            '... MaybeUniStr w/undef value';
    }
}
