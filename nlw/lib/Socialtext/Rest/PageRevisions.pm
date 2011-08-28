package Socialtext::Rest::PageRevisions;
# @COPYRIGHT@

use warnings;
use strict;

use base 'Socialtext::Rest::Pages';


# REVIEW: This need to be different depending on the query?
sub collection_name {
    'Revisions for  ' . $_[0]->page->name;
}

sub _resource_to_text {
    join '', map {"$_->{name}:$_->{revision_id}\n"} @{ $_[1] };
}

sub element_list_item {
    "<li><a href='revisions/$_[1]->{revision_id}'>"
        . Socialtext::String::html_escape( $_[1]->{name} ) . ' version ' .
        $_[1]->{revision_id}
        . "</a></li>\n";
}

# Generates an unordered, unsorted list of pages which satisfy the query
# parameters.
sub _entities_for_query {
    my $self = shift;

    return map {
        my $revision = $self->hub->pages->new_page( $self->page->id );
        $revision->revision_id($_);
        $revision;
    } $self->page->all_revision_ids();
}

1;
