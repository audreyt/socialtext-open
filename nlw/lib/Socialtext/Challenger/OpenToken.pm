package Socialtext::Challenger::OpenToken;
# @COPYRIGHT@

use strict;
use warnings;
use base qw(Socialtext::Challenger::Base);
use Crypt::OpenToken;
use URI;
use MIME::Base64;
use Socialtext::Apache::User;
use Socialtext::l10n qw(loc);
use Socialtext::Log qw(st_log);
use Socialtext::OpenToken::Config;
use Socialtext::User;
use Socialtext::WebApp;

sub challenge {
    my $class    = shift;
    my %p        = @_;
    my $hub      = $p{hub};
    my $request  = $p{request};
    my $redirect = $p{redirect};

    # make sure we've got a request
    my $app = Socialtext::WebApp->NewForNLW;
    unless ($request) {
        $request = $app->apache_req;
    }

    # get a handle to the OpenToken configuration
    my $config = Socialtext::OpenToken::Config->load();
    unless ($config) {
        return $app->_handle_error(
            error => 'OpenToken configuration missing/invalid.',
            path  => '/nlw/error.html',
        );
    }

    # if we have a Hub *AND* a User, we're Authentiated but not Authorized;
    # show the User a page letting them know that they don't have permission.
    if ($hub and not $hub->current_user->is_guest) {
        st_log->debug( 'ST::Challenger::OpenToken: unauthorized access, showing error page to user' );
        return $app->_handle_error(
            error => {
                type => 'unauthorized_workspace',
            },
            path    => '/nlw/error.html',
        );
    }

    # figure out where the User is supposed to be redirected to after the
    # challenge is successful.
    $redirect ||= $class->get_redirect_uri($request);
    $redirect = $class->clean_redirect_uri($redirect);

    # figure out where we need to redirect the User to in order to get an
    # OpenToken, in the event that we're either not Authenticated or we have
    # some problem with the OpenToken.
    my $challenge_uri = $class->build_challenge_uri($config, $redirect);

    # get the OpenToken as provided in the "opentoken" form parameter
    my $token_param = $config->token_parameter;
    my $token_str   = $request->param($token_param);
    unless ($token_str) {
        st_log->info("ST::Challenger::OpenToken: no token provided, redirecting");
        return $app->redirect($challenge_uri);
    }

    # parse/dissect the OpenToken
    my $password = decode_base64($config->password);
    my $factory  = Crypt::OpenToken->new(password => $password);
    my $token    = eval { $factory->parse($token_str) };
    if ($@) {
        st_log->warning("ST::Challenger::OpenToken: error occurred while parsing token; $@");
        return $app->redirect($challenge_uri);
    }
    unless ($token) {
        st_log->warning("ST::Challenger::OpenToken: unable to parse token; $@");
        return $app->redirect($challenge_uri);
    }

    # make sure that the token is valid
    my $skew = $config->clock_skew();
    unless ($token->is_valid(clock_skew => $skew)) {
        st_log->info("ST::Challenger::OpenToken: invalid token, redirecting");
        return $app->redirect($challenge_uri);
    }

    # extract the username from the token, and go lookup the User
    my $username = $token->subject();
    my $user     = eval { Socialtext::User->new(username => $username) };

    # Optionally auto-provision the User
    my $auto_provision = $config->auto_provision_new_users;
    if ($auto_provision) {
        # Extract the User data from the OpenToken
        my $data = $token->data;
        my %proto_user =
            map  { $_ => $data->{$_} }
            grep { defined $data->{$_} }
            qw(subject email_address first_name middle_name last_name);
        $proto_user{username} = delete $proto_user{subject};    # map this field

        # Create/Update the User record as necessary.
        my $action = '';
        eval {
            if ($user) {
                $action = 'update';
                $class->_update_user($user, %proto_user);
            }
            else {
                $action = 'create';
                st_log->info("ST::Challenger::OpenToken: auto-provisioning user '$username'");
                $user = $class->_create_user(%proto_user);
            }
        };
        if (my $e = Exception::Class->caught('Socialtext::Exception::DataValidation')) {
            my $msg = join ', ', $e->messages;
            st_log->error( "ST::Challenger::OpenToken: unable to $action user; $msg" );
            return;
        }
        elsif ($e = $@) {
            st_log->error( "ST::Challenger::OpenToken: failed to $action user; $e" );
            return;
        }
    }

    # If we don't have a User record, it wasn't provisioned; can't login as
    # the User, so fail.
    unless ($user) {
        my $err = loc("error.valid-token-for-unknown=user", $username);
        st_log->warning("ST::Challenger::OpenToken: $err");
        return $app->_handle_error(
            error => $err,
            path  => '/nlw/error.html',
        );
    }

    # figure out where the User wanted to be in the first place, and redirect
    # them off over there.
    st_log->info("LOGIN: " . $user->email_address . " destination $redirect");
    Socialtext::Apache::User::set_login_cookie($request, $user->user_id, '');
    $user->record_login;
    return $app->redirect($redirect);
}

