#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 111;
use Test::Socialtext::Search;

fixtures(qw( db no-ceq-jobs ));

my $hub = create_test_hub();
Test::Socialtext->main_hub( $hub );

my $singapore = join '', map { chr($_) } 26032, 21152, 22369;

# simple test of indexing
{
    create_and_confirm_page('a test page',
        "a simple page containing a funkity string");
    search_for_term('funkity');
}

# indexing utf8 content
{
    create_and_confirm_page('a utf8 body page',
        "I plan to visit $singapore someday.");

    search_for_term($singapore);
}

# case insensitivity
{
    create_and_confirm_page('a PHAT page',
        "With some PhAt content");
    search_for_term('pHaT');
}

# check that filtering is doing the expected thing
{
    my $title = 'a second utf8 page';
    my $content = "I plan to visit $singapore someday";
    create_and_confirm_page($title, $content);
    search_for_term($singapore);
    search_for_term('visit');
}

# do some category testings
# XXX searching categories that are utf8 does not work
# as we do not provide category searching in old style
{
    my @categories = ("urgent", "emergent", "crazy");
    my $title = 'a page with some categories';
    my $content = 'this page has some categories';
    create_and_confirm_page($title, $content, \@categories);
    search_for_term("category:$_") foreach (grep !/recent changes/i,
        @categories);
}

# do some title testing
{
    my $title = 'this tItleTEst page';
    my $content = 'abstract content';
    create_and_confirm_page($title, $content);
    search_for_term('title:titletest');
    search_for_term('=titletest');
    search_for_term('=abstract', 1);
}

# test phrases
{
    my $title = 'this page is the mostest';
    my $content = 'abstract content';
    create_and_confirm_page($title, $content);
    search_for_term('"the mostest"');
    search_for_term('"monkey mostest"', 'negate');
}

# test or in a phrase
{
    my $title = 'this page 999';
    my $content = 'this page or that page';
    create_and_confirm_page($title, $content);
    search_for_term('"page or that"');
}

# test title again
{
    my $title = 'this page fnordicize';
    my $content = 'this page or that page';
    create_and_confirm_page($title, $content);
    search_for_term('title:fnordicize');
    search_for_term('fnordicize');
}

