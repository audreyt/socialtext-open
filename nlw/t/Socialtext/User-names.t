#!perl

use strict;
use warnings;
use Test::Socialtext tests => 4;
use Test::Socialtext::User;
use Socialtext::User;

fixtures(qw( db ));

###############################################################################
# TEST: FormatFullName, non-ja locale
format_full_name: {
    my $first    = 'first';
    my $middle   = 'middle';
    my $last     = 'last';
    my $expected = 'first middle last';
    my $results = Socialtext::User::Base->FormatFullName($first, $middle, $last);
    is $results, $expected, 'Format full name, non-ja locale';
}

###############################################################################
# TEST: FormatFullName, non-ja locale, no middle name present
format_full_name_no_middle_name: {
    my $first    = 'first';
    my $middle   = undef;
    my $last     = 'last';
    my $expected = 'first last';
    my $results = Socialtext::User::Base->FormatFullName($first, $middle, $last);
    is $results, $expected, 'Format full name, non-ja locale, no middle name';
}

###############################################################################
# TEST: FormatFullName, ja locale
format_full_name_ja: {
    my $config = Socialtext::AppConfig->instance;
    $config->set('locale', 'ja');

    my $first    = 'first';
    my $middle   = 'middle';
    my $last     = 'last';
    my $expected = 'last first middle';
    my $results = Socialtext::User::Base->FormatFullName($first, $middle, $last);
    is $results, $expected, 'Format full name, ja locale';

    Socialtext::AppConfig->clear_instance;
}

###############################################################################
# TEST: FormatFullName, ja locale, no middle name present
format_full_name_ja_no_middle_name: {
    my $config = Socialtext::AppConfig->instance;
    $config->set('locale', 'ja');

    my $first    = 'first';
    my $middle   = undef;
    my $last     = 'last';
    my $expected = 'last first';
    my $results = Socialtext::User::Base->FormatFullName($first, $middle, $last);
    is $results, $expected, 'Format full name, ja locale, no middle name';

    Socialtext::AppConfig->clear_instance;
}
