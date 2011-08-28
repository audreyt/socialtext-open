package Socialtext::CredentialsExtractor::Client::Sync;
# @COPYRIGHT@

use Moose;
use AnyEvent;
use namespace::clean -except => 'meta';
BEGIN { extends 'Socialtext::CredentialsExtractor::Client::Async' };

around 'extract_credentials' => sub {
    my $orig = shift;
    my $self = shift;
    my $hdrs = shift;

    my $cv = AE::cv;
    $orig->($self, $hdrs, sub { $cv->send(shift) });

    # under Coro: schedule other coros (yield), one of those coros runs the
    #             event loop.
    # without Coro: enter the event loop and wait; effectively blocks
    my $result = $cv->recv;
    die $result->{error} if $result->{error};
    return $result;
};

__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

Socialtext::CredentialsExtractor::Client::Sync - Synchronous Creds Extraction

=head1 SYNOPSIS

  use Socialtext::CredentialsExtractor::Client::Sync;

  my $client = Socialtext::CredentialsExtractor::Client::Sync->new();
  my $creds  = $client->extract_credentials(\%ENV);
  if ($creds->{valid}) {
      # Valid User found (which *COULD* be the Guest User)
  }

=head1 DESCRIPTION

This module implements a synchronous/blocking Credentials Extraction client.

=cut
