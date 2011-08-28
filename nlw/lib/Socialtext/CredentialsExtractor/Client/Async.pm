package Socialtext::CredentialsExtractor::Client::Async;
# @COPYRIGHT@
use Moose;
use AnyEvent::HTTP qw(http_request);
use Try::Tiny;
use Socialtext::JSON qw(encode_json decode_json);
use Socialtext::Cache;
use Socialtext::HTTP::Ports;
use Socialtext::CredentialsExtractor;
use namespace::clean -except => 'meta';

has 'userd_host' => (
    is => 'ro', isa => 'Str', default => '127.0.0.1',
);
has 'userd_port' => (
    is => 'ro', isa => 'Int', default => Socialtext::HTTP::Ports->userd_port,
);
has 'userd_path' => (
    is => 'ro', isa => 'Str', default => '/stuserd',
);
has 'userd_uri' => (
    is => 'ro', isa => 'Str', lazy_build => '1',
);
has 'cache_enabled' => (
    is => 'ro', isa => 'Bool', reader => 'can_cache', default => 1,
);
has 'timeout' => ( is => 'rw', isa => 'Int', default => 30 );

sub _build_userd_uri {
    my $self = shift;
    return "http://".$self->userd_host.":".$self->userd_port.$self->userd_path;
}

sub cache {
    Socialtext::Cache->cache('creds-extractor-client', {
        class => 'Socialtext::Cache::PersistentHash',
    } );
};

sub extract_desired_headers {
    my $self = shift;
    my $hdrs = shift;
    my @header_list  = Socialtext::CredentialsExtractor->HeadersNeeded();
    my %hdrs_to_send =
        map  { $_->[0] => $_->[1] }
        grep { defined $_->[1] }
        map  { [$_ => $hdrs->{$_} || $hdrs->{"HTTP_$_"}] }
        @header_list;

    # Strip Google Analytics cache-busting cookies if present
    if (defined $hdrs_to_send{COOKIE}) {
        $hdrs_to_send{COOKIE} =~ s{__utm[^;]+(?:; )?}{}g;
    }

    return \%hdrs_to_send;
}

sub extract_credentials {
    my ($self, $hdrs, $cb) = @_;

    my $can_cache = $self->can_cache;
    try {
        # minimal headers needing to be send to st-userd
        my $hdrs_to_send = $self->extract_desired_headers($hdrs);

        # see if we have valid cached credentials
        if ($can_cache) {
            if (my $creds = $self->get_cached_credentials($hdrs_to_send)) {
                try { $cb->($creds) };
                return;
            }
        }

        my $body = encode_json($hdrs_to_send);

        # send request off to st-userd
        http_request POST => $self->userd_uri,
            headers => {
                'Referer'    => '',
                'User-Agent' => __PACKAGE__,
            },
            body    => $body,
            timeout => $self->timeout,
            sub {
                my ($resp_body, $resp_hdrs) = @_;
                my $creds;
                try {
                    if ($resp_hdrs->{Status} != 200) {
                        die "$resp_hdrs->{Status} $resp_hdrs->{Reason}\n";
                    }
                    else {
                        $creds = decode_json($resp_body);
                        $self->store_credentials_in_cache($hdrs_to_send, $creds)
                            if $can_cache
                    }
                }
                catch {
                    $creds = { error =>
                        "extract credentials error: $_" };
                };
                try { $cb->($creds) };
            };
    }
    catch {
        try { $cb->({error => $_}) };
    };
    return;
}

sub store_credentials_in_cache {
    my $self  = shift;
    my $hdrs  = shift;
    my $creds = shift;

    # creds not cachable; skip
    return unless $creds->{valid_for};

    # store the creds in the in-memory cache
    my $now  = time();
    my $key  = $self->_cache_key($hdrs);
    my $data = {
        valid_until => ($now + $creds->{valid_for}),
        credentials => $creds,
    };
    $self->cache->set($key, $data);
}

sub get_cached_credentials {
    my $self = shift;
    my $hdrs = shift;
    my $key  = $self->_cache_key($hdrs);

    # find the creds in the cache
    my $data = $self->cache->get($key);
    return unless $data;

    # if the creds are still valid, re-use those
    my $now = time();
    if ($data->{valid_until} > $now) {
        return $data->{credentials};
    }

    # remove this item from the cache; its not valid any more
    $self->cache->remove($key);
    return;
}

sub _cache_key {
    my $self = shift;
    my $hdrs = shift;
    my $key  = join '\0', map { $_ => $hdrs->{$_} } sort keys %{$hdrs};
    return $key;
}

__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

Socialtext::CredentialsExtractor::Client::Async - Asynchronous Creds Extraction

=head1 SYNOPSIS

  use Socialtext::CredentialsExtractor::Client::Async;

  my $client = Socialtext::CredentialsExtractor::Client::Async->new();
  $client->extract_credentials($env, sub {
      my $creds = shift;
      if ($creds->{valid}) {
          # Valid User found (which *COULD* be the Guest User)
      }
  } );

=head1 DESCRIPTION

This module implements an asynchronous, callback-style Credentials Extraction
client.

=cut
