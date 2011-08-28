#!perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::More;
use mocked 'LWP::UserAgent';

BEGIN {
    use_ok 'Socialtext::Job::WebHook';
}

Normal_webhook: {
    my $url = 'http://example.com/foo';
    local $LWP::UserAgent::RESULTS{$url} = 200;
    my $j = Socialtext::Job::WebHook->new();
    isa_ok $j, 'Socialtext::Job::WebHook';
    my $resp = $j->_make_webhook_request(
        {
            id  => 42,
            url => $url,
        },
        "payload",
    );
    is $resp->code, 200;
    is_deeply $LWP::UserAgent::ARGS{$url}, [ json_payload => "payload" ];
}

Webhook_to_invalid_url: {
    my $url = 'http://example.com/foo';
    my $j = Socialtext::Job::WebHook->new();
    isa_ok $j, 'Socialtext::Job::WebHook';
    my $resp = $j->_make_webhook_request(
        {
            id  => 42,
            url => $url,
        },
        "payload",
    );
    is $resp->code, 404;
    is_deeply $LWP::UserAgent::ARGS{$url}, [ json_payload => "payload" ];
}

Webhook_parses_url_correctly: {
    my $url = 'http://example.com/foo';
    local $LWP::UserAgent::RESULTS{$url} = 200;
    my $j = Socialtext::Job::WebHook->new();
    isa_ok $j, 'Socialtext::Job::WebHook';
    my $resp = $j->_make_webhook_request(
        {
            id  => 42,
            url => "$url?bar=1",
        },
        "payload",
    );
    is $resp->code, 200;
    is_deeply $LWP::UserAgent::ARGS{$url}, [ bar => 1, json_payload => "payload" ];
}

done_testing();
