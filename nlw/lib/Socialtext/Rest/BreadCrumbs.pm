package Socialtext::Rest::BreadCrumbs;
# @COPYRIGHT@
use warnings;
use strict;

use base 'Socialtext::Rest::Pages';

use Socialtext::String;

# REVIEW: This need to be different depending on the query?
sub collection_name {
    'Breadcrumbs for workspace ' . $_[0]->workspace->name;
}

sub element_list_item {
    "<li><a href='pages/$_[1]->{uri}'>"
        . Socialtext::String::html_escape( $_[1]->{name} )
        . "</a></li>\n";
}

# Generates an unordered, unsorted list of breadcrumb pages
sub _entities_for_query {
    my $self = shift;

    return $self->hub->breadcrumbs->breadcrumb_pages();
}

1;
