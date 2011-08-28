# @COPYRIGHT@
package Socialtext::File::Stringify::application_msword;
use strict;
use warnings;

use File::Temp;
use Socialtext::File;
use Socialtext::File::Stringify::Default;
use Socialtext::System qw/backtick/;
use Socialtext::Log qw/st_log/;

sub to_string {
    my ( $class, $buf_ref, $filename, $mime ) = @_;

    my $tmp = File::Temp->new(
        TEMPLATE =>
            Socialtext::File::temp_template_for('indexing_word_attachment'),
    );
    my $temp_filename = $tmp->filename;
    $tmp->unlink_on_destroy(1);

    # NOTE: wvText actually uses elinks internally for some HTML conversion
    # (no idea why).
    my $ignored = '';
    backtick('wvText', $filename, $temp_filename, {stdout => \$ignored});
    if (my $err = $@) {
        st_log->warning("Failed to index $filename: $err");
        Socialtext::File::Stringify::Default->to_string($buf_ref, $filename,
            $mime);
    }
    else {
        # TODO - this should use tika
        # TODO - can we make a get_contents that reads into a scalar-ref?
        $$buf_ref = Socialtext::File::get_contents_utf8($temp_filename);
    }
}

1;

=head1 NAME

Socialtext::File::Stringify::application_msword - Stringify MS Word documents

=head1 METHODS

=over

=item to_string($filename)

Extracts the stringified content from C<$filename>, an MS Word document.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT

Copyright 2006 Socialtext, Inc., all rights reserved.

=cut
