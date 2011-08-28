package Socialtext::Template::Plugin::minify;;
# @COPYRIGHT@
use strict;
use Template::Plugin::Filter;
use JavaScript::Minifier::XS qw(minify);
use base qw( Template::Plugin::Filter );

sub init {
    my $self = shift;

    $self->{ _DYNAMIC } = 1;

    # first arg can specify filter name
    $self->install_filter('minify');

    return $self;
}

sub filter {
    my ($self, $text) = @_;
    return minify($text);
}

1;

=head1 NAME

Socialtext::Template::Plugin::minify - minify javascript on the fly

=head1 SYNOPSIS

    [% USE minify %]
    [% FILTER minify %]
    blah
    [% END %]


=head1 DESCRIPTION

Use JavaScript::Minifier::XS to minify JS that is inline templates.

=cut
