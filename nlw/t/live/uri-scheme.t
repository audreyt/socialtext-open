#!perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Live fixtures => [qw(admin)];
use Test::More tests => 4;
use Socialtext::Hostname;
use Socialtext::HTTP::Ports;

my $live     = Test::Live->new();
my $base_uri = $live->base_url;
my $feed     = $base_uri . '/feed/workspace/admin?page=what_if_i_make_a_mistake';
my $host     = Socialtext::Hostname::fqdn();
my $port      = Socialtext::HTTP::Ports->http_port();
my $ssl_port  = Socialtext::HTTP::Ports->https_port();

$live->mech( WWW::Mechanize->new() );

$live->log_in();

{
    $live->mech->get($feed);
    is( $live->mech->status, 200, "GET $feed gives 200" );
    my $content = $live->mech->content;

    like $content,
        qr{img alt="View-Page-Revisions.png" src="http://.*?View-Page-Revisions.png},
        'url for image is http';
}

{
    $feed =~ s/http/https/;
    $feed =~ s/$port/$ssl_port/;
    $live->mech->get($feed);
    is( $live->mech->status, 200, "GET $feed gives 200" );
    my $content = $live->mech->content;
    like $content,
        qr{img alt="View-Page-Revisions.png" src="https://.*?View-Page-Revisions.png},
        'url for image is https';
}
