package Socialtext::LDAP::Base;
# @COPYRIGHT@

# NOTE: if you change the behaviour here, please make sure all of the pages
# listed in the "SEE ALSO" section are updated accordingly.

use strict;
use warnings;
use Class::Field qw(field);
use Net::LDAP;
use Net::LDAP::Constant qw(LDAP_REFERRAL);
use Net::LDAP::Util qw(escape_filter_value);
use URI::ldap;
use Socialtext::Log qw(st_log);
use Socialtext::Timer;

field 'config';

sub new {
    my ($class, $config) = @_;

    # must have config
    return unless $config;

    # create new object
    my $self = {
        config => $config,
        };
    bless $self, $class;

    # connect to the LDAP server
    $self->connect() or return;

    # return newly created LDAP connection back to caller
    return $self;
}

sub DESTROY {
    my $self = shift;
    # close any open LDAP connection
    if ($self->{ldap}) {
        $self->{ldap}->disconnect();
        delete $self->{ldap};
    }
}

sub connect {
    my ($self, %opts) = @_;

    # default connection options
    my $host = delete $opts{'host'} || $self->config->host();
    if ($self->config->port()) {
        $opts{port} ||= $self->config->port();
    }
    if ($self->config->sslversion()) {
        $opts{sslversion} ||= $self->config->sslversion();
    }

    # attempt connection
    $self->{ldap} = _ldap_connect($host, %opts);
    unless ($self->{ldap}) {
        my $host_str = ref($host) eq 'ARRAY' ? join(', ', @{$host}) : $host;
        st_log->error( "ST::LDAP::Base: unable to connect to LDAP server; $host_str" );
        return;
    }
    return $self;
}

sub _ldap_connect {
    my ($host, %opts) = @_;
    Socialtext::Timer->Continue('ldap_connect');
    my $ldap = Net::LDAP->new($host, %opts);
    Socialtext::Timer->Pause('ldap_connect');
    return $ldap;
}

sub bind {
    my $self = shift;
    my $user = $self->config->bind_user();

    # set up bind options
    my %opts = ();
    if ($self->config->bind_password()) {
        $opts{password} = $self->config->bind_password();
    }

    # attempt to bind to LDAP connection
    Socialtext::Timer->Continue('ldap_bind');
    my $mesg = _ldap_bind($self->{ldap}, $user, %opts);
    Socialtext::Timer->Pause('ldap_bind');
    if ($mesg->code()) {
        my $conn_str = $self->config->name() || $self->config->id();
        st_log->error( "ST::LDAP::Base: unable to bind to LDAP connection '$conn_str'; " . $mesg->error() );
        return;
    }
    return $self;
}

sub _ldap_bind {
    my ($ldap, $user, %opts) = @_;
    my $mesg = $ldap->bind($user, %opts);
    return $mesg;
}

sub authenticate {
    my ($self, $user_id, $password) = @_;

    # preserve our LDAP connection, in case we end up following referrals
    local $self->{ldap} = $self->{ldap};

    # if we're configured to follow referrals *AND* we've got a User ID to
    # authenticate with, go find out which LDAP server that user lives in;
    # might need to follow some referrals to do that.
    if ($user_id && $self->config->follow_referrals()) {
        my $user_id_field = $self->config->attr_map->{user_id};
        my $esc_user_id = escape_filter_value($user_id);
        my $mesg = $self->_do_following_referrals(
            action => sub {
                my $ldap = shift;
                return $ldap->search(
                    base    => $self->config->base(),
                    attrs   => [$user_id_field],
                    scope   => 'sub',
                    filter  => "(${user_id_field}=$esc_user_id)",
                );
            },
        );
        unless ($mesg) {
            st_log->info( "ST::LDAP::Base: unable to find user to authenticate as" );
            return;
        }
        if ($mesg->code()) {
            st_log->info( "ST::LDAP::Base: authentication failed; unable to find user '$user_id': " . $mesg->error() );
            return;
        }
    }

    # attempt to bind to the LDAP server with the provided credentials.
    my $mesg = $self->_do_following_referrals(
        'bind'   => sub { },
        'action' => sub {
            my $ldap = shift;
            return $ldap->bind($user_id, password=>$password);
        },
    );
    if ($mesg->code()) {
        st_log->info( "ST::LDAP::Base: authentication failed for user '$user_id'; " . $mesg->error() );
        return;
    }
    return 1;
}

sub search {
    my ($self, %args) = @_;

    # preserve our LDAP connection, in case we end up following referrals
    local $self->{ldap} = $self->{ldap};

    # do search, return results
    return $self->_do_following_referrals(
        action => sub {
            my $ldap = shift;
            return $ldap->search(%args);
        }
    );
}

