package Socialtext::CredentialsExtractor::Extractor::SSLCertificate;

use Moose;
with 'Socialtext::CredentialsExtractor::Extractor';

use Net::LDAP::Util qw(ldap_explode_dn);

sub uses_headers {
    return qw(
        X_SSL_CLIENT_SUBJECT
    );
}

sub extract_credentials {
    my ($class, $hdrs) = @_;

    # Decline processing unless we've got a Client-Side-SSL Cert to use.
    my $subject = $hdrs->{X_SSL_CLIENT_SUBJECT};
    return unless $subject;

    # Get the Username out of the Certificate Subject.
    my $username = $class->_username_from_subject($subject);
    unless ($username) {
        my $user_field = $class->_username_field();
        my $msg = "invalid certificate subject or no '$user_field' field found";
        return $class->invalid_creds(reason => $msg);
    }

    my $user_id = $class->username_to_user_id($username);
    if ($user_id) {
        my $user = Socialtext::User->new(user_id => $user_id);
        $user->record_login;
        return $class->valid_creds(user_id => $user_id);
    }
    return $class->invalid_creds(reason => "invalid username: $username");
}

sub _username_from_subject {
    my $class      = shift;
    my $subject    = shift;
    my $fields     = $class->_explode_subject($subject);
    my $user_field = $class->_username_field();
    my ($username) =
        map  { $_->{$user_field} }
        grep { exists $_->{$user_field} } @{$fields};
    return $username;
}

sub _username_field {
    return 'CN';
}

sub _explode_subject {
    my $class   = shift;
    my $subject = shift;

    $subject =~ s{^/\s*}{}g;        # eliminate leading '/'s
    $subject =~ s{/\s*}{, }g;       # convert '/'s to ','s
    # XXX: doesn't accommodate "..., ..., .../..." (embedded slashes)

    # Split the subject up into its component fields.
    my $fields = ldap_explode_dn($subject);
    return $fields;
}

no Moose;

1;

=head1 NAME

Socialtext::CredentialsExtractor::Extractor::SSLCertificate - Extract creds from Client-Side SSL Certificate

=head1 SYNOPSIS

  # see Socialtext::CredentialsExtractor

=head1 DESCRIPTION

This module extracts credentials from a Client-Side SSL Certificate subject.

It is presumed that the certificate has already been verified/validated before
hand; this credentials extractor simply pulls the Username out of the
certificate subject and confirms that this is a known User.

=head1 SEE ALSO

L<Socialtext::CredentialsExtractor::Extractor>

=cut
