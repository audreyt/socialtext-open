package Socialtext::CredentialsExtractor::Extractor::RemoteUser;
# @COPYRIGHT@

use Moose;
with 'Socialtext::CredentialsExtractor::Extractor';

sub uses_headers {
    return qw(REMOTE_USER);
}

sub extract_credentials {
    my ($class, $hdrs) = @_;
    my $username = $hdrs->{REMOTE_USER};
    return unless $username;

    my $user_id = $class->username_to_user_id($username);
    return $class->valid_creds(user_id => $user_id) if ($user_id);
    return $class->invalid_creds(reason => "invalid username: $username");
}

no Moose;

1;

=head1 NAME

Socialtext::CredentialsExtractor::Extractor::RemoteUser - Extract creds from already validate REMOTE_USER

=head1 SYNOPSIS

  # see Socialtext::CredentialsExtractor

=head1 DESCRIPTION

This module extract credentials from an already authenticated C<REMOTE_USER>;
e.g. the User has been authenticated via the webserver which has then exposed
their username to us as a C<REMOTE_USER> environment variable.

=head1 SEE ALSO

L<Socialtext::CredentialsExtractor::Extractor>

=cut
