#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext tests => 8;
fixtures( 'db' );

my $admin_hub = create_test_hub();
my $user = $admin_hub->current_user;
my $pages = $admin_hub->pages;

try_delete: {
    my $cat = 'Category Delete Test';

    my $page = $pages->new_from_name('Admin');
    $page->edit_rev();
    $page->content('test content');
    $page->tags([$cat]);
    $page->store();

    is( ( grep { $_->is_in_category($cat) } $pages->all), 1,
        'There is one page in the "Category Delete Test" category');

    my $categories = $admin_hub->category;
    $categories->delete(tag  => $cat, user => $user);

    is( ( scalar grep { $_->is_in_category($cat) } $pages->all), 0,
        'There are no pages in the "Category Delete Test" category');

    my %cats = map { $_ => 1 } $categories->all;
    ok( !$cats{$cat},
        'Categories object no longer contains reference to deleted tag');
}

{
    my $cat = 'Category Delete Test 2';

    my $page = $pages->new_from_name('Admin');
    $page->edit_rev();
    $page->content('test content');
    $page->tags([$cat]);
    $page->store();

    $page = $pages->new_from_name('Conversations');
    $page->edit_rev();
    $page->content('test content 2');
    $page->tags([$cat]);
    $page->store();

    is( ( scalar grep { $_->is_in_category($cat) } $pages->all ), 2,
        'There are two pages in the "Category Delete Test 2" category' );

    my $categories = $admin_hub->category;
    $categories->delete(tag => $cat, user => $user);

    is( ( scalar grep { $_->is_in_category($cat) } $pages->all ), 0,
        'There are no pages in the "Category Delete Test 2" category' );

    my %cats = map { $_ => 1 } $categories->all;
    ok( ! $cats{$cat},
        'Categories object no longer contains reference to "Category Delete Test 2"' );
}

caseless_delete: {
    # Capitalized Tag
    my $page = $pages->new_from_name('Maxwell Banjo');
    $page->edit_rev();
    $page->content('test content');
    $page->tags([ 'Dog' ]); # Capitalized
    $page->store( user => $user );

    # lowercase tag
    $page = $pages->new_from_name('Warren Kaczynski');
    $page->edit_rev();
    $page->content('test content');
    $page->tags(['dog']); # lower-case
    $page->store( user => $user );

    # should delete 'Dog' and 'dog'.
    my $categories = $admin_hub->category;
    $categories->delete(tag => 'dog', user => $user);

    is( ( scalar grep { $_->is_in_category('Dog') } $pages->all ), 0,
        'There are no pages in the "Dog" category' );

    is( ( scalar grep { $_->is_in_category('dog') } $pages->all ), 0,
        'There are no pages in the "dog" category' );
}
