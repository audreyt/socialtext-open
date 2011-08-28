# @COPYRIGHT@
package Socialtext::File::Stringify::application_zip;
use strict;
use warnings;

use File::Find;
use File::Path;
use File::Temp;

use Socialtext::File::Stringify;
use Socialtext::File::Stringify::Default;
use Socialtext::System;
use Socialtext::Encode qw/ensure_ref_is_utf8/;
use Socialtext::AppConfig;

sub to_string {
    my ( $class, $buf_ref, $file, $mime ) = @_;

    # Unpack the zip file in a temp dir.
    my $tempdir = File::Temp::tempdir( CLEANUP => 1 );
    {
        my $ignored; # need to capture it or unzip won't work
        Socialtext::System::backtick("unzip",
            '-q', '-P', '', # don't prompt for password
            $file, '-d', $tempdir,
            {stdout => \$ignored, stdin => \undef} );

        if ($@ or $?) {
            # if it fails it makes *no* sense to run strings on it
            $$buf_ref = '';
            return;
        }
    }

    # Find all the files we unpacked.
    my @files;
    find sub {
        push @files, $File::Find::name if -f $File::Find::name;
    }, $tempdir;

    # Stringify each the files we found
    $$buf_ref = "";
    Encode::_utf8_on($$buf_ref); # infectious
    for my $f (@files) {
        (my $shortname = $f) =~ s!\Q$tempdir/\E!!;
        $$buf_ref .= "$shortname ";
        next if $shortname =~ m/\.DS_Store$/;
        my $file_buf;
        Socialtext::File::Stringify->to_string(\$file_buf, $f);
        if (length $file_buf) {
            ensure_ref_is_utf8(\$file_buf);
            $$buf_ref .= $file_buf;
            last if length($$buf_ref)
                >= Socialtext::AppConfig->stringify_max_length;
        }
    }

    # Cleanup and return the text if we got any, 'else use the default.
    File::Path::rmtree($tempdir);
    _default($buf_ref, $file, $mime) unless $$buf_ref;
    return;
}

sub _default { Socialtext::File::Stringify::Default->to_string(@_) }

1;

=head1 NAME

Socialtext::File::Stringify::application_zip - Stringify contents of Zip files

=head1 METHODS

=over

=item to_string($filename)

Recursively extracts the stringified content of B<all> of the documents
contained within the given C<$filename>, a Zip archive.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT

Copyright 2006 Socialtext, Inc., all rights reserved.

=cut
