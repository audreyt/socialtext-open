#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 6;

use_ok('Socialtext::EmailReceiver::Factory');
fixtures(qw( empty ));

my $hub = new_hub('empty');
isa_ok( $hub, 'Socialtext::Hub' );
my $ws = $hub->current_workspace();

CREATE_EN: {

    my $locale = 'en';
    my $string = 'hogehoge';
    my $receiver;
    ok ( eval{
            $receiver = Socialtext::EmailReceiver::Factory->create(
                {
                    locale => $locale,
                    string => $string,
                    workspace => $ws,
                });
        });

    isa_ok($receiver, "Socialtext::EmailReceiver::" . $locale);
}

CREATE_JA: {

    my $locale = 'ja';
    my $string = 'hogehoge';
    my $receiver;
    ok ( eval{
            $receiver = Socialtext::EmailReceiver::Factory->create(
                {
                    locale => $locale,
                    string => $string,
                    workspace => $ws,
                });
        });
    isa_ok($receiver, "Socialtext::EmailReceiver::" . $locale);
}

