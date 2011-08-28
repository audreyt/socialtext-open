package Socialtext::CredentialsExtractor::Extractor::SiteMinder;
# @COPYRIGHT@

use Moose;
with 'Socialtext::CredentialsExtractor::Extractor';

our $USER_HEADER = 'SM_USER';
our $SESS_HEADER = 'SM_SERVERSESSIONID';

sub uses_headers {
    return ($USER_HEADER, $SESS_HEADER);
}

sub extract_credentials {
    my ($class, $hdrs) = @_;

    # Make sure that a "SM_SERVERSESSIONID" exists.
    #
    # Don't care what the Session Id is, just that one exists; once the User
    # logs out it is possible to still have an SM_USER header, but there won't
    # be an active Session any more.
    unless ($hdrs->{$SESS_HEADER}) {
        $class->log('info', 'No active SiteMinder session; skipping');
        return;
    }

    # Get the "SM_USER" header; the "username" of the logged in user
    my $username = $hdrs->{$USER_HEADER};
    $username =~ s/^[^\\]+\\// if $username; # remove a DOMAIN\ prefix if any
    unless ($username) {
        $class->log('info', "SiteMinder $USER_HEADER missing or empty");
        return;
    }

    # Get the UserId for the User.
    my $user_id = $class->username_to_user_id($username);
    return $class->valid_creds(user_id => $user_id) if ($user_id);
    return $class->invalid_creds(reason => "invalid username: $username");
}

1;

=head1 NAME

Socialtext::CredentialsExtractor::Extractor::SiteMinder - Extract creds from SiteMinder reverse proxy headers

=head1 SYNOPSIS

  # see Socialtext::CredentialsExtractor

=head1 DESCRIPTION

This module extracts credentials from the HTTP headers provided by a SiteMinder reverse proxy.

=head1 SEE ALSO

L<Socialtext::CredentialsExtractor::Extractor>,
http://schmurgon.net/blogs/christian/archive/2006/08/13/50.aspx

=cut
