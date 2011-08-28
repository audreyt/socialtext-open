# @COPYRIGHT@
use warnings;
use strict;

=head1 NAME

Socialtext::Search::SimplePageHit - A basic implementation of Socialtext::Search::PageHit.

=head1 SYNOPSIS

    $hit = Socialtext::Search::SimplePageHit->new($hit, $workspace_name, $page_uri);

    $hit->page_uri(); # returns $page_uri

    $hit->set_page_uri('foo');

    $hit->page_uri(); # returns 'foo'

    $hit->key(); # returns page's key


=head1 DESCRIPTION

This implementation simply stores a page URI in a blessed scalar.

=cut

package Socialtext::Search::SimplePageHit;
use base 'Socialtext::Search::PageHit';
use Socialtext::Encode;

=head1 CONSTRUCTOR

=head2 Socialtext::Search::SimplePageHit->new($hit, $workspace_name, $page_uri)

Creates a PageHit pointing at the given URI.

=cut

sub new {
    my ( $class, $hit, $workspace_name, $page_uri )= @_;

    bless {
        hit            => $hit,
        workspace_name => $workspace_name,
        page_uri       => $page_uri,

        snippet        => Socialtext::Encode::ensure_is_utf8($hit->{excerpt}),
        key            => $hit->{key},
    }, $class;
}

=head1 OBJECT METHODS

Besides those defined in L<Socialtext::Search::PageHit>, we have

=head2 $page_hit->set_page_uri($page_uri)

Change the URI that this hit points to.

=cut

sub set_page_uri { $_[0]->{page_uri} = $_[1] }
sub page_uri { $_[0]->{page_uri} }

=head2 $page_hit->set_workspace_name($workspace_name);

Change the workspace that this hit points to.

=cut

sub set_workspace_name { $_[0]->{workspace_name} = $_[1] }
sub workspace_name     { $_[0]->{workspace_name} }

=head2 $page_hit->set_key($key)

Change the index document key that this hit points to.

=cut

sub set_key { $_[0]->{key} = $_[1] }
sub key     { $_[0]->{key} }

=head2 $page_hit->set_snippet($snippet)

The snippet of the hit.

=head2 $page_hit->snippet()

Return the snippet of the hit.

=cut

sub set_snippet { 
    my $self = shift;
    $self->{snippet} = Socialtext::Encode::ensure_is_utf8(shift);
}

sub snippet     { $_[0]->{snippet} }

=head2 $page_hit->set_hit($hit)

The raw (original) hit.

=head2 $page_hit->hit()

Return the raw hit.

=cut

sub set_hit { $_[0]->{hit} = $_[1] }
sub hit     { $_[0]->{hit} }

=head2 $page_hit->composed_key()

Compose a key suitable for cross-workspace uniqueness.

=cut

sub composed_key     {
    my $self = shift;
    my $workspace_name = $self->workspace_name;
    my $key = $self->key;
    return "$workspace_name $key";
}

1;

=head1 SEE ALSO

L<Socialtext::Search::PageHit> for the interface definition

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
