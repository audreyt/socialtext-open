package Socialtext::LDAP::ActiveDirectory;
# @COPYRIGHT@

use strict;
use warnings;
use base 'Socialtext::LDAP::Base';

1;

=head1 NAME

Socialtext::LDAP::ActiveDirectory - LDAP plug-in for Active Directory servers

=head1 SYNOPSIS

  # Example entry in ldap.yaml
  id: 78226073fb
  name: Our Active Directory server
  backend: ActiveDirectory
  host: ad.example.com
  port: 389
  base: cn=Sales,dc=example,dc=com
  filter: (&(objectClass=user)(objectCategory=person))
  follow_referrals: 1
  max_referral_depth: 3
  attr_map:
    user_id: dn
    username: sAMAccountName
    email_address: mail
    first_name: givenName
    last_name: sn

=head1 DESCRIPTION

C<Socialtext::LDAP::ActiveDirectory> implements an LDAP plug-in for Active
Directory servers.

=head2 Supported Versions

The following versions of Active Directory are supported by this plug-in:

=over

=item Active Directory 2003

=back

=head1 NOTES

=over

=item Filter for just users

To filter all LDAP queries/searches so that they only result in "user" objects
being returned (as opposed to "contacts", "computers", "printers", etc), set a
filter that restricts searches to I<just> those objects that have the C<user>
object class and that are in the "person" object category:

  filter: (&(objectClass=user)(objectCategory=person))

=item Login by "Windows user name"

If you wish to have users log in using their "Windows user name", you can do
this by setting up the attribute mapping so that the "username" field maps to
the Active Directory "sAMAccountName" field:

  attr_map:
    username: sAMAccountName

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
