#!perl
# @COPYRIGHT@

use strict;
use warnings;
use utf8;

use Test::Socialtext tests => 18;
fixtures(qw( empty ));

BEGIN {
    use_ok( 'Socialtext::WeblogPlugin' );
}

WEBLOG_CACHE: {
    my $hub = new_hub('empty');

    $hub->weblog->current_weblog('socialtext blog');
    $hub->weblog->update_current_weblog();
    is $hub->weblog->current_blog, 'socialtext blog',
        'cache is written with socialtext blog';
}

CREATE_BLOG: {
    my $hub = new_hub('empty');

    my $category = $hub->weblog->create_weblog($$);
    check_category($hub, $category, "$$ Blog");

    $category = $hub->weblog->create_weblog("bar $$ Blog");
    check_category($hub, $category, "bar $$ Blog");

    $category = $hub->weblog->create_weblog("bar $$ blog");
    is ($category, undef, 'error condition when repeat name');
    ok ((grep /There is already/, @{$hub->weblog->errors} ), 'error message correct when repeat name');

    $category = $hub->weblog->create_weblog("bar!!$$!!blog");
    is ($category, undef, 'error condition when similar name');
    ok ((grep /There is already/, @{$hub->weblog->errors} ), 'error message correct when similar name');
}

sub check_category {
    my $hub      = shift;
    my $returned = shift;
    my $expected = shift;

    is $returned, $expected, 'return category is correct category';
    my $page = $hub->pages->new_from_name("first post in $expected");
    like ($page->content, qr{This is the first post in $expected}, 'first post created with right content');
    ok ((grep $expected, @{$page->tags}), 'post has right category');
}

BLOG_TITLE_IS_VALID: {
    my $hub = new_hub('empty');
   
    #
    # Check length boundary conditions.
    #
    ok( ! $hub->weblog->_weblog_title_is_valid('a' x 256),
       'Too-long blog name fails'
    );
    ok( $hub->weblog->_weblog_title_is_valid('a' x 255),
        'blog name of exactly 255 characters succeeds'
    );

    #
    # Check the name which had utf8 characters.
    #
    ok( ! $hub->weblog->_weblog_title_is_valid('あ' x 29),
       'Too-long blog name which had utf8 fails'
    );
    ok( $hub->weblog->_weblog_title_is_valid('あ' x 28),
        'blog name of exactly 28 utf8 characters succeeds'
    );
}

BLOG_NAME_TO_ID: {
    my $hub = new_hub('empty');

    #
    # Check creating the page object.
    #
    ok( !defined($hub->weblog->_create_first_post('a' x 242)),
        "Createing blog page object fails"
    );

    #
    # Check creating the page object which had utf8 characters.
    #
    ok( !defined($hub->weblog->_create_first_post('あ' x 29)),
        'Createing blog page object which had utf8 characters fails'
    );

}

