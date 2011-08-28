# @COPYRIGHT@
package Socialtext::UniqueArray;

use strict;
use warnings;

use Tie::IxHash;


sub new
{
    my $class = shift;

    return bless { hash => Tie::IxHash->new }, $class;
}

sub push
{
    my $self = shift;
    my $value = shift;

    return if $self->{hash}->EXISTS($value);

    $self->{hash}->Push( $value, 1 );
}

sub values
{
    my $self = shift;

    $self->{hash}->Keys;
}


1;

__END__

=head1 NAME

Socialtext::UniqueArray - An array with unique values

=head1 SYNOPSIS

  my $array = Socialtext::UniqueArray->new;

  $array->push( 'a', 'b', 'c', 'd', 'b' );

  my @vals = $array->values; # 'a', 'b', 'c', 'd'

=head1 AUTHOR

Socialtext, C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc. All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
