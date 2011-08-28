#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext tests => 9;
fixtures(qw( empty ));

BEGIN {
    use_ok( 'Socialtext::Page' );
}

my $hub       = new_hub('empty');
my $page_name = 'sample page';
my $content   =<<'EOF';
This is not your time.

Tomorrow will be [your time].
EOF



MAKE_PAGE: {
    my $page = Socialtext::Page->new(hub => $hub)->create(
        title => $page_name,
        content => $content,
        creator => $hub->current_user,
    );

    ok( $page->isa('Socialtext::Page'), 'created object is a page' );
    is( $page->content, $content, "content in page is right at creation" );
}

CONTENT_DEFAULT: {
    my $page = $hub->pages->new_from_name($page_name);
    my $default_content = $page->content_as_type();

    is( $default_content, $content, "default content matches wikitext" );
}

CONTENT_WIKITEXT: {
    my $page = $hub->pages->new_from_name($page_name);
    my $wikitext_content
        = $page->content_as_type( type => 'text/x.socialtext-wiki' );
    is( $wikitext_content, $content, "default content matches wikitext" );
}

CONTENT_HTML: {
    my $page = $hub->pages->new_from_name($page_name);
    my $html_content = $page->content_as_type( type => 'text/html' );
    like( $html_content, qr{href="\?[^"]+page_name=your%20time".*>your time</a>},
        "html content has expected link" );
}

CONTENT_LINK_DICTIONARY: {
    my $page = $hub->pages->new_from_name($page_name);
    my $html_content = $page->content_as_type(
        type            => 'text/html',
        link_dictionary => 'Lite'
    );
    like( $html_content, qr{href="your%20time\?action=edit".*>your time</a>},
        "html content has expected link" );
}

CONTENT_BAD: {
    my $page = $hub->pages->new_from_name($page_name);
    my $html_content
        = eval { $page->content_as_type( type => 'text/fancier' ); };
    my $e = $@;
    ok ($e, 'error happened');
    like( $e, qr{unknown content type}, "error message is the expected" );
}

