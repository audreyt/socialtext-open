package Socialtext::l10n::I18N::zz;

use strict;
use warnings;
use base 'Locale::Maketext';

sub numf {
    my ($self, $num) = @_;
    while ($num =~ s/^([-+]?\d+)(\d{3})/$1,$2/s) {1}
    $num =~ tr<.,><, >; # "1,234.56" => "1 234,56"
    return $num;
}

1;

__END__

=head1 NAME

Socialtext::l10n::I18N::zz

=head1 SYNOPSIS

  Blah => Zzzz

=head1 DESCRIPTION

Replace all the text with Zzzzz.

=cut
