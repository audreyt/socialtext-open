# @COPYRIGHT@
use warnings;
use strict;

=head1 NAME

Socialtext::Search::Searcher - Interface for doing fulltext search on a workspace.

=head1 SYNOPSIS

    $factory = Socialtext::Search::AbstractFactory->GetFactory();
    $seacher = $factory->create_searcher($workspace_id);
    @hits = $searcher->search($query_string);

=head1 DESCRIPTION

Socialtext::Search::Searcher is the interface for performing fulltext searches on a
workspace.  A Searcher is tied to a specific workspace when it is created by
the factory, and it performs its searches only on documents within that
workspace.

=cut

package Socialtext::Search::Searcher;

=head1 OBJECT INTERFACE

=head2 $searcher->search($query_string, [$authorizer])

Returns a list of L<Socialtext::Search::Hit>s each corresponding to some item
in the workspace which matches the given query.

If there is any sort of trouble searching, the searcher will indicate the
error by C<die()>ing.

If C<$authorizer> is provided, it may be called with a single workspce name as
an argument.  It should return C<false> if there is a problem authorizing
access to the given workspace.  Any context, e.g. as to who the current user
is and how they are to be authorized, is to be carried by the C<$authorizer>
callback.

If there is an authorization problem, then L<Socialtext::Exception::Auth> is
thrown.

=cut

sub search {
    my ( $self ) = @_;

    if (ref $self) {
        croak(ref $self, ": internal bug: search not implemented");
    }
    else {
        croak(__PACKAGE__, "::search called in a weird way");
    }
}

=head1 SEE ALSO

L<Socialtext::Search::Indexer>,
L<Socialtext::Search::Hit>,
L<Socialtext::Exception::Auth>

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
