# @COPYRIGHT@
use warnings;
use strict;

=head1 NAME

Socialtext::Search::Basic::Indexer - A NOP indexer for use when only grepping will do.

=cut

package Socialtext::Search::Basic::Indexer;

sub new { bless { }, $_[0] }

sub index_page { }

sub index_attachment { }

sub index_workspace { }

sub delete_page { }

sub delete_attachment { }

sub delete_workspace { }

=head1 SEE

L<Socialtext::Search::Indexer> for the interface definition.

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
