package Socialtext::Challenger::STLogin;
# @COPYRIGHT@

use strict;
use warnings;
use base qw(Socialtext::Challenger::Base);
use Socialtext::Log qw(st_log);

=head1 NAME

Socialtext::Challenger::STLogin - Challenge with the default login screen

=head1 SYNOPSIS

    Do not instantiate this class directly. Use L<Socialtext::Challenger>

=head1 DESCRIPTION

When configured for use, this Challenger will redirect a request
to the default Socialtext login screen.

=head1 METHODS

=over

=item B<Socialtext::Challenger::STLogin-E<gt>challenge(%p)>

Custom challenger.

Not to be called directly.  Use C<Socialtext::Challenger> instead.

=back

=cut

# Send this request to the NLW challenge screen
sub challenge {
    my $class    = shift;
    my %p        = @_;
    my $hub      = $p{hub};
    my $request  = $p{request};
    my $redirect = $p{redirect};
    my $type     = 'not_logged_in';
    # if we were to decline to do this challenge
    # we should return false before going on

    my $app = Socialtext::WebApp->NewForNLW;
    unless ($request) {
        $request = $app->apache_req;
    }
    unless (defined $redirect) {
        $redirect = $request->parsed_uri->unparse;
    }
    $redirect = $class->clean_redirect_uri($redirect);

    my $ws;
    if ($hub) {
        $ws = $hub->current_workspace;
        if ( !$hub->current_user->is_guest ) {
            $type = 'unauthorized_workspace';
            st_log->error('User ' . $hub->current_user->email_address .
                          ' is not authorized to view workspace ' .
                          $hub->current_workspace->title);
        }
    }
    $type = $p{type} ? $p{type} : $type;

    # Figure out which login to use; mobile, or regular?
    my $login_page
        = $class->is_mobile($redirect) ? '/m/login' : '/nlw/login.html';

    # If the error is "You're not logged in", just show the login page.
    if ($type eq 'not_logged_in') {
        $app->redirect(
            path  => $login_page,
            query => {
                ($redirect ? (redirect_to => $redirect) : ()),
            },
        );
    }

    # Otherwise, show a more detailed error.
    my $workspace_title = $ws ? $ws->title        : '';
    my $workspace_id    = $ws ? $ws->workspace_id : '';
    $app->_handle_error(
        error => {
            type => $type,
            args => {
                workspace_title => $workspace_title,
                workspace_id    => $workspace_id,
            },
        },
        path  => $login_page,
        query => {
            ($redirect ? (redirect_to => $redirect) : ()),
        },
    );
}

1;

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2007 Socialtext, Inc., All Rights Reserved.

=cut
