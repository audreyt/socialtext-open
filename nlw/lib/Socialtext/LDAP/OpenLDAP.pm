package Socialtext::LDAP::OpenLDAP;
# @COPYRIGHT@

use strict;
use warnings;
use base 'Socialtext::LDAP::Base';

1;

=head1 NAME

Socialtext::LDAP::OpenLDAP - LDAP plug-in for OpenLDAP servers

=head1 SYNOPSIS

  # Example entry in ldap.yaml
  id: 0e69907405
  name: Our OpenLDAP server
  backend: OpenLDAP
  host: openldap.example.com
  port: 389
  base: cn=IT,dc=example,dc=com
  filter: (objectClass=inetOrgPerson)
  follow_referrals: 1
  max_referral_depth: 3
  attr_map:
    user_id: dn
    username: cn
    email_address: mail
    first_name: givenName
    last_name: sn

=head1 DESCRIPTION

C<Socialtext::LDAP::OpenLDAP> implements an LDAP plug-in for OpenLDAP servers.

=head2 Supported Versions

The following versions of OpenLDAP are supported by this plug-in:

=over

=item OpenLDAP v2.x

=back

=head1 NOTES

=over

=item Filter for just users

To filter all LDAP queries/searches so that they only result in "user" objects
being returned (as opposed to "contacts", "computers", "printers", etc), set a
filter that restricts searches to I<just> those objects that have the
C<inetOrgPerson> object class:

  filter: (objectClass=inetOrgPerson)

=item Login by "user name"

If you wish to have users log in using their "user name", you can do this by
setting up the attribute mapping so that the "username" field maps to the LDAP
"Common Name" field:

  attr_map:
    username: cn

=item Login by "email address"

If you wish to have users log in using their "email address", you can do this
by setting up the attribute mapping for the "username" field so that it maps
to the LDAP "Mail Address" field:

  attr_map:
    username: mail

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
