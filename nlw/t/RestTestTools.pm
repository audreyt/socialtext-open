package t::RestTestTools;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Exporter';
use Socialtext::JSON qw/encode_json/;
use mocked 'Socialtext::CGI::Scrubbed';
use mocked 'Socialtext::User';
use mocked 'Socialtext::Rest', 'is_status';
use URI::Escape qw/uri_escape/;

our @EXPORT_OK = qw/do_get_json do_post_form do_post_json is_status/;

our $Actor;

sub default_actor {
    my $class = shift;
    $Actor ||= Socialtext::User->new(
        user_id    => 27,
        name       => 'username',
        email      => 'username@example.com',
        first_name => 'User',
        last_name  => 'Name',
        is_guest   => 0
    );
    return $Actor;
}

sub set_actor {
    my $class = shift;
    $Actor = shift;
}

sub reset_actor {
    my $class = shift;
    $Actor = undef;
}

sub do_get_json {
    Socialtext::Events::clear_get_args();

    my $actor = default_actor();
    my $cgi   = Socialtext::CGI::Scrubbed->new({@_});
    my $rest  = Socialtext::Rest->new(undef, $cgi, user => $actor);
    my $e     = Socialtext::Rest::Events->new($rest, $cgi);
    $e->{user} = $actor;
    my $result = $e->GET_json($rest);
    return ($rest, $result);
}

sub do_post_form {
    Socialtext::Events::clear_get_args();
    my %form = (@_);
    my $post = '';
    $post .= "$_=" . uri_escape($form{$_}) . '&' for keys %form;
    chop $post;

    my $actor = default_actor();
    my $cgi   = Socialtext::CGI::Scrubbed->new($post);
    my $rest  = Socialtext::Rest->new(undef, $cgi, user => $actor);
    my $e     = Socialtext::Rest::Events->new($rest, undef, user => $actor);
    $e->{_test_cgi} = $cgi;
    $e->{rest}      = $rest;
    my $result = $e->POST_form($rest);
    return ($rest, $result);
}

sub do_post_json {
    Socialtext::Events::clear_get_args();
    my $json = encode_json(shift);

    my $actor = default_actor();
    my $cgi   = Socialtext::CGI::Scrubbed->new;
    my $rest  = Socialtext::Rest->new(undef, $cgi, user => $actor);
    my $e     = Socialtext::Rest::Events->new($rest, undef, user => $actor);
    $e->{_content} = $rest->{_content} = $json;
    $e->{rest} = $rest;
    my $result = $e->POST_json($rest);
    return ($rest, $result);
}

1;
