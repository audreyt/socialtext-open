#!perl
# @COPYRIGHT@

use strict;
use warnings;
use DateTime;
use Socialtext::Pages;
use Test::Socialtext tests => 8;

###############################################################################
# Fixtures: db
# - need a DB but don't care what's in it
fixtures(qw( db ));

###############################################################################
# TEST: start/limit work as expected.
start_limit_work: {
    # Create a dummy/test Hub
    my $hub  = create_test_hub();
    my $user = $hub->current_user;

    # Create a bunch of pages
    my $date = DateTime->now()->add( seconds => 60 );
    my @all_pages;
    for my $i (0 .. 20) {
        my $page_name = "page $i";
        Socialtext::Page->new(hub => $hub)->create(
            title   => $page_name,
            content => $page_name,
            date    => $date,
            creator => $user,
        );
        push @all_pages, $page_name;
        $date->add( seconds => 5 );
    }

    # Get a range of pages back
    my $category = $hub->category;
    my $start    = 2;
    my $limit    = 7;
    my @pages = $category->get_pages_numeric_range(
        'recent changes', $start, $start+$limit,
    );

    # Check results
    is @pages, $limit, 'got correct number of pages';

    for my $i (0 .. $#pages) {
        my $page_title = $pages[$i]->title;
        my $expected   = $all_pages[ -($start + $i + 1) ];
        is $page_title, $expected, "result $i has expected page title";
    }
}
