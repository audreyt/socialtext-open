package Socialtext::Template::Plugin::JSON;
# @COPYRIGHT@
use Moose;
use JSON::XS ();
use Socialtext::Encode 'ensure_is_utf8';
use Carp qw/croak/;

extends qw(Moose::Object Template::Plugin);

our $VERSION = "0.06";

has context => (
        isa => "Object",
        is  => "ro",
);

has json_converter => (
        isa => "Object",
        is  => "ro",
        lazy_build => 1,
);

has json_args => (
        isa => "HashRef",
        is  => "ro",
        default => sub { {} },
);

sub BUILDARGS {
    my ( $class, $c, @args ) = @_;

        my $args;

        if ( @args == 1 and not ref $args[0] ) {
                warn "Single argument form is deprecated, this module always uses JSON/JSON::XS now";
        }

        $args = ref $args[0] ? $args[0] : {};

        return { %$args, context => $c, json_args => $args };
}

sub _build_json_converter {
        my $self = shift;

        my $json = JSON::XS->new->allow_nonref(1);

        my $args = $self->json_args;

        for my $method (keys %$args) {
                if ( $json->can($method) ) {
                        $json->$method( $args->{$method} );
                }
        }

        return $json;
}

sub json {
        my ( $self, $value ) = @_;

        my $json = ensure_is_utf8($self->json_converter->allow_blessed->convert_blessed->ascii->encode($value));
        $json =~ s!</(scr)(ipt)>!</$1" + "$2>!gi;
        return $json;
}

sub json_decode {
        my ( $self, $value ) = @_;

        $self->json_converter->decode($value);
}

sub BUILD {
        my $self = shift;
        $self->context->define_vmethod( $_ => json => sub { $self->json(@_) } ) for qw(hash list scalar);
}

__PACKAGE__;

=head1 NAME

Socialtext::Template::Plugin::JSON

=head1 SYNOPSIS

[% use JSON %]

this is [% something.json %]

=head1 DESCRIPTION

Port this to use ST's JSON libs.

=head1 COPYRIGHT & LICENSE

Copyright (c) 2006, 2008 Infinity Interactive, Yuval Kogman.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

=cut