sub _update_user {
    my ($class, $user, %proto_user) = @_;
    if ($user->can_update_store) {
        $user->update_store(%proto_user);
    }
}

sub _create_user {
    my ($class, %proto_user) = @_;

    # Generate a random password for the User so that we've got _something_ in
    # there.  Otherwise, checks for "has_valid_password()" will fail and the
    # User won't ever be allowed to log in.
    my $password = $class->_generate_random_password(32);
    $proto_user{password} = $password;

    # Create the User record.
    my $user = Socialtext::User->create(%proto_user);
    return $user;
}

sub _generate_random_password {
    my ($class, $length) = @_;
    my @valid = ('a'..'z', 'A'..'Z', '0'..'9');
    my $pass = '';
    while ($length-- >= 0) {
        my $offset = rand(scalar @valid);
        $pass .= $valid[$offset];
    }
    return $pass;
}

# Returns the URL which kickstarts a SP-initiated SAML assertion.
sub build_challenge_uri {
    my ($class, $config, $redirect) = @_;

    # start with the configured Challenge URI
    my $challenge_uri = URI->new($config->challenge_uri);

    # build a target URI; the URI that the User should be sent to after being
    # successfully authenticated, so that we can then log them in and redirect
    # them to the resource that they were originally trying to access.
    my $target_uri;
    {
        $target_uri = Socialtext::URI::uri(
            path  => '/challenge',
            query => { redirect_to => $redirect }
        );
    }

    my @form = $challenge_uri->query_form();
    $challenge_uri->query_form(@form, TARGET => $target_uri);
    return $challenge_uri->as_string;
}

# Returns the URI to redirect the User to *after* a successful Authen
# handshake.
#
# We do *not* allow for redirects to send the User to a machine other than
# ourselves.
sub get_redirect_uri {
    my ($self, $request) = @_;

    # get the URL that we're supposed to be redirecting the User to
    my $redirect
        = $request->param('redirect_to') || $request->parsed_uri->unparse;

    # make sure that regardless of whether the Redirect URI is absolute or
    # relative, that it points to *THIS* server.
    my $uri = URI->new($redirect);
    if ($uri->scheme) {
        # given an absolute URI; if it points to somewhere _other_than_
        # this machine, fail
        my $host      = $uri->host();
        my $this_host = Socialtext::AppConfig->web_hostname();
        if ($host ne $this_host) {
            st_log->error(
                "ST::Challenger::OpenToken; redirect attempted to external source; $redirect"
            );
            return $self->default_redirect_uri;
        }
    }

    # strip off any query param containing the token parameter
    my $config = Socialtext::OpenToken::Config->load();
    my $param  = $config->token_parameter;
    my %query  = $uri->query_form;
    delete $query{$param};
    delete $query{''};          # PingFederate sends empty query param back
    $uri->query_form(\%query);

    # return the relative form of the URI back to the caller.
    return $uri->path_query();
}

1;

=head1 NAME

Socialtext::Challenger::OpenToken - Custom challenger for OpenToken integration

=head1 SYNOPSIS

  Do not instantiate this class directly.
  Use Socialtext::Challenger instead.

=head1 DESCRIPTION

When configured for use, this Challenger redirects Users off to an OpenToken
Service Provider to perform authentication.

The Service Provider will then verify the User's identity against an Identity
Provider and then redirect the User back to us with an OpenToken.  This
OpenToken will then contain the information that we need to know about this
User in order to authenticate them and log them in to the system.

This module can be used to integrate a Socialtext Appliance into a SAML
infrastructure using a SAML Service Provider application such as PingFederate.

=head1 CONFIGURATION

The configuration for the OpenToken Challenger resides in
F</etc/socialtext/opentoken.yaml>, and is documented in
L<Socialtext::OpenToken::Config>.

A note of importance is that if you wish to auto-provision new Users, you will
B<need> to make sure that the following attributes are provided in the
OpenToken:

=over

=item subject

=item email_address

=item first_name

=item last_name

=back

Optionally, the following additional attributes may be also be set or updated via auto-provisioning:

=over

=item middle_name

=back

=head1 METHODS

=over

=item B<Socialtext::Challenger::OpenToken-E<gt>challenge(%p)>

Custom challenger.

Not to be called directly.  Use C<Socialtext::Challenger> instead.

=item B<Socialtext::Challenger::OpenToken-E<gt>build_challenge_uri($config, $request)>

Builds the URI that the User should be redirected to in order to get
Authenticated.

=item B<Socialtext::Challenger::OpenToken-E<gt>get_redirect_uri($redirect)>

Returns the URI to redirect the User to B<after> a successful Authentication
has been performed.

Redirects to I<external> URLs is B<forbidden>.  Attempts to redirect the User
off of the Socialtext Appliance to an external URL will result in an error
being logged and the User being redirected to the default URI ("/").

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2010 Socialtext, Inc., All Rights Reserved.

=head1 SEE ALSO

L<Socialtext::Challenger>,
L<Crypt::OpenToken>.

=cut
