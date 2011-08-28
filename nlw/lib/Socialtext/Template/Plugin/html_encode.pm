package Socialtext::Template::Plugin::html_encode;
# @COPYRIGHT@

use strict;
use warnings;

use Template::Plugin::Filter;
use base qw( Template::Plugin::Filter );

use HTML::Entities ();

sub init {
    my $self = shift;

    $self->{ _DYNAMIC } = 0;

    # first arg can specify filter name
    $self->install_filter($self->{ _ARGS }->[0] || 'html_encode');

    return $self;
}


sub filter {
    return HTML::Entities::encode_entities( $_[1] );
}

1;
