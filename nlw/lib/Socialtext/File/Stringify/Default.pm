# @COPYRIGHT@
package Socialtext::File::Stringify::Default;
use strict;
use warnings;

use Socialtext::System;
use Socialtext::MIME::Types;

sub to_string {
    my ( $class, $buf_ref, $filename, $mime ) = @_;

    Socialtext::System::backtick('strings', $filename,
        { stdout => $buf_ref });
}

1;

=head1 NAME

Socialtext::File::Stringify::Default - Default stringifier

=head1 DESCRIPTION

Default stringifier, when nothing else is willing to handle it.

=head1 METHODS

=over

=item to_string($filename)

Extracts the stringified content from C<$filename>, using F<strings>.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT

Copyright 2006 Socialtext, Inc., all rights reserved.

=cut
