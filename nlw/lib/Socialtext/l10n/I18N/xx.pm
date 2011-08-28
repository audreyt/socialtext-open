package Socialtext::l10n::I18N::xx;

use strict;
use warnings;
use base 'Locale::Maketext';

our %Lexicon = ( _AUTO => 1 );

sub maketext {
    my $self   = shift;
    my @tokens = split(/(&\w+;|<[^>]*|quant)/, shift);
    my $result = '';
    for my $token (@tokens) {
        unless ($token =~ /^(?:<|&\w+;|quant$)/) {
            $token =~ s/[[:upper:]]/X/g;
            $token =~ s/[[:lower:]]/x/g;
        }

        $result .= $token;
    }
    return $self->SUPER::maketext($result, @_);
}

1;

__END__

=head1 NAME

Socialtext::l10n::I18N::xq

=head1 SYNOPSIS

  Blah => Xxxx

=head1 DESCRIPTION

Replace all the text with Xxxxx.

=cut
