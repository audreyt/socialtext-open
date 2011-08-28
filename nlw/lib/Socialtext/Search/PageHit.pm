# @COPYRIGHT@
use warnings;
use strict;

=head1 NAME

Socialtext::Search::PageHit - Representation of a search hit found in a page.

=head1 SYNOPSIS

    $uri = $page_hit->page_uri();
    $key     = $page_hit->key();

    print "Your search term was found in the page with URI $uri.\n";

=head1 DESCRIPTION

Socialtext::Search::PageHit is an interface definition.  A PageHit is an occurence of
a particular search term in a wiki page.

=cut

package Socialtext::Search::PageHit;

use base 'Socialtext::Search::Hit';

use Carp 'croak';

=head1 OBJECT INTERFACE

=head2 $page_hit->page_uri()

Returns the URI of the wiki page where the search term was found.

=cut

sub page_uri {
    my ( $self ) = @_;

    if (ref $self) {
        croak(ref $self, ": internal bug: page_uri not implemented");
    }
    else {
        croak(__PACKAGE__, "::page_uri called in a weird way");
    }
}

=head2 $page_hit->workspace_name()

Returns the name of the workspace where the hit was found.

=cut
sub workspace_name {
    my ( $self ) = @_;

    if (ref $self) {
        croak(ref $self, ": internal bug: workspace_name not implemented");
    }
    else {
        croak(__PACKAGE__, "::workspace_name called in a weird way");
    }
}

=head2 $page_hit->key()

Returns the document key of the hit in the index.

=cut
sub key {
    my ( $self ) = @_;

    if (ref $self) {
        croak(ref $self, ": internal bug: key not implemented");
    }
    else {
        croak(__PACKAGE__, "::key called in a weird way");
    }
}

1;

=head1 SEE ALSO

L<Socialtext::Search::Hit>, L<Socialtext::Page>

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
