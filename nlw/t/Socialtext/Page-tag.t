#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 9;
fixtures( 'admin' );

use Readonly;
use utf8;

Readonly my $TAG => 'snarky';
Readonly my $UTF8_TAG      => 'Και';

EXISTING_TAGS: {
    my $page = new_hub('admin')->pages->new_from_name("Admin wiki");
    my $original_categories = $page->tags;

    ok( !grep ( { $_ eq $TAG } @$original_categories ),
        'old categories do not have tag' );
}

ADD_TAG: {
    my $page = new_hub('admin')->pages->new_from_name("Admin wiki");
    $page->add_tags($TAG);

    my $new_categories = $page->tags;

    ok( grep ( { $_ eq $TAG } @$new_categories ),
        'new categories have tag after add' );
}

ADD_TAG_SCOPE: {
    my $page       = new_hub('admin')->pages->new_from_name("Admin wiki");
    my $categories = $page->tags;
    ok( grep ( { $_ eq $TAG } @$categories ),
        'new categories have tag after save' );
}

ALL_CATEGORIES: {
    my @categories = new_hub('admin')->category->all();
    ok( grep ( { $_ eq $TAG } @categories ),
        "all categories have $TAG after save" );
}

ADD_UTF8_TAG: {
    my $page = new_hub('admin')->pages->new_from_name("Admin wiki");
    $page->add_tags($UTF8_TAG);

    my $new_categories = $page->tags;

    ok( grep ( { $_ eq $UTF8_TAG } @$new_categories ),
        'new categories have tag after add' );
}

ADD_UTF8_TAG_SCOPE: {
    my $page       = new_hub('admin')->pages->new_from_name("Admin wiki");
    my $categories = $page->tags;
    ok( grep ( { $_ eq $UTF8_TAG } @$categories ),
        'new categories have tag after save' );
}

ALL_CATEGORIES_UTF8: {
    my @categories = new_hub('admin')->category->all();
    ok( grep ( { $_ eq $UTF8_TAG } @categories ),
        "all categories have $UTF8_TAG after save" );
}


DELETE_TAG: {
    my $page       = new_hub('admin')->pages->new_from_name("Admin wiki");
    my $original_categories = $page->tags;

    $page->edit_rev();
    $page->delete_tag($TAG);
    $page->store();

    my $new_categories = $page->tags;
    ok( !grep ( { $_ eq $TAG } @$new_categories ),
        'new categories do not have tag after delete' );
}

DELETE_TAG_SCOPE: {
    my $page       = new_hub('admin')->pages->new_from_name("Admin wiki");
    my $categories = $page->tags;
    ok( !grep ( { $_ eq $TAG } @$categories ),
        'new categories do not have tag after save' );
}
