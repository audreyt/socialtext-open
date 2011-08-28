package Socialtext::CredentialsExtractor::Extractor::BasicAuth;
# @COPYRIGHT@

use Moose;
use MIME::Base64 qw(decode_base64);
with 'Socialtext::CredentialsExtractor::Extractor';

use Socialtext::User;

sub uses_headers {
    return qw(AUTHORIZATION);
}

sub extract_credentials {
    my ($class, $hdrs) = @_;

    # Get the "Authorization" header and make sure that its BasicAuth
    my $authz = $hdrs->{AUTHORIZATION};
    return unless $authz;
    return unless ($authz =~ s/^\s*Basic\s+//); # check + strip in one step

    # Grab the user/pass out of the header
    my ($username, $password) = split /:/, decode_base64($authz), 2;
    unless ($username && $password) {
        return $class->invalid_creds(reason => 'missing username or password')
    }

    # Check that the user/pass is valid
    my $user = Socialtext::User->new(username => $username);
    if ($user && $user->password_is_correct($password)) {
        return $class->valid_creds(user_id => $user->user_id);
    }
    return $class->invalid_creds(reason => 'invalid username or password');
}

no Moose;

1;

=head1 NAME

Socialtext::CredentialsExtractor::Extractor::BasicAuth - Extract creds from HTTP BasicAuth headers

=head1 SYNOPSIS

  # see Socialtext::CredentialsExtractor

=head1 DESCRIPTION

This module extracts credentials from standard HTTP BasicAuth headers.

=head1 SEE ALSO

L<Socialtext::CredentialsExtractor::Extractor>

=cut
