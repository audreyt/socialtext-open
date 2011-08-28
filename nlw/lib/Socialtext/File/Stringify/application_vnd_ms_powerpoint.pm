# @COPYRIGHT@
package Socialtext::File::Stringify::application_vnd_ms_powerpoint;
use strict;
use warnings;

use Socialtext::File::Stringify::Default;
use Socialtext::System;
use Socialtext::Log qw/st_log/;

sub to_string {
    my ( $class, $buf_ref, $file, $mime ) = @_;
    Socialtext::System::backtick( "catppt",  $file, {stdout => $buf_ref} );
    if ( $? or $@ ) {
        Socialtext::File::Stringify::Default->to_string($buf_ref, $file, $mime);
    }
}

1;

=head1 NAME

Socialtext::File::Stringify::application_vnd_ms_powerpoint - Stringify MS Powerpoint documents

=head1 METHODS

=over

=item to_string($filename)

Extracts the stringified content from C<$filename>, an MS Powerpoint document.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT

Copyright 2006 Socialtext, Inc., all rights reserved.

=cut
