package Socialtext::Template::Plugin::html_truncate;
# @COPYRIGHT@
use strict;
use warnings;

use Template::Plugin::Filter;
use HTML::Truncate;
use base qw( Template::Plugin::Filter );

sub init {
    my $self = shift;

    $self->{ _DYNAMIC } = 1;

    # first arg can specify filter name
    $self->install_filter($self->{ _ARGS }->[0] || 'html_truncate');

    return $self;
}

sub filter {
    my ($self, $html, $args, $config) = @_;
    my $length = defined $args->[0] ? $args->[0] : 350;
    my $ht = HTML::Truncate->new();
    $ht->add_skip_tags(qw( img ));
    return $ht->truncate($html, $length, chr(8230));
}

1;
