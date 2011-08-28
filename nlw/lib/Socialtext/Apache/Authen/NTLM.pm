package Socialtext::Apache::Authen::NTLM;
# @COPYRIGHT@
use strict;
use warnings;
use Apache::Constants qw(HTTP_UNAUTHORIZED HTTP_FORBIDDEN HTTP_INTERNAL_SERVER_ERROR OK DECLINED);
use LWP::UserAgent;
use Socialtext::NTLM::Config;
use Socialtext::Log qw(st_log);
use Socialtext::l10n qw(loc);
use Socialtext::Session;
use Socialtext::HTTP::Ports;

# mod_perl authen handler:
sub handler {
    my $r = pop;

    # turn HTTP KeepAlive requests *ON*, only really affects apache2 front-end
    st_log->debug( "turning HTTP Keep-Alives back on" );
    $r->subprocess_env(nokeepalive => undef);

    my $rc = call_ntlm_daemon($r);
    if ($rc == HTTP_UNAUTHORIZED) {
        _set_session_error( $r, { type => 'not_logged_in' } );
    }
    elsif ($rc == HTTP_FORBIDDEN) {
        _set_session_error( $r, { type => 'unauthorized_workspace' } );
    }
    elsif ($rc == HTTP_INTERNAL_SERVER_ERROR) {
        $rc = HTTP_FORBIDDEN;
        _set_session_error( $r, loc(
            "error.ntlm"
        ) );
    }
    st_log->debug( "NTLM authen handler rc: $rc" );

    return $rc;
}

sub call_ntlm_daemon {
    my $r = shift;

    my $authz_in = $r->header_in('Authorization');
    unless ($authz_in) {
        $r->err_headers_out->add('WWW-Authenticate' => 'NTLM');
        return HTTP_UNAUTHORIZED;
    }

    my $ua = LWP::UserAgent->new;
    my $port = Socialtext::HTTP::Ports->ntlmd_port;
    my $uri = $r->uri;
    $uri = "/$uri" unless $uri =~ m#^/#;
    my $ntlmd_url = 'http://localhost:'.$port.$uri.'?'.$r->args;
    my $req = HTTP::Request->new('GET' => $ntlmd_url);
    
    $req->header('X-Authorization' => $authz_in);
    my $resp = $ua->request($req);

    if (!$resp->is_success) {
        st_log->error("Unexpected NTLM daemon response: ".$resp->status_line);
        return HTTP_INTERNAL_SERVER_ERROR;
    }

    my $authn_out = $resp->header('X-WWW-Authenticate');
    $r->err_headers_out->add('WWW-Authenticate' => $authn_out) if $authn_out;

    my $authn_user = $resp->header('X-User');
    $r->user($authn_user) if $authn_user;

    my $authn_status = $resp->header('X-Status');
    # Special tokens are used for OK and DECLINED to avoid loading gross
    # Apache::Constants module on the daemon side:
    if ($authn_status eq 'OK') {
        $authn_status = OK; # note: not necessarily "200"
    }
    elsif ($authn_status eq 'DECLINED') {
        $authn_status = DECLINED;
    }

    return $authn_status;
}

###############################################################################
# Throws away any error(s) in the current session and sets the error to the
# given error.
sub _set_session_error {
    my ($r, $error) = @_;
    my $session    = Socialtext::Session->new($r);
    my $throw_away = $session->errors();
    $session->add_error( $error );
}

1;

=head1 NAME

Socialtext::Apache::Authen::NTLM - Custom Apache NTLM Authentication handler

=head1 SYNOPSIS

  # In your Apache/Mod_perl config
  <Location /nlw/ntlm>
    SetHandler          perl-script
    PerlHandler         +Socialtext::Handler::Redirect
    PerlAuthenHandler   +Socialtext::Apache::Authen::NTLM
    Require             valid-user
  </Location>

=head1 DESCRIPTION

C<Socialtext::Apache::Authen::NTLM> is a custom Apache/Mod_perl authentication
handler, that uses NTLM for authentication and is derived from
C<Apache::AuthenNTLM>.  Please note that only NTLM v1 is implemented at this
time.

=head1 METHODS

=over

=item B<Socialtext::Apache::Authen::NTLM-E<gt>handler($request)>

Over-ridden C<handler()> method, which forcably turns B<on> HTTP Keep-Alive
requests before letting our base class to its work.

This re-enabling of Keep-Alive requests is required as they're auto-disabled
by C<Socialtext::InitHandler>.

=item B<$self-E<gt>get_config($request)>

Over-ridde C<get_config()> method, which reads in our configuration from
C<Socialtext::NTLM::Config>, instead of expecting it to be configured in the
Apache/Mod_perl configuration files.

You I<can> still use the Apache/Mod_perl configuration file to define NTLM
configuration, but this configuration will be supplemented/over-written by the
configuration read using C<Socialtext::NTLM::Config>.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc., All Rights Reserved.

=head1 SEE ALSO

L<Apache::AuthenNTLM>,
L<Socialtext::InitHandler>,
L<Socialtext::NTLM::Config>.

=cut
