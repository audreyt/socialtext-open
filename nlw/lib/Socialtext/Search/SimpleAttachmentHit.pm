# @COPYRIGHT@
use warnings;
use strict;

=head1 NAME

Socialtext::Search::SimpleAttachmentHit - A basic implementation of Socialtext::Search::AttachmentHit.

=head1 SYNOPSIS

    $hit = Socialtext::Search::SimpleAttachmentHit->new(
        $hit,
        $workspace_name,
        $page_uri,
        $attachment_id,

    );

    $hit->page_uri();              # returns $page_uri
    $hit->attachment_id();         # returns $attachment_id
    $hit->workspace_name();        # returns $workspace_name
    $hit->key();                   # returns our hit's key
    $hit->snippet();               # returns an excerpt
    $hit->hit();                   # returns the raw hit from the search engine

=head1 DESCRIPTION

This implementation simply stores the URI and attachment id in a blessed hash.

=cut

package Socialtext::Search::SimpleAttachmentHit;
use base 'Socialtext::Search::AttachmentHit';
use Socialtext::Encode;

=head1 CONSTRUCTOR

=head2 Socialtext::Search::SimpleAttachmentHit->new( $hit, $workspace_name, $page_uri, $attachment_id )

Creates an AttachmentHit pointing at the given attachment (attached to the
page with URI $page_uri).

=cut

sub new {
    my ( $class, $hit, $workspace_name, $page_uri, $attachment_id ) = @_;

    bless {
        hit            => $hit,
        workspace_name => $workspace_name,
        page_uri       => $page_uri,
        attachment_id  => $attachment_id,

        key            => $hit->{key},
        snippet        => Socialtext::Encode::ensure_is_utf8($hit->{excerpt}),
    }, $class;
}

=head1 OBJECT METHODS

Besides those defined in L<Socialtext::Search::AttachmentHit>, we have

=head2 $hit->set_page_uri($page_uri)

Change the page that this hit points to.

=cut

sub set_page_uri { $_[0]->{page_uri} = $_[1] }
sub page_uri { $_[0]->{page_uri} }

=head2 $hit->set_attachment_id($attachment_id)

Change the attachment that this hit points to.

=cut

sub set_attachment_id { $_[0]->{attachment_id} = $_[1] }
sub attachment_id { $_[0]->{attachment_id} }

=head2 $hit->set_workspace_name($workspace_name)

Change the workspace this hit points to.

=cut

sub set_workspace_name { $_[0]->{workspace_name} = $_[1] }
sub workspace_name     { $_[0]->{workspace_name} }

=head2 $hit->set_key($key)

Change the document key this hit points to.

=cut

sub set_key { $_[0]->{key} = $_[1] }
sub key     { $_[0]->{key} }

=head2 $page_hit->set_snippet($snippet)

The snippet of the hit.

=head2 $hit->snippet()

Return the hit's snippet
=cut

sub set_snippet { 
    my $self = shift;
    $self->{snippet} = Socialtext::Encode::ensure_is_utf8(shift);
}

sub snippet     { $_[0]->{snippet} }

=head2 $hit->set_hit($hit)

Change the raw hit this hit was made from.

=head2 $hit->hit()

Return the raw hit
=cut

sub set_hit { $_[0]->{hit} = $_[1] }
sub hit     { $_[0]->{hit} }

=head2 $hit->composed_key()

Return a composed key guaranteeing cross-workspace uniqueness

=cut

sub composed_key {
    my $self = shift;
    my $workspace_name = $self->workspace_name;
    my $page_uri = $self->page_uri;
    my $key = $self->key;
    return "$workspace_name $page_uri $key";
}

1;

=head1 SEE ALSO

L<Socialtext::Search::AttachmentHit> for the interface definition

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
