package Socialtext::Group::LDAP;
# @COPYRIGHT@
use Moose;
extends 'Socialtext::Group::Homunculus';
no Moose;
__PACKAGE__->meta->make_immutable;
1;
__END__

=head1 NAME

Socialtext::Group::LDAP - LDAP sourced Socialtext Group

=head1 SYNOPSIS

  $group = Socialtext::Group->GetGroup(
    driver_unique_id => $ldap_dn,
  );

=head1 DESCRIPTION

C<Socialtext::Group::LDAP> provides an implementation for a Group Homunculus
that is sourced from an LDAP or Active Directory store.

Derived from C<Socialtext::Group::Homunculus>.

=head1 METHODS

See L<Socialtext::Group::Homunculus>.

=head1 AUTHOR

Socialtext, Inc.,  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc.,  All Rights Reserved.

=cut
