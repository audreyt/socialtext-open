package Socialtext::Challenger::NTLM;
# @COPYRIGHT@

use strict;
use warnings;
use base qw(Socialtext::Challenger::Base);
use Socialtext::Log qw(st_log);
use Socialtext::l10n qw(loc);
use Socialtext::UUID qw(new_uuid);

sub challenge {
    my $class    = shift;
    my %p        = @_;
    my $hub      = $p{hub};
    my $request  = $p{request};
    my $redirect = $p{redirect};

    # get a handle to the app
    my $app = Socialtext::WebApp->NewForNLW;

    # make sure we've got a request
    unless ($request) {
        $request = $app->apache_req;
    }

    # make sure we know where we want to redirect the User to
    unless ($redirect) {
        $redirect = $class->build_redirect_uri($request);
    }
    $redirect = $class->clean_redirect_uri($redirect);

    # default error is "User isn't logged in"
    my $type = 'not_logged_in';

    # default redirection URI is "the NTLM authentication URI"
    my $challenge_uri = $class->challenge_uri();

    # if we have a Hub and a User, we're already Authenticated (but apparently
    # don't have sufficient Authz).
    if ($hub and not $hub->current_user->is_guest) {
        # error type: unauthorized_workspace
        $type = 'unauthorized_workspace';

        # use an error page that has *no* login form on it.
        $challenge_uri = '/nlw/error.html';

        # log an error stating that this User isn't authorized to view this
        # Workspace.
        my $workspace = $hub->current_workspace;
        my $username  = $hub->current_user->username();
        my $message   = loc(
            "error.wiki-forbidden=user,wiki",
            $username . $workspace->title()
        );
        st_log->error($message);
    }

    # redirect the User to the Login URI, while setting the current error into
    # the session (so we can get at it later if needed).
    my %args = (
        workspace_title => $hub->current_workspace->title,
        workspace_id    => $hub->current_workspace->workspace_id,
    ) if ($hub and $hub->current_workspace);


    my $sid = new_uuid();
    
    return $app->_handle_error(
        error => {
            type => $type,
            args => \%args,
        },
        path  => $challenge_uri,
        query => { 
            redirect_to => $redirect,
            sid => $sid,
        },
    );
}

sub build_redirect_uri {
    my ($class, $request) = @_;
    return $request->parsed_uri->unparse;
}

sub challenge_uri {
    return '/nlw/ntlm';
}

1;

=head1 NAME

Socialtext::Challenger::NTLM - Custom challenger for NTLM Authentication

=head1 SYNOPSIS

  Do not instantiate this class directly.
  Use Socialtext::Challenger instead.

=head1 DESCRIPTION

When configured for use, this Challenger redirects Users off to the NTLM
Authentication URL (C</nlw/ntlm>) for NTLM authentication.

It is expected that the NTLM Authentication URL has been configured to use
C<Socialtext::Handler::NTLM> as the underlying Mod_perl handler, which will
redirect the User off to the URI provided to it (once it has been able to
verify that the User I<is> logged in, and sets a session cookie in their
browser).

=head1 METHODS

=over

=item B<Socialtext::Challenger::NTLM-E<gt>challenge(%p)>

Custom challenger.

Not to be called directly.  Use C<Socialtext::Challenger> instead.

=item B<Socialtext::Challenger::NTLM-E<gt>build_redirect_uri($request)>

Builds the URI that the User should be redirected to once they have been
authenticated, and returns that URI back to the caller.

=item B<Socialtext::Challenger::NTLM-E<gt>challenge_uri()>

Returns the URI that the User should be redirected to in order to get
Authenticated.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc., All Rights Reserved.

=head1 SEE ALSO

L<Socialtext::Challenger>,
L<Socialtext::Handler::NTLM>,
L<Socialtext::Apache::Authen::NTLM>.

=cut
