package Socialtext::LDAP::Config;
# @COPYRIGHT@

# NOTE: if you change the behaviour here, please make sure all of the pages
# listed in the "SEE ALSO" section are updated accordingly.

use strict;
use warnings;
use Class::Field qw(field const);
use Time::HiRes qw(gettimeofday);
use base qw(Socialtext::Config::Base);

###############################################################################
# Name our configuration file
const 'config_basename' => 'ldap.yaml';

###############################################################################
# Fields that the config file contains
field 'id';
field 'name';
field 'backend';
field 'base';
field 'host';
field 'port';
field 'bind_user';
field 'bind_password';
field 'filter';
field 'group_filter';
field 'follow_referrals' => 1;
field 'max_referral_depth' => 3;
field 'ttl' => 3600;
field 'not_found_ttl';
field 'attr_map';
field 'sslversion';
field 'group_attr_map' => +{};

# XXX: possible future config options:
#           timeout
#           localaddr

# XXX: the 'id' field does NOT need to be exposed to users via any sort of UI;
#      its for internally segregating one LDAP configuration from another,
#      even if the user goes in and changes all of the other information about
#      the connection (hostname, port, descriptive name, etc).

sub init {
    my $self = shift;

    # {bz: 4211} Common typo is 'bind_username' instead of 'bind_user':
    if (!$self->{bind_user} && $self->{bind_username}) {
        $self->{bind_user} = $self->{bind_username};
    }

    # default "not_found_ttl" to current "ttl" value
    unless ($self->{not_found_ttl}) {
        $self->{not_found_ttl} = $self->ttl();
    }

    # make sure we've got all required fields
    my @required = (qw( id host attr_map ));
    $self->check_required_fields(@required);

    # make sure we've got all required mapped User attributes
    my @req_attrs = (qw( user_id username email_address first_name last_name ));
    $self->check_required_mapped_user_attributes(@req_attrs);

    # make sure we've got all required mapped Group attributes
    @req_attrs = (qw( group_id group_name member_dn ));
    $self->check_required_mapped_group_attributes(@req_attrs);
}

sub check_required_mapped_user_attributes {
    my ($self, @attrs) = @_;
    my $attr_map = $self->attr_map();
    foreach my $attr (@attrs) {
        unless ($attr_map->{$attr}) {
            die "config missing mapped User attribute '$attr'\n";
        }
    }
}

sub check_required_mapped_group_attributes {
    my ($self, @attrs) = @_;

    # get the Group Attr Map.  Its OK to not have one (its optional)
    my $attr_map = $self->group_attr_map();
    return unless ($attr_map && %{$attr_map});

    # make sure that all of the required Group Attrs are mapped properly
    foreach my $attr (@attrs) {
        unless ($attr_map->{$attr}) {
            die "config missing mapped Group attribute '$attr'\n";
        }
    }
}

sub generate_driver_id {
    # NOTE: generated ID only has to be unique for -THIS- system, it doesn't
    # have to be universally unique across every install.

    # NOTE: generated ID should also be ugly enough that users aren't inclined
    # to want to go in and twiddle the value themselves; hex should be
    # sufficient to deter most users.

    my ($sec, $msec) = gettimeofday();
    my $id = sprintf( '%05x%05x', $msec, $$ );
    return $id;
}

1;

=head1 NAME

Socialtext::LDAP::Config - Configuration object for LDAP connections

=head1 SYNOPSIS

  # please refer to Socialtext::Base::Config

  # generate a new unique driver ID
  $driver_id = Socialtext::LDAP::Config->generate_driver_id();

=head1 DESCRIPTION

C<Socialtext::LDAP::Config> encapsulates all of the information for LDAP
connections in configuration object.

LDAP configuration objects can either be loaded from YAML files or created from
a hash of configuration values:

=over

=item B<id> (required)

A B<unique identifier> for the LDAP connection.  This identifier will be used
internally to help denote which LDAP configuration users reside in.

B<DO NOT change this value.>  Doing so will cause any existing users to no
longer be associated with this LDAP configuration.

=item B<name>

Specifies the name for the LDAP connection.  This is a I<descriptive name>,
B<not> the I<host name>.

=item B<backend>

Specifies the name of the LDAP back-end plug-in which is responsible for
connections to this LDAP server.

=item B<base>

Specifies the LDAP "Base DN" which is to be used for searches in the LDAP
directory.

=item B<host> (required)

Specifies a host (or list of hosts) that we are supposed to be connecting to.

Can be provided in any of the following formats:

  ip.add.re.ss
  hostname
  ldap://hostname
  ldaps://hostname

Any of the above formats may include a TCP port number (e.g. "127.0.0.1:389").

=item B<port>

Specifies the TCP port number that the connection should be made to.

=item B<bind_user>

Specifies the username that should be used when binding to the LDAP connection.
If not provided, an anonymous bind will be performed.

=item B<bind_password>

Specifies the password that should be used when binding to the LDAP connection.

=item B<filter>

Specifies a LDAP filter (e.g. C<(objectClass=inetOrgPerson)>) that should be
used to restrict LDAP searches to B<just User records>.

=item B<group_filter>

Specifies an LDAP filter (e.g. C<(objectClass=posixGroup)>) that should be
used to restrict LDAP searches to B<just Group records>.

=item B<follow_referrals>

Specifies whether or not LDAP referral responses from this server are followed
or not.  Defaults to "1" (follow referrals).

=item B<max_referral_depth>

Specifies the maximum depth to which LDAP referrals are followed.  Defaults to
"3".

=item B<ttl>

Specifies the TTL (in seconds) for data which is queried via this LDAP
instance.  Defaults to "3600" seconds (1 hour)

If you are using LDAP as a Group factory, it is recommended that you
B<increase> this TTL value.  When Groups are fetched from LDAP, all of the
Users in the Group are enumerated in order to verify that we have valid data
for them.  Larger Groups contain more Users and thus take more time to
enumerate/verify; please ensure that you have set a suitable value for the TTL
based on your Group size.

=item B<not_found_ttl>

Specifies the TTL (in seconds) for LDAP queries done that return "not found"
as a result.  Defaults to the configured C<ttl> value.

=item B<sslversion>

Forces the LDAPS connection to connect using the specified C<sslversion>.
Valid values include "tlsv1", "sslv3", and "sslv2".

Unless specified, we attempt to auto-detect the most secure SSL version.

=item B<attr_map> (required)

Maps Socialtext user attributes to their underlying LDAP representations.

=item B<group_attr_map>

Maps Socialtext Group attributes to their underlying LDAP representations.

=back

=head1 METHODS

=over

=item B<$self-E<gt>init()>

Custom initialization routtine.  Verifies that the configuration contains all
of the required fields and required mapped attributes.

=item B<Socialtext::LDAP::Config-E<gt>generate_driver_id()>

Generates a new unique driver identifier.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Socialtext::Config::Base>,
L<http://www.socialtext.net/open/index.cgi?ldap_configuration_options>.

=cut
