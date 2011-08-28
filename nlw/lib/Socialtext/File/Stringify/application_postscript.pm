# @COPYRIGHT@
package Socialtext::File::Stringify::application_postscript;
use strict;
use warnings;

use Socialtext::File::Stringify::Default;
use Socialtext::System;

sub to_string {
    my ( $class, $buf_ref, $file, $mime ) = @_;
    Socialtext::System::backtick( "ps2ascii", $file, {stdout => $buf_ref} );
    Socialtext::File::Stringify::Default->to_string($buf_ref, $file, $mime)
        if $? or $@;
}

1;

=head1 NAME

Socialtext::File::Stringify::application_postscript - Stringify Postscript documents

=head1 METHODS

=over

=item to_string($filename)

Extracts the stringified content from C<$filename>, a Postscript document.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT

Copyright 2006 Socialtext, Inc., all rights reserved.

=cut
