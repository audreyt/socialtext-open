# @COPYRIGHT@
package Socialtext::Formatter::Wafl;
use strict;
use warnings;

use base 'Socialtext::Base';

use Class::Field qw( const );

const contains_phrases => [];

# Because -- cannot appear inside HTML comments, we escape '-' characters
# here into '-='.  Because '=' is our trailing escape character, we first
# escape '=' to '=='.  This transform will be reversed inside
# Wikiwyg/Socialtext.js and Wikiwyg/Widgets.js.
sub escape_wafl_dashes {
    shift;
    my $html = shift || '';

    $html =~ s/=/==/g;
    $html =~ s/-/-=/g;

    return $html;
}

1;

__END__

=head1 NAME

Socialtext::Formatter::Wafl - Wiki Abstract Formatting Language

=head1 DESCRIPTION

Wafl is a flexible way of adding additional formatting functionality,
often dynamic, to a wikitext syntax. It comes in two forms
L<Socialtext::Formatter::WaflBlock> and L<Socialtext::Formatter::WaflPhrase>.

=head1 METHODS

=over 4

=item escape_wafl_dashes 

For Wikiwyg, we need to turn HTML comments within wikihints
into something else. Otherwise dom parsing gets in trouble.

=back

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., All Rights Reserved.

=cut
