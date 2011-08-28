# @COPYRIGHT@
use warnings;
use strict;

=head1 NAME

Socialtext::Search::Basic::Searcher - Basic grep-through-the-files Socialtext::Search::Searcher implementation.

=cut

package Socialtext::Search::Basic::Searcher;

use base 'Socialtext::Search::Searcher';

use Encode ();
use Socialtext::Hub;
use Socialtext::Pages;
use Socialtext::Search::SimplePageHit;
use Socialtext::Workspace;
use Socialtext::String ();

sub new {
    my ( $class, $workspace_name ) = @_;

    my $workspace = Socialtext::Workspace->new( name => $workspace_name );

    bless {

        # WARNING!  This hub is bogus!
        # It is only complete enough to access specific legacy routines.
        hub            => Socialtext::Hub->new( current_workspace => $workspace ),
        workspace_name => $workspace_name,
    }, $class;
}

sub search {
    my ( $self, $query_string ) = @_;

    my $flat_terms = Socialtext::String::title_to_id($query_string, 'no-escape');

    Encode::_utf8_on($flat_terms);

    my @search_terms = split '_', $flat_terms;

    return $self->_search_pages(
        $query_string !~ /^(?:=|title:)/,
        @search_terms
    );
}

sub _search_pages {
    my ( $self, $search_body, @search_terms ) = @_;
    my @hits;

    for my $page_id ( $self->hub->pages->all_ids_newest_first ) {
        my $page = $self->hub->pages->new_page($page_id);
        $page->load;

        # XXX It would be a nice optimization to know whether a page was
        # deleted without needing to read the headers. Then we could do fast
        # title searches.
        unless ($page->deleted) {
            push @hits, Socialtext::Search::SimplePageHit->new($page_id)
                if ($self->_title_matches( $page, @search_terms )
                || (
                    $search_body
                    && $self->_body_matches( $page, @search_terms )
                ));
        }
    }

    return @hits;
}

sub _title_matches {
    my ( $self, $page, @search_terms ) = @_;

    my $page_title = lc $page->title;

    for my $search_term (@search_terms) {
        return 0 unless $page_title =~ /\Q$search_term\E/;
    }
    
    return 1;
}

sub _body_matches {
    my ( $self, $page, @search_terms ) = @_;

    my $body = lc $page->content;

    for my $search_term (@search_terms) {
        return 0 unless $body =~ /\Q$search_term\E/;
    }
    
    return 1;
}

sub hub { $_[0]->{hub} }

=head1 SEE

L<Socialtext::Search::Searcher> for the interface definition.

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
