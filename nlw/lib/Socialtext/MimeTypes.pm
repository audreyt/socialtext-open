package Socialtext::MimeTypes;

use warnings;
use strict;

=head1 NAME

Socialtext::MimeTypes - Definitions of standard mime types used at Socialtext.

=head1 SYNOPSIS

    use Socialtext::MimeTypes 'WIKITEXT_MIME_TYPE';

    print "Content-type: ", WIKITEXT_MIME_TYPE, "\n\n";
    print $page->content;

=head1 DESCRIPTION

This package provides a single standard place to define any mime types we need
to mention in multiple places across the code.  Since the best practice for a
given format often changes with time (e.g., C<text/x.socialtext-wiki> changing
to C<text/vnd.socialtext.wiki>), it is best to abstract the actual names.

=cut

use base 'Exporter';

our @EXPORT_OK = qw( JSON_MIME_TYPE WIKITEXT_MIME_TYPE );

=head1 EXPORTABLE TYPES

=head2 JSON_MIME_TYPE

A mime type for JSON representations.

=cut

sub JSON_MIME_TYPE() { 'application/json' }

=head2 WIKITEXT_MIME_TYPE

A mime type for raw Socialtext wikitext.

=cut

sub WIKITEXT_MIME_TYPE() { 'text/x.socialtext-wiki' }

=head1 BUGS

Many applications and libraries won't really give a shit what MIME type you
say anyway.

=head1 SEE ALSO

IANA's media type registry at
L<http://www.iana.org/assignments/media-types/application/>,
RFC 4288 (L<http://www.isi.edu/in-notes/rfc4288.txt>)
for details on specifying and registering media types.

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
