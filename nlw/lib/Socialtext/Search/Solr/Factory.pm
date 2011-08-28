package Socialtext::Search::Solr::Factory;
# @COPYRIGHT@
use strict;
use warnings;

use Socialtext::l10n qw(system_locale);
use Socialtext::Search::Solr::Indexer;
use Socialtext::Search::Solr::Searcher;
use Socialtext::AppConfig;
use Socialtext::Exceptions;
use base 'Socialtext::Search::AbstractFactory';

=head1 NAME

Socialtext::Search::Solr::Factory

=head1 SYNOPSIS

  my $s = Socialtext::Search::Solr::Factory->create_searcher($workspace_name);
  $s->search(...);

=head1 DESCRIPTION

Factory class for creating Solr indexers and searchers

=cut

# Rather than create an actual object (since there's no state), just return
# the class name.  This will continue to make all the methods below work.
sub new { $_[0] }

sub create_searcher {
    my ( $self, $ws_name, %param ) = @_;
    return $self->_create( "Searcher", $ws_name, %param );
}

sub create_indexer {
    my ( $self, $ws_name, %param )  = @_;
    return $self->_create( "Indexer", $ws_name, %param );
}

sub _create {
    my $self = shift;
    my ( $kind, $ws_name, %param ) = @_;
    
    my $class = 'Socialtext::Search::Solr::' . $kind;
    return $class->new( $ws_name ? (ws_name => $ws_name) : () );
}

=head2 $factory->template_vars()

Returns a list of variables to pass to templates.

=cut

sub template_vars {
    my $self = shift;
    return (
        partial_set => 1,
        no_user_sorting => 1,
    );
}

sub search_on_behalf {
    my $self               = shift;
    my $workspaces         = shift;
    my $query              = shift;
    my $user               = shift;
    my $no_such_ws_handler = shift;
    my $authz_handler      = shift;
    my %opts               = @_;

    my $hit_threshold = Socialtext::AppConfig->search_warning_threshold || 500;

    my $thunk = sub {};
    my $num_hits = 0;
    eval {
        ($thunk, $num_hits)
            = $self->_search_workspaces($user, $workspaces, $query, %opts);
    };
    if (my $e = $@) {
        die $e unless ref $e;
        if ($e->isa('Socialtext::Exception::NoSuchResource')) {
            $e->rethrow unless defined $no_such_ws_handler;
            $no_such_ws_handler->($e);
        }
        elsif ($e->isa('Socialtext::Exception::Auth')) {
            $e->rethrow unless defined $authz_handler;
            $authz_handler->($e) if defined $authz_handler;
        }
        else {
            $e->rethrow;
        }
    }

    # Evaluate the thunk now that we're sure that the results are of
    # reasonable size
    my $hits = $thunk->();

    return $hits, $num_hits;
}

sub _search_workspaces {
    my $self = shift;
    my $user = shift;
    my $workspaces = shift;
    my $query = shift;

    my $authorizer = $self->_make_authorizer($user);
    for my $workspace (@$workspaces) {
        unless ($authorizer->($workspace)) {
            Socialtext::Exception::Auth->throw;
        }
    }

    # Searcher needs a workspace, which is kinda dumb in the case of
    # inter-workspace search.
    my $searcher = $self->create_searcher($workspaces->[0]);
    return $searcher->begin_search(
        $query,
        undef,  # authorizer
        $workspaces,
        (viewer => $user),
        @_
    );
}


1;
__END__

=pod

=head1 NAME

Socialtext::Search::Solr::Factory

=head1 SEE

L<Socialtext::Search::AbstractFactory> for the interface definition.

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
