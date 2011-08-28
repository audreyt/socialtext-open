package Socialtext::Apache::User;
# @COPYRIGHT@

use strict;
use warnings;
use Apache::Cookie;
use Digest::SHA ();
use Socialtext::AppConfig;
use Socialtext::CredentialsExtractor::Client::Sync;
use Socialtext::User;
use Socialtext::HTTP::Cookie;

# Note: A parallel version of this code lives in Socialtext::CGI::User
# so if this mechanism changes, we need to change the CGI version too
# (or merge them together).

sub set_login_cookie {
    my $r = shift;
    my $id = shift;
    my $expire = shift;
    my $value = Socialtext::HTTP::Cookie->BuildCookieValue(user_id => $id);

    _login_cookie( $r, $value, $expire );
}


sub unset_login_cookie {
    my $r = shift;

    _login_cookie( $r, '', '-1M' );
}

sub _login_cookie {
    my $r = shift;
    my $value = shift;
    my $expire = shift;
    my $cookie_name = Socialtext::HTTP::Cookie->cookie_name();

    _set_cookie( $r, $cookie_name, $value, $expire );
}

sub current_user {
    my $r      = shift;
    my $client = Socialtext::CredentialsExtractor::Client::Sync->new();
    my %env    = (
        $r->cgi_env,
        AUTHORIZATION => $r->header_in('Authorization'),
    );
    my $creds  = $client->extract_credentials(\%env);
    return unless ($creds->{valid});
    return if ($creds->{user_id} == Socialtext::User->Guest->user_id);

    my $user = Socialtext::User->new(user_id => $creds->{user_id});
    $r->connection->user($user->username) unless $r->connection->user();
    return $user;
}

sub _set_cookie {
    my $r       = shift;
    my $name    = shift;
    my $value   = shift;
    my $expires = shift;

    my $ssl_only = Socialtext::AppConfig->ssl_only ? 1 : 0;

    Apache::Cookie->new(
        $r,
        -name     => $name,
        -value    => $value,
        -expires  => $expires,
        -secure   => $ssl_only,
        -path     => '/',
        ( Socialtext::AppConfig->cookie_domain
            ? (-domain => '.' . Socialtext::AppConfig->cookie_domain)
            : ()
        ),
    )->bake;
}


1;

=head1 NAME

Socialtext::Apache::User - The great new Socialtext::Apache::User!

=head1 SYNOPSIS

  my $user_id = Socialtext::Apache::User::user_id($r);
  Socialtext::Apache::User::set_login_cookie( ... );

=head1 DESCRIPTION

C<Socialtext::Apache::User> provides some helper methods to get information on
the current User, and to set/query the login cookie.

B<NOTE:> a parallel version of this code lives in C<Socialtext::CGI::User>.
If this mechanism changes, we need to change the CGI version too.  Eventually
we'd like to merge them together into a single API, but we haven't gotten
there yet.

=head1 METHODS

=over

=item B<set_login_cookie($request, $user_id, $expires)>

Sets a login cookie into the provided Apache C<$request> object for the User
identified by the given C<$user_id>.  Unless a C<$expires> is given, the
cookie will be a "session cookie" (and will expire when the browser closes).
C<$expires> can be given in any format usable by C<Apache::Cookie>.

=item B<unset_login_cookie($request)>

Clears any existing session cookie that may exist in the browser.

=item B<current_user($request)>

Returns a C<Socialtext::User> object for the currently authenticated User, and
sets C<$user->username> into the Apache C<$request> object as the currently
authenticated username.

=back

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc. All Rights Reserved.

=cut
