package Socialtext::Search;
use warnings;
use strict;

use base 'Exporter';

use Socialtext::AppConfig;

our @EXPORT_OK = qw( search_on_behalf );

sub search_on_behalf {
    my $ws_name = shift;
    my $query = shift;
    my $scope = shift || '_';
    my $user = shift;
    my $no_such_ws_handler = shift;
    my $authz_handler = shift;
    my %opts = @_;

    my @workspaces = _enumerate_workspaces($scope, $user, $ws_name, \$query);

    my $factory = Socialtext::Search::AbstractFactory->GetFactory();
    return $factory->search_on_behalf(\@workspaces, $query, $user,
        $no_such_ws_handler, $authz_handler, %opts);
}

sub _enumerate_workspaces {
    my ($scope, $user, $current_workspace, $query_ref) = @_;
    my @workspaces;

    # We reserve two set names: _ and *. _ represents the current workspace,
    # while * represents all workspaces where the current user is a member.
    # However, when the user is at the global dashboard and not inside any
    # particular workspace, _ becomes a synonym to *.
    if ($$query_ref =~ s/\bworkspaces:(\S+)//) {
        if ($1 eq '*') {
            @workspaces = _all_workspaces($user, $current_workspace);
        }
        else {
            @workspaces = split /,/, $1;
        }
    }
    elsif ($scope eq '*') {
        @workspaces = _all_workspaces($user, $current_workspace);
    }
    elsif ($scope eq '_') {
        if (length $current_workspace) {
            @workspaces = ($current_workspace);
        }
        else {
            @workspaces = _all_workspaces($user);
        }
    }

    return @workspaces;
}


sub _all_workspaces {
    my ($user, $current_workspace) = @_;
    my @workspaces = map { $_->name }
        $user->workspaces->all();

    # always include the current workspace, in case the user isn't
    # a member
    if (defined $current_workspace and length $current_workspace) {
        push @workspaces, $current_workspace;
    }

    my %uniq = map {$_=>1} @workspaces;
    @workspaces = keys %uniq;
}

1;

=head1 NAME

Socialtext::Search - The NLW search API.

=head1 SYNOPSIS

    package MySearch::Searcher;

    use base 'Socialtext::Search::Searcher';

    sub new { # you'll need a constructor
    }

    sub search {
        my ( $self, $query_string ) = @_;

        # ... return a list of search hits
    }

    package MySearch::Indexer;

    use base 'Socialtext::Search::Indexer';

    sub new { # you'll need a constructor
    }

    sub index_page {
        my ( $self, $page_uri ) = @_;

        # update index contents for the give page
    }

    sub index_attachment;
    sub index_workspace;
    sub delete_page;
    sub delete_attachment;
    sub delete_workspace;

    package MySearch::Factory;
    
    use MySearch::Searcher;
    use MySearch::Indexer;

    sub new {
        my ( $class ) = @_;

        # ... create a new factory
    }

    sub create_indexer {
        my ( $self, $workspace_name ) = @_;

        MySearch::Indexer->new( $workspace_name );
    }

    sub create_searcher {
        my ( $self, $workspace_name ) = @_;

        MySearch::Indexer->new( $workspace_name );
    }

=head1 DESCRIPTION

The C<Socialtext::Search> namespace holds interface definitions for NLW's search API
as well as any implementations developed by Socialtext.  The API is designed
using the Abstract Factory design pattern (see
L<http://en.wikipedia.org/wiki/Abstract_factory>) in order to hide both
implementation selection and implementation details from calling applications.

=head1 USING THE SEARCH API

Callers will either want to search or index documents.

=head2 SEARCHING

    use Socialtext::Search::AbstractFactory;

    my $factory = Socialtext::Search::AbstractFactory->GetFactory;
    my $searcher = $factory->create_searcher('my_workspace');
    my @hits = $searcher->search('fnord');

    foreach my $hit (@hits) {
        if ($hit->isa('Socialtext::Search::PageHit')) {
            print "'fnord' found in page ", $hit->page_uri;
        } elsif ($hit->isa('Socialtext::Search::AttachmentHit')) {
            print "'fnord' found in attachment to page",
                $hit->page_uri,
                ".  Attachment id ", $hit->attachment_id;
        }
    }

=head2 INDEXING

    # Let's assume @pages is a list of Socialtext::Page objects
    # you wish to index, and @attachments is a similar list of
    # Socialtext::Attachment objects.

    use Socialtext::Search::AbstractFactory;

    my $factory = Socialtext::Search::AbstractFactory->GetFactory;
    my $indexer = $factory->create_indexer('my_workspace');

    foreach my $page (@pages) {
        $indexer->index_page( $page->id );
    }

    foreach my $attachment (@attachments) {
        $indexer->index_attachment(
            $attachment->page_id,
            $attachment->id
        );
    }

=head1 WRITING A SEARCH INTERFACE

Writing a search interface means, at a minimum, writing implementations of the
following interfaces.

=over 2

=item L<Socialtext::Search::AbstractFactory>

=item L<Socialtext::Search::Indexer>

=item L<Socialtext::Search::Searcher>

=back

When implementing L<Socialtext::Search::Searcher>, you will need to return
L<Socialtext::Search::PageHit> and L<Socialtext::Search::AttachmentHit> objects.  You may
find the simple implementations L<Socialtext::Search::SimplePageHit> and
L<Socialtext::Search::SimpleAttachmentHit> of use.

Once the code for your implementations is installed, you simply need to set
the C<search_factory_class> AppConfig key, for example by editing
C</etc/Socialtext/Socialtext.conf> and inserting the line

  search_factory_class: MySearch::Factory

See L<Socialtext::AppConfig> for other ways of setting AppConfig keys.

=head1 SEE ALSO

B<Interfaces>:
L<Socialtext::Search::AbstractFactory>,
L<Socialtext::Search::Indexer>,
L<Socialtext::Search::Searcher>,
L<Socialtext::Search::PageHit>,
L<Socialtext::Search::AttachmentHit>

B<Useful implementations>:
L<Socialtext::Search::SimplePageHit>,
L<Socialtext::Search::SimpleAttachmentHit>

B<Sample implementations>:
L<Socialtext::Search::Plucene::AbstractFactory>,
L<Socialtext::Search::Plucene::Indexer>,
L<Socialtext::Search::Plucene::Searcher>,
L<Socialtext::Search::Basic::AbstractFactory>,
L<Socialtext::Search::Basic::Indexer>,
L<Socialtext::Search::Basic::Searcher>,

B<Collaborators>:
L<Socialtext::AppConfig>,
L<Socialtext::Page>,
L<Socialtext::Attachment>,
L<Socialtext::Paths>,
L<Socialtext::Workspace>

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
