#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext;

BEGIN {
    plan tests => 10;
    use_ok( 'Socialtext::Headers' );
}

ERASE_HEADERS: {
    my $headers = Socialtext::Headers->new;
    like $headers->pragma, qr/no-cache/, "Pragma contains no-cache.";
    like $headers->cache_control, qr/no-cache/, "Cache-Control has no-cache.";
    $headers->erase_cache_headers();
    is $headers->pragma, undef, "Pragma was erased.";
    is $headers->cache_control, undef, "Cache-Control was erased.";
}

ADD_ATTACHMENT: {
    my $headers = Socialtext::Headers->new;
    $headers->add_attachment(
        len => 97,
        type => 'i/love-cows',
        filename => 'cows.txt',
    );
    is $headers->pragma, undef, "Pragma was erased.";
    is $headers->cache_control, undef, "Cache-Control was erased.";
    is $headers->content_length, 97, 'Checking Content-Length';
    is $headers->content_type, 'i/love-cows', 'Checking Content-Type';
    like $headers->content_disposition, qr/attachment.*filename="cows\.txt"/,
        'Checking Content-Type';
}
