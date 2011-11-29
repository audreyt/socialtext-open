package Socialtext::Template::Plugin::coffee;;
# @COPYRIGHT@
use Moose;
use methods;
use File::Which qw(which);
use IPC::Run qw(run);
use namespace::clean -except => 'meta';

extends 'Template::Plugin::Filter';

method init {
    $self->{ _DYNAMIC } = 1;
    $self->install_filter('coffee');
    return $self;
}

has 'coffee_compiler' => ( is => 'ro', isa => 'Str', lazy_build => 1 );
sub _build_coffee_compiler { which('st-coffee') }

method filter ($text) {
    my ($out, $err);
    run [ $self->coffee_compiler, '-sc' ], \$text, \$out, \$err;
    warn $err if $err;
    return $out;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 NAME

Socialtext::Template::Plugin::coffee - Convert coffee script to javascript

NOTE: This will be slow, so it should only happen in build operations, not on each request!!!!

=head1 DESCRIPTION

Convert coffeescript to javascript

=head1 SYNOPSIS

    [% USE coffee %]
    [% FILTER coffee %]
    blah
    [% END %]

=cut
