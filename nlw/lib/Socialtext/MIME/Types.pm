package Socialtext::MIME::Types;
# @COPYRIGHT@
use strict;
use warnings;
use MIME::Types;

use base qw(Exporter);
our @EXPORT_OK = qw(mimeTypeOf);

# Force initialization right away, so any forked processes get the complete
# list of MIME-Types (otherwise only the _first_ process to query a MIME Type
# gets the list and the others get nothing).
BEGIN { MIME::Types->init( { only_complete => 1 } ) };

sub mimeTypeOf {
    my $file = shift;
    return MIME::Types->new->mimeTypeOf($file);
}

1;

=head1 NAME

Socialtext::MIME::Types - MIME::Types wrapper/replacement

=head1 SYNOPSIS

  use Socialtext::MIME::Types;

  my $type = Socialtext::MIME::Types::mimeTypeOf($filename);

=head1 DESCRIPTION

This module serves as a wrapper/replacement for C<MIME::Types>.

C<MIME::Types> has trouble being shared across processes unless used
correctly... if you don't initialize the list of MIME-Types in the parent
process, only I<one> of the child processes gets to initialize the list.

Rather than have to deal with doing this multiple times in multiple places,
we're wrapping it here in this module.

=head1 COPYRIGHT & LICENSE

Copyright 2010 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
