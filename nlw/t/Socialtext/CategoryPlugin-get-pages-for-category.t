#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 7;
use Socialtext::Pages;
use DateTime;

fixtures(qw( db ));

my $hub = create_test_hub();

# create pages
{
    my $date = DateTime->now->add( seconds => 60 );
    for my $i (1 .. 20) {
        Socialtext::Page->new(hub => $hub)->create(
            title => "page title $i",
            content => "page content $i",
            date => $date,
            creator => $hub->current_user,
            categories => ['rad', ($i % 2 ? 'odd' : 'even')],
        );
        $date->add( seconds => 2 );
    }
}

############# CRAPPY OLD API ###################
# get ten of them and see which ones you have
Get_with_limit: {
    my @pages = $hub->category->get_pages_for_category( 'rad', 10 );
    my @ids = map {$_->id} @pages;
    my @numbers = map {$_ =~ /_(\d+)$/; $1} @ids;

    is join(',', @numbers), join(',', reverse 11 .. 20), 'pages returned in sequence';
    is scalar(@numbers), 10, 'got 10 pages';
}

Get: {
    my @pages = $hub->category->get_pages_for_category( 'even' );
    my @ids = map {$_->id} @pages;
    my @numbers = map {$_ =~ /_(\d+)$/; $1} @ids;

    is join(',', @numbers), join(',', grep { !($_ % 2) } reverse 1 .. 20),
        'pages returned in sequence';
    is scalar(@numbers), 10, 'got 10 pages';
}

############# NEW FAST API ###################
Get_with_limit: {
    my $pages = $hub->category->_get_pages_for_listview( 'rad', 'desc', undef, 10, 5 );
    is $pages->{total_entries}, 20, 'total entries';
    my @ids = map {$_->{page_id}} @{ $pages->{rows} };
    my @numbers = map {$_ =~ /_(\d+)$/; $1} @ids;

    is join(',', @numbers), join(',', reverse 6 .. 15), 'pages returned in sequence';
    is scalar(@numbers), 10, 'got 10 pages';
}

