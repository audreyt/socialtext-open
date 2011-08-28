package Socialtext::Rest::Sections;
# @COPYRIGHT@

use strict;
use warnings;

use Socialtext::String ();

# One can guess that someday there could be a 
# Socialtext::Rest::Units (so we can pull a variety of
# things out of a page) but that's the yag for now.
use base 'Socialtext::Rest::Collection';

=head1 NAME

Socialtext::Rest::Sections - A class for exposing collections of sections associated with a Page

=head1 SYNOPSIS

    GET  /data/workspaces/:ws/pages/:pname/sections

=head1 DESCRIPTION

The wikitext of a page may contain headers or sections markers that can 
be used to create anchors into the content of the page. This collection
exposes those sections so anchors may be discovered and used.

=cut
# REVIEW is load required here?
sub last_modified   { $_[0]->page->load->modified_time }
sub collection_name { "Sections for page " . $_[0]->page->title . "\n" }

sub _entities_for_query {
    my $self = shift;

    return () if $self->page->content eq '';
    return ( map { $_->{text} } @{ $self->page->get_sections() } );
}

sub _uri_for_section {
    my $self    = shift;
    my $section = shift;
    return '../' . $self->page->uri  . '#'
        . Socialtext::String::title_to_id($section);
}

sub _entity_hash {
    my $self    = shift;
    my $section = shift;

    return +{
        name => $section,
        uri  => $self->_uri_for_section($section),
    };
}

1;

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
