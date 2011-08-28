#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::HTTP::Socialtext '-syntax', tests => 36;

use Readonly;
use Test::Live fixtures => ['admin'];

Readonly my $BASE => Test::HTTP::Socialtext->url('/data');
Readonly my $ECHO_WORD => 'xyzzy';
Readonly my @COMMON_MIMES => qw(text/html 
                                text/x.socialtext-wiki 
                                application/json 
                                text/xml);

# These quick and dirty tests only checks that the content types match and
# that the body _cointains_ the requested word.
for my $type (@COMMON_MIMES) {
    test_http "echo $type" {
        >> GET $BASE/echo/$ECHO_WORD
        >> Accept: $type

        << 200
        ~< Content-type: ^$type(;|,|$)
        <<
        ~< $ECHO_WORD
    }
}

my %bodies = (
    'application/json' => '{"message": "I like cows"}',
    'text/x.cowsay' => <<'COWS',
 _____________ 
< I like cows >
 ------------- 
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||
COWS
    'text/xml' => <<'XML',
<st:xml xmlns:st="http://socialtext.net/xmlns/0.1">
    <st:message>I like cows</st:message>
</st:xml>
XML
);

for my $send_type ( 'application/json', 'text/xml', 'text/x.cowsay' ) {
    for my $get_type ( 'application/json', 'text/xml' ) {
        test_http "POST echo. Sending $send_type. Response" {
            >> POST $BASE/echo/$ECHO_WORD
            >> Accept: $get_type
            >> Content-Type: $send_type
            >>
            >> $bodies{$send_type}

            << 200
            ~< Content-type: $get_type
            <<
            ~< $ECHO_WORD
            ~< I like cows
        }
    }
}
