#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::More tests => 9;
use utf8;

BEGIN {
    use_ok 'Socialtext::Locales', qw(valid_code available_locales);
}

Valid_codes: {
    for (qw(en zz zq xq zh_CN zh_TW)) {
        ok valid_code($_), "$_ is valid";
    }
}

Available_locales: {
    my $locales = available_locales();
    isa_ok $locales, 'HASH';
    is $locales->{en}, 'English', 'en locale works';
}
