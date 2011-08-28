# @COPYRIGHT@
use warnings;
use strict;

=head1 NAME

Socialtext::Search::Basic::Factory - Grep-based Socialtext::Search::AbstractFactory implementation.

=cut

package Socialtext::Search::Basic::Factory;

use Socialtext::Search::Basic::Indexer;
use Socialtext::Search::Basic::Searcher;

# Rather than create an actual object (since there's no state), just return
# the class name.  This will continue to make all the methods below work.
sub new { $_[0] }

sub create_searcher {
    my ( $self, $workspace_name ) = @_;

    return Socialtext::Search::Basic::Searcher->new($workspace_name);
}

sub create_indexer {
    my ( $self, $workspace_name ) = @_;

    return Socialtext::Search::Basic::Indexer->new;
}

=head1 SEE

L<Socialtext::Search::AbstractFactory> for the interface definition.

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
