package Socialtext::l10n::I18N::xr;

use strict;
use warnings;
use base 'Locale::Maketext';

our %Lexicon = ( _AUTO => 1 );

sub maketext {
    my $self   = shift;
    my %leet   = ( a => 4, e => 3, o => 0, t => 7, b => 8 );
    my $c      = 0;
    my $result = join "", map { ( $c++ % 2 ) ? uc($_) : $_ }
        map { defined( $leet{$_} ) ? $leet{$_} : $_ }
        map lc, split //, shift;
    $result =~ s/qu4n7/quant/gi;
    $result =~ s/<4 hr3f/<a href/gi;
    return $self->SUPER::maketext($result, @_);
}

1;

__END__

=head1 NAME

Socialtext::l10n::I18N::xr

=head1 SYNOPSIS

  Blah => 8l4h

=head1 DESCRIPTION

xr is a l33t sp34k locale.

=cut
