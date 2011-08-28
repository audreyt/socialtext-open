package Socialtext::Template::Plugin::flatten;
# @COPYRIGHT@

use strict;
use warnings;

use Template::Plugin::Filter;
use base qw( Template::Plugin::Filter );

use URI::Escape ();

sub init {
    my $self = shift;

    $self->{ _DYNAMIC } = 0;

    # first arg can specify filter name
    $self->install_filter($self->{ _ARGS }->[0] || 'flatten');

    return $self;
}


sub filter {
    my $id = $_[1];
    $id = '' if not defined $id;

    # duplicated in Socialtext::String::title_to_id
    $id =~ s/[^\p{Letter}\p{Number}\p{ConnectorPunctuation}\pM]+/_/g;
    $id =~ s/_+/_/g;
    $id =~ s/^_(?=.)//;
    $id =~ s/(?<=.)_$//;
    $id =~ s/^0$/_/;
    $id = lc($id);

    return URI::Escape::uri_escape_utf8($id);
}

1;

