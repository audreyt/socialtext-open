package Socialtext::Rest::PageTags;
# @COPYRIGHT@

use strict;
use warnings;

use Socialtext::String;

use base 'Socialtext::Rest::Tags';
use Socialtext::HTTP ':codes';

=head1 NAME

Socialtext::Rest::PageTags - A class for exposing collections of Tags associated with a Page

=head1 SYNOPSIS

    GET  /data/workspaces/:ws/pages/:pname/tags
    POST /data/workspaces/:ws/pages/:pname/tags

=head1 DESCRIPTION

Every page may have zero or more tags (aka categories) associated with it.
At the URIs listed above it is possible to get a list of those tags,
or associate a new one with a page.

For manipulating individual tags on a page see L<Socialtext::Rest::PageTag>.
For listing all tags in a workspace see L<Socialtext::Rest::WorkspaceTags>.

See L<Socialtext::Rest::Tags> for information on representations.

=cut
sub last_modified   { $_[0]->page->modified_time }
sub collection_name { "Tags for page " . $_[0]->page->title . "\n" }

=head2 POST_text

Calls add_text_element with the text/plain representation it was given.

=cut

sub POST_text {
    my ( $self, $rest ) = @_;

    my $unable_to_edit = $self->page_locked_or_unauthorized();
    return $unable_to_edit if ($unable_to_edit);

    my $location = $self->add_text_element($rest->getContent);
    $rest->header( -status    => HTTP_201_Created,
                   -type      => 'text/plain',
                   -Location  => $location );
    return "Added.";
}

sub _entities_for_query {
    my $self = shift;

    return () if $self->page->content eq '';
    return grep (lc($_) ne 'recent changes', @{$self->page->tags});
}

sub add_text_element {
    my ( $self, $tag ) = @_;

    chomp $tag;
    $self->page->add_tags( $tag );

    return $self->_uri_for_tag($tag);
}

1;

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