# Performs an LDAP lookup, while also following LDAP referrals.
#
# Accepts a series of callback methods as arguments:
#
#   connect
#       method used to connect to the next LDAP server
#       called as: connect($host, %opts)
#
#   bind
#       method used to bind to the LDAP connection
#       called as: bind($ldap_conn, $user, %bind_options)
#
#
#   action
#       method used to perform requested LDAP lookup
#       called as: action($ldap_conn)
#
# LDAP referrals are followed in a "depth first" manner, and the first
# non-referral response retrieved is returned back to the caller.  If all of
# the LDAP referrals are exhausted before a suitable response is found, this
# method returns empty-handed.
sub _do_following_referrals {
    my $self = shift;
    my %callbacks = (
        'connect'   => \&_ldap_connect,
        'bind'      => \&_ldap_bind,
        'action'    => sub { die "no 'action' provided in call to _do_following_referrals()" },
        @_,
        );

    # invoke the CB and get the LDAP response message
    my $mesg = $callbacks{action}->( $self->{ldap} );

    # return the LDAP response immediately if either:
    #   a) its *not* an LDAP referral,
    #   b) we're not configured to follow LDAP referrals
    return $mesg unless ($mesg->code() == LDAP_REFERRAL);
    unless ($self->config->follow_referrals()) {
        st_log->info( "received LDAP referral response, but referral following disabled; not following" );
        return $mesg;
    }

    # follow the LDAP referrals in a depth-first manner, returning the first
    # answer we get thats *not* another LDAP referral response.
    my $max_depth = $self->config->max_referral_depth();
    my @referrals = map { [1, $_] } $mesg->referrals();
  REFERRAL:
    while (my $entry = shift @referrals) {
        my ($curr_depth, $referral) = @{$entry};

        # if we've reached the max referral depth, skip this referral
        if ($curr_depth > $max_depth) {
            st_log->warning( "max referral depth reached; not following LDAP referral: $referral" );
            next REFERRAL;
        }
        st_log->debug( "following LDAP referral: $referral" );

        # extract the info out of the LDAP referral response
        my $uri = URI::ldap->new($referral);
        my $scheme  = $uri->scheme();
        my $host    = $uri->host();
        my $port    = $uri->port();

        # connect to the LDAP server we've been referred to
        $self->{ldap} = $callbacks{connect}->("${scheme}://${host}", port=>$port);
        unless ($self->{ldap}) {
            st_log->warning( "ST::LDAP::Base: unable to connect while following LDAP referral: $referral" );
            next REFERRAL;
        }

        # bind the LDAP connection
        my $bind_user = $self->config->bind_user();
        my $bind_pass = $self->config->bind_password();
        st_log->debug( "ST::LDAP::Base: binding to LDAP referral as: $bind_user" );
        $mesg = $callbacks{bind}->($self->{ldap}, $bind_user, ($bind_pass ? (password=>$bind_pass) : ()));
        if ($mesg && $mesg->code()) {
            st_log->warning( "ST::LDAP::Base: unable to bind to LDAP referral '$referral'; " . $mesg->error() );
            next REFERRAL;
        }

        # invoke CB, and return immediately if its *NOT* an LDAP referral
        # response.
        $mesg = $callbacks{action}->( $self->{ldap} );
        return $mesg unless ($mesg->code() == LDAP_REFERRAL);

        # add the referrals to the list of things to follow
        my @more_referrals = map { [$curr_depth+1, $_ ]} $mesg->referrals();
        unshift @referrals, @more_referrals;
    }

    # XXX: if we got this far, we haven't found a suitable non-referral
    # response to hand back to the caller; all referrals led us to the maximum
    # referral depth.
    return;
} 

1;

=head1 NAME

Socialtext::LDAP::Base - Base class for LDAP plug-ins

=head1 SYNOPSIS

  use Socialtext::LDAP;

  # instantiate a new LDAP connection
  $ldap = Socialtext::LDAP->new();

  # performing a search against an LDAP directory
  $mesg = $ldap->search( %options );

  # authenticating against an existing LDAP connection
  # (see METHODS below for caveats on authorization/privileges)
  $auth_ok = $ldap->authenticate( $user_id, $password );

  # re-binding an LDAP connection (to reset authorization/privileges)
  $bind_ok = $ldap->bind();

=head1 DESCRIPTION

C<Socialtext::LDAP::Base> implements a base class for LDAP plug-ins, which
provides a generic LDAP implementation.  LDAP back-end plug-ins which require
custom behaviour can derive and over-ride methods as needed.

=head1 METHODS

=over

=item B<Socialtext::LDAP::Base-E<gt>new($config)>

Instantiates a new LDAP object and connects to the LDAP server.  Returns the
newly created object on success, false on any failure.

C<connect()> is called automatically, but you will be responsible for binding
or authenticating against the connection yourself.

=item B<connect()>

Connects to the LDAP server, using the configuration provided at
instantiation.  Returns true on success, false on failure.

Called automatically by C<new()>.

=item B<bind()>

Binds to the LDAP connection, using the configuration provided at
instantiation.  Returns true on success, false on failure.

=item B<authenticate($user_id, $password)>

Attempts to authenticate against the LDAP connection, using the provided
C<$user_id> and C<$password>.  Returns true if successful, false otherwise.

If following of LDAP referrals is enabled, a search is done to locate the user
in your LDAP directory prior to authentication (so we know we're connected to
the LDAP server that contains the user we're authenticating as).

B<NOTE:> after calling C<authenticate()>, the LDAP connection will be bound
using the provided C<$user_id>; any further method calls will be done
with the privileges and authorization granted to that user.  If you wish to
reset the connection back to its original privileges, simply call C<bind()>
to re-bind the connection and reset its privileges.

=item B<search(%opts)>

Performs a search against the LDAP connection, using B<ONLY> the LDAP
C<filter> provided in the C<%opts>.  This method B<no longer> applies the
global LDAP C<filter> to the search automatically; that filter is now applied
by C<Socialtext::User::LDAP::Factory> when doing a search for User records.

Accepts all of the parameters that C<Net::LDAP::search()> does (refer to
L<Net::LDAP> for more information).  Returns a C<Net::LDAP::Search> object back
to the caller.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Net::LDAP>,
L<http://www.socialtext.net/open/index.cgi?howto_configure_the_ldap_plugin>.

=cut
