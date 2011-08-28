package Socialtext::Group::Default;
# @COPYRIGHT@
use Moose;
extends 'Socialtext::Group::Homunculus';
no Moose;
__PACKAGE__->meta->make_immutable;
1;
__END__

=head1 NAME

Socialtext::Group::Default - Internally sourced Socialtext Group

=head1 DESCRIPTION

C<Socialtext::Group::Default> provides an implementation for a Group
Homunculus that is sourced internally by Socialtext (e.g. Groups are defined
by the local DB).

Derived from C<Socialtext::Group::Homunculus>.

=head1 METHODS

See L<Socialtext::Group::Homunculus>.

=head1 AUTHOR

Socialtext, Inc.,  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc.,  All Rights Reserved.

=cut
