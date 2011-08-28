# @COPYRIGHT@
package Socialtext::String;
use strict;
use warnings;
use HTML::Entities ();
use URI::Escape ();
use HTML::Truncate;
use parent 'Exporter';

use constant MAX_PAGE_ID_LEN => 255;
use constant BOM => chr(0xFEFF);

our @EXPORT = ();
our @EXPORT_OK = qw/
    MAX_PAGE_ID_LEN BOM
    html_escape html_unescape
    trim scrub
    uri_escape uri_unescape
    double_space_harden
    word_truncate html_truncate
    title_to_id title_to_display_id
/;
our %EXPORT_TAGS = (
    'html' => [qw/html_escape html_unescape/],
    'uri' => [qw/uri_escape uri_unescape/],
    'id' => [qw/title_to_id title_to_display_id/],
);

=head1 NAME

Socialtext::String - A collection of handy string functions.

=head1 SYNOPSIS

    use Socialtext::String qw/:uri/;
    uri_escape("bl/a/h"); # runs uri_escape_utf8
    uri_unescape("%2F");

    use Socialtext::String qw/:html/;
    html_escape(">>rad<<"); # escapes minimal html/xml chars
    html_unescape($escaped);

    use Socialtext::String qw/:id/;
    title_to_id("Page Title"); # see POD; transforms a page title into a page ID
    title_to_display_id("Incipient Page Title"); # see POD

=head1 CONSTANTS

=head2 MAX_PAGE_ID_LEN

Returns the maximum length of a page id.

=head2 BOM

Returns the BOM as a perl-unicode string (0xFEFF)

=head1 FUNCTIONS

All functions are importable.

=head2 html_escape ($str)

=head2 html_unescape ($entity_str)

Escape returns an HTML-escaped version of the C<$str>, replacing C<< <>&"' >>
with their HTML entities.

Unescape decodes HTML entities into characters.

=cut

sub html_escape {
    return HTML::Entities::encode_entities(shift, q/<>&"'/);
}

sub html_unescape { 
    return HTML::Entities::decode_entities(shift);
}

=head2 uri_escape ($str)

=head2 uri_unescape ($uri_str)

Return an escaped version of C<$str> using L<URI::Escape>'s uri_escape_utf8.

Unescape reverses this (and should decode utf8 properly).

=cut

sub uri_escape {
    return URI::Escape::uri_escape_utf8(shift);
}

sub uri_unescape {
    return URI::Escape::uri_unescape(shift)
}

=head2 trim $str

Returns a copy of C<$str> with leading and trailing whitespace removed.

=cut

sub trim ($) {
    my $str = shift;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    return $str;
}

=head2 scrub $str

Returns a copy of C<$str> with XML tags, C<< < > >> characters and leading and trailing whitespace removed.

=cut

sub scrub ($) {
    my $str = shift;
    $str =~ s/<[^>]*>//g;
    $str =~ s![<>]!!g;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    return $str;
}

=head2 double_space_harden ($str)

Adds hard spaces in C<$str> where there's two space characters.

=cut

sub double_space_harden {
    my $str = shift;
    $str =~ s/  / \x{00a0}/g;
    return $str;
}

=head2 word_truncate ($str, $length, [$ellipsis])

Return a truncated C<$str> to a maximum of C<$length> characters and append
C<$ellipsis> if text was truncated.  C<word_truncate> breaks on whitespace, so
that words are not chopped in half.

C<$ellipsis> defaults to '...' (not the unicode one).

=cut

sub word_truncate {
    my ($string, $length, $ellipsis) = @_;
    $ellipsis ||= '...';
    return $ellipsis if !$length;

    my $new_string = '';

    return $string if (length($string) <= $length);
    return $ellipsis if (0 == $length);

    my @parts = split / /, $string;

    if (scalar(@parts) == 1) {
        $new_string = substr $string, 0, $length;
    }
    else {
        foreach my $part (@parts) {
            last if ((length($new_string) + length($part)) > $length);
            $new_string .= $part . ' ';
        }
        $new_string = substr($parts[0], 0, $length) if (length($new_string) == 0);

    }

    $new_string =~ s/\s+$//;
    $new_string .= $ellipsis;
    return $new_string;
}

=head2 html_truncate ($str, $length)

Return an L<HTML::Truncate>-ed C<$str> to a maximum of C<$length> characters.
The C<utf8_mode> is on for the truncator.  HTML tags won't be split.

=cut

sub html_truncate {
    my ($string, $length) = @_;
    return $string if length($string) <= $length;

    my $t = HTML::Truncate->new(utf8_mode => 1, chars => $length);
    return $t->truncate($string);
}

=head2 title_to_id ($str)

=head2 title_to_id ($str, 1)

Returns the URI-encoded ID of a page given it's name/title.

For example, this converts "Check it: My  Awesome page" to
"check_it_my_awesome_page".

The ID is run through C<uri_escape> by default; pass a second parameter to
skip this.

The transformation is roughly:

=over 4

=item 1

Replace anything that isn't a Letter, Number, ConnectorPunctuation or Mark
(L<perlunicode> for what these mean) with an underscore.  Note this means
whitespace is underscore-ified.

=item 2

Replace runs of underscores with a single underscore and remove
leading/trailing underscores.

=item 3

If the ID is "0", replace it with "_"

=item 4

Lower-case and optionally uri-escape the ID.

=back

=cut

sub title_to_id ($;$) {
    my ($id, $no_escape) = @_;

    # NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE #
    #                                                         #
    #  / \   If you change this function be sure to update    #
    # / ! \  dev-bin/generate-title-to-id-js.pl and whatever  #
    # -----  uses that javascript function too!               #
    #                                                         #
    # NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE #

    # other places this function shows up:
    # * share/skin/s3/javascript/s3.js
    # * share/skin/common/javascript/Socialtext/lib/Socialtext/Workspace.js
    # * lib/Socialtext/Template/Plugin/flatten.pm

    $id = '' if not defined $id;
    $id =~ s/^\s+//;
    $id =~ s/\s+$//;
    $id =~ s/[^\p{Letter}\p{Number}\p{ConnectorPunctuation}\pM]+/_/g;
    $id =~ s/_+/_/g;
    $id =~ s/^_(?=.)//;
    $id =~ s/(?<=.)_$//;
    $id =~ s/^0$/_/;
    $id = lc($id);

    return uri_escape($id) unless $no_escape;
    return $id;
}

=head2 title_to_display_id ($str)

=head2 title_to_display_id ($str, 1)

Returns a URI-encoded display id of a page given it's name (title).  Unlike
C<title_to_id> this function preserves case.  This is handy for making
incipient links.

For example, converts "Check it: My  Awesome page/rant" to
"Check%20it%3A%20My%20Awesome%20page%2Frant".

The ID is run through C<uri_escape> by default; pass a second parameter to
skip this.

=cut

sub title_to_display_id ($;$) {
    my ($id, $no_escape) = @_;
    $id = '' if not defined $id;
    $id =~ s/\s+/ /g;
    $id =~ s/^\s(?=.)//;
    $id =~ s/(?<=.)\s$//;
    $id =~ s/^0$/_/;
    return $no_escape ? $id : uri_escape($id);
}

1;
