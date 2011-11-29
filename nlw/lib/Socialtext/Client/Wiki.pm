package Socialtext::Client::Wiki;
# @COPYRIGHT@
use 5.12.0;
use warnings;
no warnings 'uninitialized';
use parent 'Exporter';
use LWP::UserAgent;
use HTTP::Request::Common;
use Socialtext::HTTP::Ports;

our @EXPORT = qw( wiki2html html2wiki );

sub wiki2html {
    unshift @_, 'wiki';
    goto &_request;
}

sub html2wiki {
    return '' unless length $_[0];
    unshift @_, 'html';
    goto &_request;
}

sub _request {
    state $ua //= LWP::UserAgent->new;
    state $wikid_url //= "http://127.0.0.1:".Socialtext::HTTP::Ports->wikid_port;
    my $request = POST $wikid_url, \@_;
    my $response = $ua->simple_request($request);
    if ($response->is_success) {
        return $response->decoded_content;
    }
    die $response->decoded_content;
}

1;

__END__

=head1 NAME

Socialtext::Client::Wiki - HTTP client to st-wikid

=head1 SYNOPSIS

    use Socialtext::Client::Wiki qw( wiki2html html2wiki );

=head1 DESCRIPTION

This module exports two functions, C<wiki2html> and C<html2wiki>,
as provided by the F<st-wikid> service.

If the service is down for any reason, an exception is raised with
the error message from LWP.

=cut
