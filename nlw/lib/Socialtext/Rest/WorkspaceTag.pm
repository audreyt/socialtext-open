package Socialtext::Rest::WorkspaceTag;
# @COPYRIGHT@

use strict;
use warnings;

=head1 NAME

Socialtext::Rest::WorkspaceTag - Manage single tags in a workspace via REST

=head1 SYNOPSIS

    GET    /data/workspaces/:ws/tags/:tag
    PUT    /data/workspaces/:ws/tags/:tag
    DELETE /data/workspaces/:ws/tags/:tag

=head1 DESCRIPTION

Provide a way to determine existence, add or remove one single tag
from a workspace. When a tag is added, if it does not exist
in the tag system it is created. When a tag is removed from a workspace,
pages that have that tag have the tag removed.

=cut

use base 'Socialtext::Rest::Tag';

sub _find_tag {
    my $self = shift;
    my $tag  = shift;

    return $self->hub->category->exists($tag);
}

sub _add_tag {
    my $self = shift;
    my $tag  = shift;

    $self->_clean_tag(\$tag);

    $self->hub->category->add_workspace_tag($tag);
}

# REVIEW: this sure looks a lot like _add_tag
sub _delete_tag {
    my $self = shift;
    my $tag  = shift;

    $self->_clean_tag( \$tag );

    my $hub = $self->hub;
    $hub->category->delete( user => $hub->current_user, tag => $tag );
}

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=cut

1;
