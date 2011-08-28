# @COPYRIGHT@
use warnings;
use strict;

=head1 NAME

Socialtext::Search::Hit - Representation of a search hit in a wiki object.

=head1 DESCRIPTION

Subinterfaces of Socialtext::Search::Hit specify the specific interface which
particular types of hits (e.g., a hit found in a wiki page, or an attachment)
should present.

=cut

package Socialtext::Search::Hit;

# "use base" freaks out if this package is empty, so...
sub _totally_bogus_method { }

# No code goes here yet.  If anything ever emerges which is obviously common
# to all Hit interfaces, it should go here.

=head1 SEE ALSO

L<Socialtext::Search::PageHit>, L<Socialtext::Search::AttachmentHit>

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
