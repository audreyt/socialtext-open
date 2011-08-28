package Socialtext::Rest::TaggedPages;
# @COPYRIGHT@

use Moose;

extends 'Socialtext::Rest::Pages';

# REVIEW: This need to be different depending on the query?
sub collection_name {
    'Pages tagged with ' . $_[0]->tag;
}

sub element_list_item {
    my ( $self, $page ) = @_;

    return "<li><a href='/data/workspaces/$page->{workspace_name}/pages/$page->{page_id}'>"
        . Socialtext::String::html_escape( $page->{name} )
        . "</a></li>\n";
}

# Generates an list of pages which satisfy the query parameters, ordered
# by the last edit time.
sub _entities_for_query {
    my $self = shift;

    my $limit = $self->items_per_page || 500;
    my $type = $self->rest->query->param('type');

    my $pagesref = [];
    if (lc($self->tag) eq 'recent changes') {
        my $prefs = $self->hub->recent_changes->preferences;
        my $seconds = $prefs->changes_depth->value * 1440 * 60;
        $pagesref = Socialtext::Pages->By_seconds_limit(
            seconds          => $seconds,
            hub              => $self->hub,
            limit            => $limit,
            offset           => $self->start_index,
            do_not_need_tags => 1,
            workspace_id     => $self->hub->current_workspace->workspace_id,
            type             => $type,
        );
        $self->total_result_count(
            Socialtext::Pages->ChangedCount(
                workspace_id => $self->hub->current_workspace->workspace_id,
                duration => $seconds,
            )
        );
    }
    else {
        $pagesref = Socialtext::Pages->By_tag(
            hub          => $self->hub,
            tag          => $self->tag,
            workspace_id => $self->hub->current_workspace->workspace_id,
            limit        => $limit,
            offset       => $self->start_index,
            type         => $type,
        );
        $self->total_result_count(
            $self->hub->category->page_count($self->tag)
        );
    }
    return @$pagesref;
}

sub allowed_methods {
    return 'GET, HEAD';
}

1;
