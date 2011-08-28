#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 18;
fixtures(qw( empty ));

BEGIN {
    use_ok( 'Socialtext::Formatter::Phrase' );
}

UNITS_IN_FREELINKS: {
    my $hub = new_hub('empty');

    my $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'page one',
        content => 'some [*stuff*] and [http://foobar/]',
        creator => $hub->current_user,
    );

    my $html = $page->to_html;

    like $html, qr{>\*stuff\*</a>},
        'phrase formatting does not work in freelinks';
    like $html, qr{>http://foobar/</a>},
        'link formatting does not work in freelinks';
}

PLAIN_HYPERLINK: {
    my $hub = new_hub('empty');

    my $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'page one',
        content => 'This is a link to http://www.example.com/ by itself.',
        creator => $hub->current_user,
    );

    my $html = $page->to_html;
    like $html, qr{\Qhref="http://www.example.com/"},
         'plain link surrounded by space is formatted properly';

    $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'page one',
        content => 'This is a link to http://www.example.com/',
        creator => $hub->current_user,
    );

    $html = $page->to_html;
    like $html, qr{\Qhref="http://www.example.com/"},
         'plain link at end of body is formatted properly';

}

ANCHOR_IN_HYPERLINK: {
    my $hub = new_hub('empty');

    my $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'page one',
        content => 'This is a link to http://www.example.com/#anchor1.',
        creator => $hub->current_user,
    );

    my $html = $page->to_html;
    like $html, qr{\Qhref="http://www.example.com/#anchor1"},
         'period is not included in hyperlink with anchor';

}

ITALIC_HYPERLINK: {
    my $hub = new_hub('empty');

    my $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'page one',
        content => 'This is a link to _http://www.example.com/#anchor1_.',
        creator => $hub->current_user,
    );

    my $html = $page->to_html;
    like $html, qr{<em><a .*anchor1</a></em>},
         'italic hyperlinks are possible';
}

PUNCTUATION_AT_END_OF_HYPERLINK: {
    my $hub = new_hub('empty');

    my $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'page one',
        content => 'This is a link to http://www.example.com/.',
        creator => $hub->current_user,
    );

    my $html = $page->to_html;
    like $html, qr{\Qhref="http://www.example.com/"},
         'period is not included in hyperlink';

    $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'page one',
        content => 'This is a link to http://www.example.com/,',
        creator => $hub->current_user,
    );

    $html = $page->to_html;
    like $html, qr{\Qhref="http://www.example.com/"},
         'comma is not included in hyperlink';

    $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'page one',
        content => 'This is a link to http://www.example.com/page.html.',
        creator => $hub->current_user,
    );

    $html = $page->to_html;
    like $html, qr{\Qhref="http://www.example.com/page.html"},
         'period is not included in hyperlink';

    $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'page one',
        content => 'This is a link to http://www.example.com/page.html,',
        creator => $hub->current_user,
    );

    $html = $page->to_html;
    like $html, qr{\Qhref="http://www.example.com/page.html"},
         'comma is not included in hyperlink';
}

MAILTO_HYPERLINK: {
    my $hub = new_hub('empty');

    my $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'page one',
        content => 'This is a mailto:foo@example.com link.',
        creator => $hub->current_user,
    );

    my $html = $page->to_html;
    like $html, qr{\Qhref="mailto:foo\E\@\Qexample.com"\E.+foo\@\Qexample.com</a>},
         'mailto link is linked properly';

    $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'page one',
        content => 'This is a link to "address"<mailto:foo@example.com>',
        creator => $hub->current_user,
    );

    $html = $page->to_html;
    like $html, qr{\Qhref="mailto:foo\E\@\Qexample.com"\E.+\Qaddress</a>},
         'named mailto link';

}

Image_links: {
    my $hub = new_hub('empty');

    my %image_urls = (
        jpeg => 'http://example.com/monkey.jpg',
        dynamic_jpeg => 'http://example.com/monkey.jpg?v=0',
    );
    for my $k (keys %image_urls) {
        my $url = $image_urls{$k};
        my $page = Socialtext::Page->new( hub => $hub )->create(
            title   => $k,
            content => "This is an image link: $url",
            creator => $hub->current_user,
        );

        my $html = $page->to_html;
        like $html, qr/\Qimg alt="$url" src="$url"\E/, "Image: $k";
    }
}

Smiley_Friendly: {
    my $hub = new_hub('empty');

    my $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'smiley',
        content => ':-) Making Wikitext- more Smiley Friendly',
        creator => $hub->current_user,
    );

    my $html = $page->to_html;
    like $html, qr{:-\)},
         'Smileys are rendered as-is instead of as deletion phrases';
}

NonSmiley_UnFriendly: {
    my $hub = new_hub('empty');

    my $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'non-smiley',
        content => ':*) Making Wikitext* more Smiley Friendly',
        creator => $hub->current_user,
    );

    my $html = $page->to_html;
    unlike $html, qr{:\*\)},
         'Non-smileys are still rendered as phrases';
}

UnderScore_InBetween: {
    my $hub = new_hub('empty');

    my $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'underscore-inbetween',
        content => '_hello duckduck_goose moose_',
        creator => $hub->current_user,
    );

    my $html = $page->to_html;
    like $html, qr{<em>},
         'Underscores inbetween words does not prevent emphasis';
}

