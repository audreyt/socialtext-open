# @COPYRIGHT@
package Socialtext::File::Stringify::application_vnd_ms_excel;
use strict;
use warnings;

use Socialtext::File::Stringify::Default;
use Socialtext::System;

sub to_string {
    my ( $class, $buf_ref, $file, $mime ) = @_;
    Socialtext::System::backtick( "xls2csv", $file, {stdout => $buf_ref} );
    if ( $? or $@ ) {
        Socialtext::File::Stringify::Default->to_string($buf_ref, $file, $mime);
    }
    elsif ( defined $$buf_ref ) {
        $$buf_ref =~ s/^"|"$//mg;
        $$buf_ref =~ s/"+/"/g;
    }
}

1;

=head1 NAME

Socialtext::File::Stringify::application_vnd_ms_excel - Stringify MS Excel documents

=head1 METHODS

=over

=item to_string($filename)

Extracts the stringified content from C<$filename>, an MS Excel document.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT

Copyright 2006 Socialtext, Inc., all rights reserved.

=cut
