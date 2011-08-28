package Socialtext::CredentialsExtractor::Extractor::Cookie;
# @COPYRIGHT@

use Moose;
with 'Socialtext::CredentialsExtractor::Extractor';

use Socialtext::JSON qw(json_bool);
use Socialtext::HTTP::Cookie;

sub uses_headers {
    # UA needed for ST::HTTP::Cookie to determine which UA cookie to use
    # (NLW, or AIR)
    return qw(COOKIE USER_AGENT);
}

sub extract_credentials {
    my ($class, $hdrs) = @_;

    local $ENV{HTTP_COOKIE}     = $hdrs->{COOKIE}     || '';
    local $ENV{HTTP_USER_AGENT} = $hdrs->{USER_AGENT} || '';

    unless (Socialtext::HTTP::Cookie->AuthCookiePresent) {
        # No cookie; skip this Creds Extractor.
        return;
    }

    my $user_id = Socialtext::HTTP::Cookie->GetValidatedUserId;
    unless ($user_id) {
        return $class->invalid_creds(reason => 'invalid cookie');
    }

    my $needs_renewal = Socialtext::HTTP::Cookie->NeedsRenewal;
    return $class->valid_creds(
        user_id       => $user_id,
        needs_renewal => json_bool($needs_renewal),
        valid_for     => 60,             # XXX: let userd client cache for 60s
    );
}

no Moose;

1;

=head1 NAME

Socialtext::CredentialsExtractor::Extractor::Cookie - Extract creds for Socialtext authentication cookie

=head1 SYNOPSIS

  # see Socialtext::CredentialsExtractor

=head1 DESCRIPTION

This module extracts credentials from the Socialtext authentication cookie, using C<Socialtext::HTTP::Cookie>.

=head1 SEE ALSO

L<Socialtext::CredentialsExtractor::Extractor>

=cut
