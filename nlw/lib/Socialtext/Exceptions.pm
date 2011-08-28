# @COPYRIGHT@
package Socialtext::Exceptions;

use warnings;
use strict;

our $VERSION = 0.01;

use Scalar::Util ();

my %e;

BEGIN {
    %e = (
        'Socialtext::Exception' => {
            description => 'Generic super-class for Socialtext exceptions',
            fields      => [qw( http_status http_type )],
        },

        'Socialtext::Exception::Auth' => {
            isa         => 'Socialtext::Exception',
            alias       => 'auth_error',
            description => 'User cannot perform the requested action'
        },

        'Socialtext::Exception::Config' => {
            isa         => 'Socialtext::Exception',
            alias       => 'config_error',
            description => 'Config file is missing data or contains bad data'
        },

        'Socialtext::Exception::BadRequest' => {
            isa         => 'Socialtext::Exception',
            alias       => 'bad_request',
            description => 'Bad request',
        },

        'Socialtext::Exception::Params' => {
            isa         => 'Socialtext::Exception',
            alias       => 'param_error',
            description => 'Bad parameters given to a method/function'
        },

        'Socialtext::Exception::SystemError' => {
            isa         => 'Socialtext::Exception',
            alias       => 'system_error',
            description => 'An error occurred when making a system call'
         },

        'Socialtext::Exception::DataValidation' => {
            isa         => 'Socialtext::Exception',
            alias       => 'data_validation_error',
            fields      => [qw( errors )],
            description => 'Data validation error'
        },

        'Socialtext::Exception::TooManyResults' => {
            isa         => 'Socialtext::Exception',
            alias       => 'too_many_results',
            fields      => [qw( num_results )],
            description => 'Too many search results returned.',
        },

        'Socialtext::Exception::SearchTimeout' => {
            isa         => 'Socialtext::Exception',
            alias       => 'search_timeout',
            fields      => [],
            description => 'Search took too long.',
        },

        'Socialtext::Exception::NoSuchResource' => {
            isa         => 'Socialtext::Exception',
            alias       => 'no_such_resource_error',
            fields      => [qw( name )],
            description => 'An attempt to access a non-existent resource'
        },

        'Socialtext::Exception::NotFound' => {
            isa         => 'Socialtext::Exception',
            alias       => 'not_found',
            fields      => [qw( name )],
            description => 'The specified resource was not found',
        },

        'Socialtext::Exception::Conflict' => {
            isa         => 'Socialtext::Exception',
            alias       => 'conflict',
            fields      => [qw( errors )],
            description => 'Conflict with the specified resource',
        },

        'Socialtext::Exception::VirtualMethod' => {
            isa         => 'Socialtext::Exception',
            description =>
                'A virtual method was not implemented in a subclass'
        },

        'Socialtext::Exception::UndefinedMethod' => {
            alias       => 'throw_undef_method',
            description => 'A method was not implemented by a class',
            fields      => [qw( class method )],
            isa         => 'Socialtext::Exception',
        },

    );
}

{
    package Socialtext::Exception::DataValidation;

    sub messages { @{ $_[0]->errors || [] } }

    # for stringification
    sub full_message {
        if ( my @m = $_[0]->messages ) {
            return join "\n", 'Data validation errors: ', @m;
        }
        else {
            return $_[0]->SUPER::full_message();
        }
    }
}

use Exception::Class (%e);

$_->Trace(1) for keys %e;

use base 'Exporter';
our @EXPORT_OK = ( qw( rethrow_exception virtual_method_error ),
                   map { $_->{alias} } grep { exists $_->{alias} } values %e
                 );

sub virtual_method_error {
    my $object = shift;

    my $sub = (caller(1))[3];
    my $class = ref $object || $object;

    Socialtext::Exception::VirtualMethod->throw
        ( error =>
          "$sub is a virtual method and must be subclassed in $class"
        );
}

sub rethrow_exception {
    my $e = shift;

    if ( Scalar::Util::blessed($e) and $e->can('rethrow') ) {
        $e->rethrow();
    }

    Socialtext::Exception->throw( message => $e );
}

1;

__END__

=head1 NAME

Socialtext::Exceptions - The great new Socialtext::Exceptions!

=head1 SYNOPSIS

  Socialtext::Exception::NoSuchResource->throw(name => $name)

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

