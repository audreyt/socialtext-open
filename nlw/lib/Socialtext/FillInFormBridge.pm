# @COPYRIGHT@
package Socialtext::FillInFormBridge;
use strict;
use warnings;

use Scalar::Util ();

use Params::Validate
    qw( validate_pos HASHREF OBJECT );

use HTML::FillInForm::ForceUTF8;


sub New {
    my $class = shift;
    validate_pos( @_, ( { type => HASHREF | OBJECT } ) x @_ );

    return bless { sources => [ @_ ] }, $class;
}

sub param {
    my $self = shift;
    my $param = shift;

    foreach my $s ( @{ $self->{sources} } ) {
        if ( Scalar::Util::blessed($s) ) {
            return $s->$param() if $s->can($param);
        }
        else {
            return $s->{$param} if exists $s->{$param};
        }
    }

    return;
}


1;

__END__

=head1 NAME

Socialtext::FillInFormBridge - The great new Socialtext::FillInFormBridge!

=head1 SYNOPSIS


=head1 AUTHOR

Socialtext, C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc. All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
