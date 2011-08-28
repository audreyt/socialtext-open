package Socialtext::Rest::Tags;
# @COPYRIGHT@

use strict;
use warnings;

use Socialtext::l10n;
use Socialtext::String;

use base 'Socialtext::Rest::Collection';

sub SORTS {
    return +{
        alpha => sub {
            lcmp($Socialtext::Rest::Collection::a->{name},
                 $Socialtext::Rest::Collection::b->{name});
        },
        weighted => sub {
            $Socialtext::Rest::Collection::b->{page_count} <=>
                $Socialtext::Rest::Collection::a->{page_count};
        },
    };
}

=head1 NAME

Socialtext::Rest::Tags - A base class describing lists of tags.

=head1 REPRESENTATIONS

A list of tags may be returned as three different representations.

=over 4

=item text/plain

A linefeed separated list of tags on the page.

=item application/json

A JSON data structure of an Array of tag objects including name,
uri and page_count. Page count is the number of pages that are
currently using this tag.

=item text/html

An HTML page listing each tag with a link to the tag.

=back

=cut
sub _uri_for_tag    {'tags/' . Socialtext::String::uri_escape($_[1])}

sub _entity_hash {
    my $self = shift;
    my $tag  = shift;

    if (ref($tag) eq 'HASH') {
        $tag->{value} ||= lc $tag->{name};
        $tag->{uri} = $self->_uri_for_tag($tag->{name});
        $tag->{page_count} += 0;
        return $tag;
    }

    return +{
        value => lc($tag),
        name => $tag,
        uri  => $self->_uri_for_tag($tag),
        page_count => $self->hub->category->page_count($tag),
    };
}

1;
=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
