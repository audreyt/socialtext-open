package Socialtext::Apache::AuthenHandler;
# @COPYRIGHT@

use strict;
use warnings;

use Apache::Constants qw(OK HTTP_UNAUTHORIZED HTTP_INTERNAL_SERVER_ERROR);
use Readonly;
use Socialtext::Authen;
use Socialtext::Apache::User;
use Socialtext::AppConfig;
use Socialtext::Exceptions 'throw_undef_method';

=head1 NAME

Socialtext::Apache::AuthenHandler - A variable PerlAuthenHandler which works against Socialtext::Authen.

=head1 SYNOPSIS

 <Location /foo>
   PerlAddVar SocialtextAuthenActions check_basic
   PerlAddVar SocialtextAuthenActions http_401
   PerlAuthenHandler Socialtext::Apache::AuthenHandler-
 </Location>

=head1 DESCRIPTION

The handler tries each of your actions in turn.  It expects the last action
listed to be what to do in case of failure.

=cut

Readonly my $SERVICE => __PACKAGE__;

=head1 METHODS

=head2 handler

Mod_perl handler.

=cut

sub handler {
    my ($r) = @_;

    my @actions = $r->dir_config->get('SocialtextAuthenActions');
    my $failure = pop @actions;

    my $result = eval {
        foreach my $action (@actions) {
            return OK if _try_to( $r, $action );
        }
        return _try_to( $r, $failure );
    };
    if ( UNIVERSAL::isa( $@, 'Socialtext::Exception::UndefinedMethod' ) ) {
        $r->log_error( "$SERVICE: ", $@->method, " is undefined." );
        return HTTP_INTERNAL_SERVER_ERROR;
    }
    elsif ($@) {
        die;
    }
    return $result;
}

sub _try_to {
    my ($r, $action) = @_;

    return __PACKAGE__->can($action)
        ? eval "$action(\$r)"
        : throw_undef_method class => __PACKAGE__, method => $action;
}

# TODO: Put in login.html-redirecting methods.

=head1 AUTHENTICATION ACTIONS

=head2 check_basic

Authenticates against HTTP Basic authentication username and password.

=cut

# Return 1 if able to authenticate via HTTP Basic, (0, CODE) if not, where
# CODE is what handler should return.
sub check_basic {
    my ($r) = @_;
    my ( $result, $sent_password ) = $r->get_basic_auth_pw;

    return ( $result == OK ) ? _authenticate_with( $r, $sent_password ) : 0;
}

# Returns 1 if the current user authenticates with the supplied password, 0 if
# not.
sub _authenticate_with {
    my ( $r, $password ) = @_;
    my $username = $r->connection->user;

    if ( $username eq '' ) {
        $r->log_reason( "$SERVICE - no username given", $r->uri );
        return 0;
    }
    elsif ( _authenticates( $username, $password ) ) {
        return 1;
    }

    $r->note_basic_auth_failure;
    $r->log_reason(
        "$SERVICE unable to authenticate $username for " . $r->uri );
    return 0;
}

sub _authenticates {
    my ( $username, $password ) = @_;

    my $auth = Socialtext::Authen->new();

    return (
        $auth->check_password(
            username => $username,
            password => $password,
        )
    );
}

=head2 check_cookie

Checks to see if the request could be authenticated via a registered
Credentials Extractor.  Returns 1 if it can, 0 otherwise.

As a side-effect, this method also sets C<$r-E<gt>connection-E<gt>user()> to
the logged in username.

Yes, this is poorly named; we do have other Credentials Extractors that aren't
cookie based.

=cut

sub check_cookie {
    my ($r) = @_;

    if ( my $user = Socialtext::Apache::User::current_user($r) ) {
        return 0 if $user->username eq Socialtext::User->Guest->username;
        $r->connection->user( $user->username );
        return 1;
    }

    return 0;
}

=head1 FAILURE ACTIONS

=head2 http_401

Returns C<HTTP 401> Unauthorized to the client.

=cut

sub http_401 { HTTP_UNAUTHORIZED }

=head1 SEE ALSO

L<Socialtext::Authen>,
L<http://www.w3.org/Protocols/HTTP/1.0/draft-ietf-http-spec.html#BasicAA>

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
