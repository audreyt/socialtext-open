#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use Socialtext::MultiCursor;
use List::MoreUtils 'none';
use Test::Socialtext tests => 17;

use_ok 'Socialtext::MultiCursorFilter';

my @food_stuffs = qw(asparagus lambs corn sloths carps broa banana);
my @animals = qw(lambs sloths carps);

sunny_day: {
    my $food  = Socialtext::MultiCursor->new(iterables => [\@food_stuffs]);
    my $vegan = Socialtext::MultiCursorFilter->new(
        cursor => $food,
        filter => sub { my $i=shift; return none { $_ eq $i } @animals; },
    );

    is( $vegan->next, 'asparagus', 'Next entry is \'asparagus\'.' );
    ok( $vegan->reset, 'MultiCursor resets properly.' );
    is_deeply(
        [ $vegan->all ],
        [ 'asparagus', 'corn', 'broa', 'banana' ],
        'All entries accounted for.',
    );
    is( $vegan->next, 'asparagus', 'Next entry is \'asparagus\'.' );
    is( $vegan->next, 'corn', 'Next entry is \'corn\'.' );
    ok( $vegan->reset, 'MultiCursor resets properly.' );
    is( $vegan->next, 'asparagus', 'Next entry is \'asparagus\'.' );
    ok( $vegan->reset, 'MultiCursor resets properly.' );
    is( $vegan->count, 4, '4 food items for a vegan (poor vegans)' );
}

with_apply: {
    my $food  = Socialtext::MultiCursor->new(iterables => [\@food_stuffs]);
    my $vegan = Socialtext::MultiCursorFilter->new(
        cursor => $food,
        filter => sub { my $i=shift; return none { $_ eq $i } @animals; },
    );

    $vegan->apply(sub {
        my $item = shift;
        return ($item eq 'banana') ? 'blueberry' : $item;
    });
    is_deeply(
        [ $vegan->all ],
        [ 'asparagus', 'corn', 'broa', 'blueberry' ],
        'Apply is applied.',
    );
}

apply_before_filter: {
    my $food  = Socialtext::MultiCursor->new(iterables => [\@food_stuffs]);
    my $vegan = Socialtext::MultiCursorFilter->new(
        cursor => $food,
        filter => sub { my $i=shift; return none { $_ eq $i } @animals; },
    );

    $vegan->apply(sub {
        my $item = shift;
        return ($item eq 'lambs') ? 'blueberry' : $item;
    });
    is_deeply(
        [ $vegan->all ],
        [ 'asparagus', 'blueberry', 'corn', 'broa', 'banana' ],
        'Apply is applied before filter.',
    );
}

with_offset: {
    my $food  = Socialtext::MultiCursor->new(iterables => [\@food_stuffs]);
    my $vegan = Socialtext::MultiCursorFilter->new(
        offset => 2,
        cursor => $food,
        filter => sub { my $i=shift; return none { $_ eq $i } @animals; },
    );
    is $vegan->next, 'broa', 'offset got correct next';
    $vegan->reset;
    is $vegan->next, 'broa', 'reset correctly adjusts position';
    $vegan->reset;
    is_deeply [ $vegan->all ], [qw(broa banana)], 'offset is applied to all';
}

with_limit: {
    my $food  = Socialtext::MultiCursor->new(iterables => [\@food_stuffs]);
    my $vegan = Socialtext::MultiCursorFilter->new(
        limit  => 2,
        cursor => $food,
        filter => sub { my $i=shift; return none { $_ eq $i } @animals; },
    );
    is_deeply [ $vegan->all ], [qw(asparagus corn)], 'limit is applied.';
}

with_limit_and_offset: {
    my $food  = Socialtext::MultiCursor->new(iterables => [\@food_stuffs]);
    my $vegan = Socialtext::MultiCursorFilter->new(
        limit  => 1,
        offset => 2,
        cursor => $food,
        filter => sub { my $i=shift; return none { $_ eq $i } @animals; },
    );
    is_deeply [ $vegan->all ], ['broa'], 'limit and offset are applied.';
}
