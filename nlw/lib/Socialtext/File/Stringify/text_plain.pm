# @COPYRIGHT@
package Socialtext::File::Stringify::text_plain;
use strict;
use warnings;

use Socialtext::File;
use Socialtext::File::Stringify;
use Socialtext::l10n qw/system_locale/;
use Socialtext::Log qw/st_log/;
use Socialtext::AppConfig;
use Encode;

sub to_string {
    my ( $class, $buf_ref, $filename, $mime ) = @_;
    $$buf_ref = '';

    open my $fh, '<:mmap', $filename or return;
    (my $charset) = ($mime =~ /;charset=(\S+)/);
    unless ($charset) {
        my $guess_buf;
        # Only read some small number of bytes, as the file may have binary
        # junk farther on (in the case of shell script + binary installers)
        read $fh, $guess_buf, 128;
        # Guess the encoding, but fall back to 8859 so that all bytes are
        # valid when decoding
        $charset = Socialtext::File::guess_string_encoding(
            system_locale(),\$guess_buf) || 'ISO-8859-1';
    }

    st_log()->warning("Using charset $charset for text/plain file");
    my $limit = Socialtext::AppConfig->stringify_max_length;
    eval {
        seek $fh, 0, 0;
        read($fh, (my $data), $limit);
        # This will decode up until the first error. Data beyond that will be
        # discarded.
        $$buf_ref = Encode::decode($charset, $data, Encode::RETURN_ON_ERR);
    };
    if ($@) {
        st_log()->warning("could not decode attachment charset '$charset': $@'");
    }
    return;
}

1;

=head1 NAME

Socialtext::File::Stringify::text_plain - Stringify text documents

=head1 METHODS

=over

=item to_string($filename)

Extracts the stringified content from C<$filename>, a text document.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT

Copyright 2006 Socialtext, Inc., all rights reserved.

=cut
