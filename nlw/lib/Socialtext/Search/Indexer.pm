# @COPYRIGHT@
use warnings;
use strict;

=head1 NAME

Socialtext::Search::Indexer - Interface for fulltext search indices.

=head1 SYNOPSIS

    $factory = Socialtext::Search::AbstractFactory->GetFactory();
    $indexer = $factory->create_indexer( $workspace_name, 
                                         config_type => $config_type);

    # Update page's content in the index.
    $indexer->index_page($page_uri);

    # Update attachment's content in the index.
    $indexer->index_attachment($page_uri, $attachment_id);

    # For more methods, see below.

=head1 DESCRIPTION

Socialtext::Search::Indexer is the interface for creating fulltext search
indices on a workspace.  An Indexer is tied to a specific workspace when it is
created by the factory, and it indexes documents within that workspace.

=cut

package Socialtext::Search::Indexer;

use Carp 'croak';

=head1 OBJECT INTERFACE

The methods below each update content in the fulltext search index for the
content indicated by their arguments.  When they return, the search indexes
will be updated.  They C<die()> if there is any trouble during indexing.

NOTE: Every method B<must> be callable multiple times on a single instance of
the object.  For some backends this may mean having to open the index multiple
times, once per method.

=head2 $indexer->index_page($page_uri)

=cut

sub index_page {
    my ( $self ) = @_;

    if (ref $self) {
        croak(ref $self, ": internal bug: index_page not implemented");
    }
    else {
        croak(__PACKAGE__, "::index_page called in a weird way");
    }
}

=head2 $indexer->index_attachment($page_uri, $attachment_id)

=cut

sub index_attachment {
    my ( $self ) = @_;

    if (ref $self) {
        croak(ref $self, ": internal bug: index_attachment not implemented");
    }
    else {
        croak(__PACKAGE__, "::index_attachment called in a weird way");
    }
}

=head2 $indexer->index_workspace()

=cut

sub index_workspace {
    my ( $self ) = @_;

    if (ref $self) {
        croak(ref $self, ": internal bug: index_workspace not implemented");
    }
    else {
        croak(__PACKAGE__, "::index_workspace called in a weird way");
    }
}

=pod

The methods below each delete all references in the fulltext search index to
the content indicated by their arguments.  When they return, the deletion will
be complete.  They each C<die()> if there is any trouble during the deletion.

=head2 $indexer->delete_page($page_uri)

=cut

sub delete_page {
    my ( $self ) = @_;

    if (ref $self) {
        croak(ref $self, ": internal bug: delete_page not implemented");
    }
    else {
        croak(__PACKAGE__, "::delete_page called in a weird way");
    }
}

=head2 $indexer->delete_attachment($page_uri, $attachment_id)

=cut

sub delete_attachment {
    my ( $self ) = @_;

    if (ref $self) {
        croak(ref $self, ": internal bug: delete_attachment not implemented");
    }
    else {
        croak(__PACKAGE__, "::delete_attachment called in a weird way");
    }
}

=head2 $indexer->delete_workspace()

=cut

sub delete_workspace {
    my ( $self ) = @_;

    if (ref $self) {
        croak(ref $self, ": internal bug: delete_workspace not implemented");
    }
    else {
        croak(__PACKAGE__, "::delete_workspace called in a weird way");
    }
}

=head1 SEE ALSO

L<Socialtext::Search::Searcher>, L<Socialtext::Page>, L<Socialtext::Attachment>

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
