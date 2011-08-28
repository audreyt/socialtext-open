#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 7;
fixtures(qw( empty ));

BEGIN {
    use_ok( 'Socialtext::Formatter::Viewer' );
}

my $hub = new_hub('empty');

my $page = Socialtext::Page->new( hub => $hub )->create(
    title   => 'page one',
    content => 'some [*stuff*] and [http://foobar/]',
    creator => $hub->current_user,
);

my $wikitext = "This is just simple text\n";
my $html = $hub->viewer->text_to_html($wikitext);
my $unwrapped_html = $hub->viewer->text_to_non_wrapped_html($wikitext);
isnt($html, $unwrapped_html, 'Unwrapped returns something different'); 
unlike $html, qr{^<div>}, 'Unwrapped text does not have divs';

my $no_p_html = $hub->viewer->text_to_non_wrapped_html(
    $wikitext, 
    Socialtext::Formatter::Viewer::NO_PARAGRAPH,
);
isnt($unwrapped_html, $no_p_html, 'NO_PARAGRAPH returns something different'); 
unlike $html, qr{^<p>}, 'No paragraph node when NO_PARAGRAPH is specified';

$wikitext = "Text with \[A Link\]\n";
$unwrapped_html = $hub->viewer->text_to_non_wrapped_html($wikitext);
unlike $unwrapped_html, qr{^<div>}, 'Unwrapped text with link does not have wrapper div';
like $unwrapped_html, qr{<a.*href=".*A Link}, 'Has html link';

