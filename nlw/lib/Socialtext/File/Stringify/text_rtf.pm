# @COPYRIGHT@
package Socialtext::File::Stringify::text_rtf;
use strict;
use warnings;

use Socialtext::File::Stringify::Default;
use Socialtext::System;

sub to_string {
    my ( $class, $buf_ref, $file, $mime ) = @_;
    Socialtext::System::backtick(
        "unrtf", "--nopict", "--text",
        $file, {stdout => $buf_ref}
    );

    if ( $? or $@ ) {
        Socialtext::File::Stringify::Default->to_string($buf_ref, $file, $mime);
    }
    elsif ( defined $$buf_ref ) {
        $$buf_ref =~ s/^.*?-----------------\n//s; # Remove annoying unrtf header.
    }
}

1;

=head1 NAME

Socialtext::File::Stringify::text_rtf - Stringify RTF documents

=head1 METHODS

=over

=item to_string($filename)

Extracts the stringified content from C<$filename>, an RTF document.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT

Copyright 2006 Socialtext, Inc., all rights reserved.

=cut
