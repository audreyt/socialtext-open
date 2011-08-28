# @COPYRIGHT@
package Socialtext::File::Stringify::audio_mpeg;
use strict;
use warnings;

use Socialtext::File::Stringify::Default;

sub to_string {
    my ( $class, $buf_ref, $file, $mime ) = @_;
    $$buf_ref = "";
    eval {
        require MP3::Tag;
        my $mp3  = MP3::Tag->new($file);
        my $info = $mp3->autoinfo();
        die unless defined $info;
        for my $tag ( reverse sort keys %$info ) {
            $$buf_ref .= uc($tag) . ": $info->{$tag}\n";
        }
    };
    Socialtext::File::Stringify::Default->to_string($buf_ref, $file, $mime) if $@;
    return;
}

1;

=head1 NAME

Socialtext::File::Stringify::audio_mpeg - Stringify MP3 files

=head1 METHODS

=over

=item to_string($filename)

Extracts the stringified content from C<$filename>, an MP3 file, by extracting
all of the MP3 Tags.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT

Copyright 2006 Socialtext, Inc., all rights reserved.

=cut
