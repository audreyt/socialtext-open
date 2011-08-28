#!perl
# @COPYRIGHT@

use utf8;
use strict;
use warnings;

use Test::Socialtext tests => 4;
fixtures( 'admin' );
use Socialtext::Pages;

my $hub = new_hub('admin');

my $page = Socialtext::Page->new( hub => $hub )->create(
    title   => "test",
    content => "{googlesearch: One}\n\n{googlesoap: Two}\n\n{googlesearch: naïve}\n\n{googlesearch: 曌}\n\n",
    creator => $hub->current_user,
);

my $content = $page->to_html_or_default;

SKIP: {
    skip "Google gave us 403", 4 if $content =~ m/\s403\s/;

    like $content, qr{\Q<a href="http://www.google.com/search?q=One">Search for "One"</a>\E},
        '{googlesearch: One} works';
    like $content, qr{\Q<a href="http://www.google.com/search?q=Two">Search for "Two"</a>\E},
        '{googlesoap: Two} works';

    like $content, qr{\QSearch for "naïve"</a>\E},
        '{googlesearch: naïve} works';
    like $content, qr{\QSearch for "曌"</a>\E},
        '{googlesearch: 曌} works';
}
