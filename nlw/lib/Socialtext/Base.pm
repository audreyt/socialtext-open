# @COPYRIGHT@
package Socialtext::Base;
use strict;
use warnings;

use Class::Field qw( const field );

use Carp();
use Data::Dumper;
use Encode;
use Socialtext::Paths;
use Socialtext::File;
use Socialtext::String;
use URI::Escape ();

field hub => -weak;

# This at one point was changed to simply do this:
#
#    return bless {@_}, $class;
#
# This does not work because if we don't call the field methods, then
# references will not be weakened, and we end up with memory cycles
sub new {
    my $class = shift;
    $class = ref($class) || $class;

    my $self = bless {}, $class;
    while ( my ( $field, $value ) = splice @_, 0, 2 ) {
        $self->$field($value)
            if $self->can($field);
    }

    return $self;
}

sub init { }

sub init_cgi {
    my $self = shift;
    my $class = $self->cgi_class
        or return;

    unless ($class->can('new')) {
        eval qq{require $class};
        die "unable to init cgi class $class: $@" if $@;
    }

    my $package = ref($self);
    field -package => $package, 'cgi';

    # XXX Have to pass in hub for now...it's used in Socialtext::CGI
    # default_page_name
    my $object = $class->new( hub => $self->hub );
    $object->init;
    $self->cgi($object);
}

sub assert {
    my $self = shift;
    die "Assertion failed" unless shift;
}

sub clone {
    my $self = shift;
    return bless {%$self}, ref $self;
}

sub is_in_cgi {
    my $self = shift;
    defined $ENV{GATEWAY_INTERFACE};
}

sub plugin_directory {
    my $self = shift;
    my $name = shift || $self->hub->current_workspace->name;
    my $dir = File::Spec->catdir(
        Socialtext::Paths::plugin_directory( $name ), $self->class_id,
    );
    Socialtext::File::ensure_directory($dir) unless -d $dir;
    return $dir;
}

sub dumper_to_file {
    my $self = shift;
    my $path = shift;
    no warnings;
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Terse = (@_ == 1) ? 1 : 0;
    local $Data::Dumper::Sortkeys = 1;

    Socialtext::File::set_contents( $path, Data::Dumper::Dumper(@_) );
}

sub utf8_decode {
    my $self = shift;
    $_[0] = Encode::decode('utf8', $_[0])
      if defined $_[0] and
         not Encode::is_utf8($_[0]);
    return $_[0];
}

sub utf8_encode {
    my $self = shift;
    $_[0] = Encode::encode('utf8', $_[0])
      if defined $_[0];
    return $_[0];
}

sub uri_escape {
    my $self = shift;
    return URI::Escape::uri_escape_utf8(shift);
}

sub uri_unescape {
    my $self = shift;
    my $data = shift;
    $data = URI::Escape::uri_unescape($data);
    return $self->utf8_decode($data);
}

sub html_escape {
    my $self = shift;
    return Socialtext::String::html_escape(@_);
}

sub html_unescape {
    my $self = shift;
    return Socialtext::String::html_unescape(@_);
}

1;

__END__

=head1 NAME 

Socialtext::Base - Generic NLW Base Class

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AUTHOR

Brian Ingerson <INGY@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2004. Brian Ingerson. All rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
