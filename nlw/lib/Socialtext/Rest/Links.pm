package Socialtext::Rest::Links;
# @COPYRIGHT@
use warnings;
use strict;

use base 'Socialtext::Rest::Pages';

sub link_type { ref($_[0]) =~ /::(\w+)s$/; lc($1); }

use Socialtext::String;

# REVIEW: This need to be different depending on the query?
sub collection_name {
    ucfirst( $_[0]->link_type() )
        . 's for page '
        . $_[0]->page->name;
}

sub element_list_item {
    "<li><a href='../$_[1]->{uri}'>"
        . Socialtext::String::html_escape( $_[1]->{name} )
        . "</a></li>\n";
}

# Generates an unordered, unsorted list of backlink pages
sub _entities_for_query {
    my $self = shift;

    my $method = 'all_' . $self->link_type . '_pages_for_page';
    return $self->hub->backlinks->$method( $self->page,
        $self->rest->query->param('incipient') );
}

1;
