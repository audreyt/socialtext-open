package Socialtext::Rest::WorkspaceTags;
# @COPYRIGHT@
use strict;
use warnings;

use Socialtext::String;
use Socialtext::SQL qw/sql_execute/;

use base 'Socialtext::Rest::Tags';

=head1 NAME

Socialtext::Rest::WorkspaceTags - A class for exposing collections of Tags associated with a Workspace

=head1 SYNOPSIS

    GET  /data/workspaces/:ws/tags
    POST /data/workspaces/:ws/tags

=head1 DESCRIPTION

Every workspace has a collection of zero or more tags (aka categories) that
may be used to describe pages and as navigational aids. At the URIs listed
above it is possible to get a list of those tags, or add a new tag 
to those available for use.

See L<Socialtext::Rest::Tags> for information on representations.

=cut
sub collection_name { "Tags for " . $_[0]->workspace->title . "\n" }

sub _entities_for_query {
    my $self = shift;

    my $ws_id = $self->hub->current_workspace->workspace_id;
    my @params = ($ws_id);

    my $sql = "
        SELECT tag AS name, count(page_id) AS page_count
          FROM page_tag
         WHERE workspace_id = ?
    ";

    if (my $except_page = $self->rest->query->param('exclude_from')) {
        $sql .= "AND tag NOT IN (SELECT tag FROM page_tag WHERE page_id = ? AND workspace_id = ?)\n";
        push @params, $except_page, $ws_id;
    };

    $sql .= "GROUP BY tag";

    my $sth = sql_execute($sql, @params);
    return @{ $sth->fetchall_arrayref({}) };
}

sub add_text_element {
    my ( $self, $tag ) = @_;

    chomp $tag;
    $self->hub->category->add_workspace_tag($tag);

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
