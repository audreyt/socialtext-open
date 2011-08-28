# @COPYRIGHT@
use warnings;
use strict;

=head1 NAME

Socialtext::Search::AttachmentHit - Representation of a search hit found in an attachment.

=head1 SYNOPSIS

    $page_uri = $attachment_hit->page_uri();
    $attachment_id = $attachment_hit->attachment_id();
    $ws_name       = $attachment_hit->workspace_name();
    $key           = $attachment_hit->key();

    print "Your search term was found in the attachment $attachment_id\n";
    print "attached to the page with URI $page_uri.\n";

=head1 DESCRIPTION

Socialtext::Search::AttachmentHit is an interface definition.  An AttachmentHit is an
occurence of a particular search term in an attachment to a wiki page.

=cut

package Socialtext::Search::AttachmentHit;

use base 'Socialtext::Search::Hit';

=head1 OBJECT INTERFACE

=head2 $attachment_hit->page_uri()

Returns the URI of the wiki page to which the matching attachment is attached.

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

=head2 $attachment_hit->attachment_id()

Returns the id of the attachment where the search term was found.

=cut

sub attachment_id {
    my ( $self ) = @_;

    if (ref $self) {
        croak(ref $self, ": internal bug: attachment_id not implemented");
    }
    else {
        croak(__PACKAGE__, "::attachment_id called in a weird way");
    }
}

=head2 $attachment_hit->workspace_name()

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

=head2 $attachment_hit->key()

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

L<Socialtext::Search::Hit>, L<Socialtext::Attachment>, L<Socialtext::Page>

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
