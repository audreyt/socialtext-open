# @COPYRIGHT@
package Socialtext::File::Stringify::application_pdf;
use strict;
use warnings;

use Socialtext::File::Stringify::Default;
use Socialtext::System;

sub to_string {
    my ( $class, $buf_ref, $file, $mime ) = @_;
    Socialtext::System::backtick( "pdftotext", "-enc", "UTF-8", $file, "-",
        { stdout => $buf_ref });
    Socialtext::File::Stringify::Default->to_string($buf_ref, $file, $mime)
        if $? or $@;
    return;
}

1;

=head1 NAME

Socialtext::File::Stringify::application_pdf - Stringify PDF documents

=head1 METHODS

=over

=item to_string($filename)

Extracts the stringified content from C<$filename>, a PDF document.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT

Copyright 2006 Socialtext, Inc., all rights reserved.

=cut
