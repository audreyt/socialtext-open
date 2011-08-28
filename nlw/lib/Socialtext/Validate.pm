# @COPYRIGHT@
package Socialtext::Validate;

use strict;
use warnings;

our $VERSION = 0.01;

use Params::Validate 0.79 qw( :all );
use Socialtext::Exceptions qw( param_error );
use base 'Exporter';

use Email::Valid;

my %types;
BEGIN {
    %types = (
        FILE_TYPE => {
            callbacks => {
                'is valid file path' => sub { -f $_[0] or not -e _ }
            },
        },

        DIR_TYPE => {
            callbacks => {
                'is valid directory path' => sub { -d $_[0] or not -e _ }
            },
        },

        SCALAR_OR_ARRAYREF_TYPE => { type => SCALAR | ARRAYREF },

        SECURE_URI_TYPE => { type => SCALAR, regex => qr[^https://] },

        URI_TYPE => { type => SCALAR, regex => qr[^https?://] },

        EMAIL_TYPE => { type => SCALAR,
                        callbacks => { 'is valid email address' => sub { Email::Valid->address($_[0]) } },
                      },

        NONNEGATIVE_INT_TYPE => {
            type => SCALAR,
            regex => qr/^\d+$/,
        },
        POSITIVE_INT_TYPE => {
            type => SCALAR,
            callbacks => { 'is positive integer' => sub { ($_[0] =~ /^\d+$/) && ($_[0] > 0) }, },
        },
        POSITIVE_FLOAT_TYPE => {
            type => SCALAR,
            callbacks => { 'is positive float' => sub { ($_[0] =~ /^\d+(?:\.\d+)?$/) && ($_[0] > 0) }, },
        },

        OPTIONAL_INT_TYPE => { type => SCALAR, regex => qr/^\d+$/, optional => 1 },

        REGEX_TYPE => { callbacks =>
                        { 'is a regex' => sub { UNIVERSAL::isa( $_[0], 'Regexp' ) || ! ref $_[0] } },
                      },

        PAGE_TYPE => { can => 'title' },

        PLUGIN_TYPE => { can => 'plugin_directory' },

        # a bit incestuous, but it works
        map { $_ . '_TYPE' => { type => eval $_ } } grep { /^[A-Z]+$/ } @Params::Validate::EXPORT_OK,
    );

    # XXX - should this list be available elsewhere?
    for my $data_object ( qw( user workspace account role permission ) ) {
        $types{ uc $data_object . '_TYPE' } = { can => "${data_object}_id" };
    }

    for my $t ( keys %types ) {
        my %t = %{ $types{$t} };
        my $sub = sub { param_error "Invalid additional args for $t: [@_]" if @_ % 2;
                        return { %t, @_ } };

        no strict 'refs';
        *{$t} = $sub;
    }
}

our %EXPORT_TAGS = ( types => [ keys %types ] );
our @EXPORT_OK = keys %types;
my %MyExports = map { $_ => 1 }
    @EXPORT_OK,
    map { ":$_" } keys %EXPORT_TAGS;


sub import
{
    my $class = shift;

    my $caller = caller;

    my @pv_export = grep { ! $MyExports{$_} } @_;

    {
        eval <<"EOF";
package $caller;

use Params::Validate qw(@pv_export);
Params::Validate::set_options( on_fail => \\&Socialtext::Exceptions::param_error );
EOF

        die $@ if $@;
    }

    $class->export_to_level( 1, undef, grep { $MyExports{$_} } @_ );
}

1;

__END__

=head1 NAME

Socialtext::Validate - The great new Socialtext::Validate!

=head1 SYNOPSIS


  use Socialtext::Validate qw( FILE_TYPE );

  use Socialtext::Validate ':types';

=head1 EXPORT

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc., All Rights Reserved.

=cut
