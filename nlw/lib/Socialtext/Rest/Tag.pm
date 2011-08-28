package Socialtext::Rest::Tag;
# @COPYRIGHT@

use strict;
use warnings;

=head1 NAME

Socialtext::Rest::Tag - Base class for managing a single tag

=cut

use base 'Socialtext::Rest::Entity';
use Socialtext::HTTP ':codes';

sub allowed_methods { 'GET, HEAD, PUT, DELETE' }

sub entity_name { 'tag ' . $_[0]->tag }

sub get_resource {
    my ( $self, $rest ) = @_;

    return $self->_find_tag( $self->tag )
        ? $self->_tag_representation($self->tag)
        : undef;
}

# REVIEW: cutnpaste from Socialtext::Rest::Tags
sub _uri_for_tag    {'tags/' . Socialtext::String::uri_escape($_[1])}

# REVIEW: cutnpaste from Socialtext::Rest::Tags
sub _tag_representation {
    my $self = shift;
    my $tag  = shift;

    return +{
        name => $tag,
        uri  => $self->_uri_for_tag($tag),
        page_count => $self->hub->category->page_count($tag),
    };
}

=head2 PUT tag

Add a tag to the current context. If it is already there 204, otherwise 201.

=cut
# REVIEW: replace with put_generic
# REVIEW: some overlap and lack of pattern with permissions handling elsewhere
sub PUT {
    my $self = shift;
    my ($rest) = @_;

    return $self->no_workspace() unless $self->workspace;
    return $self->not_authorized() unless $self->user_can('edit');

    if ( $self->_find_tag( $self->tag )) {
        $rest->header( -status => HTTP_204_No_Content );
    }
    else {
        $self->_add_tag($self->tag);
        $rest->header( -status => HTTP_201_Created );
    }
    return '';
}

=head2 DELETE tag

Remove a tag. 204 if the tag existed and has been removed.
If the tag is not there, 404.

=cut
sub DELETE {
    my $self = shift;
    my ($rest) = @_;

    my $permission_failed = $self->_delete_permission_failed();
    return $permission_failed if ( $permission_failed );

    if ($self->_find_tag( $self->tag)) {
        $self->_delete_tag($self->tag);
        $rest->header( -status => HTTP_204_No_Content );
    }
    else {
        $rest->header( -status => HTTP_404_Not_Found );
    }
    return '';
}

sub _delete_permission_failed {
    my $self = shift;

    return $self->no_workspace() unless $self->workspace;
    return $self->not_authorized() unless $self->user_can('edit');

    return 0;
}

sub _find_tag {
}

sub _add_tag {
}

sub _delete_tag {
}

# for later consideration, probably should be at a deeper level
sub _clean_tag {
    my $self = shift;
    my $tag_ref = shift;

    return $tag_ref;
}

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=cut

1;
