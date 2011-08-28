# @COPYRIGHT@
use warnings;
use strict;

package Socialtext::Search::AbstractFactory;

use Carp 'croak';
use Socialtext::AppConfig;
use Socialtext::Workspace;
use Socialtext::Authz;
use Socialtext::Exceptions;
use Socialtext::Permission 'ST_READ_PERM';

=head1 NAME

Socialtext::Search::AbstractFactory - Instantiate search-related objects.

=head1 SYNOPSIS

    $factory = Socialtext::Search::AbstractFactory->GetFactory();
    $indexer = create_indexer($workspace_name,
                              config_type => $config_type );
    # Index documents in this workspace using $indexer.

    $searcher = create_searcher($workspace_name,
                                config_type => $config_type );
    # Perform searches on this workspace using $searcher.

=head1 DESCRIPTION

C<Socialtext::Search::AbstractFactory> defines an object interface for search
factories.  A factory is simply a class which understands how to instantiate
sets of related objects.  In this case, those related objects are searchers
and indexers.

With this interface, fulltext search systems become interchangeable, and the
calling classes need not know which implementation is in use.  A call to
L</GetFactory> produces the correct factory, and that factory can produce
searcher and indexer objects which operate on the current fulltext search
implementation.

=head1 CLASS METHODS

=head2 GetFactory()

Returns an instance of the configured search factory.

=cut

sub GetFactory {
    my ( $class, %p ) = @_;

    my $factory_class = 'Socialtext::Search::Solr::Factory';

    eval "require $factory_class";
    die __PACKAGE__, "->GetFactory: $@" if $@;

    my $factory = $factory_class->new
        or die __PACKAGE__, "->GetFactory: $factory_class->new returned null";

    return $factory;
}

=head2 GetIndexers()

Returns an array of indexer objects for the current active indexers.

=cut

sub GetIndexers {
    my ( $class, $ws_name ) = @_;

    my @classes = ('Socialtext::Search::Solr::Factory');

    my @indexers;
    for my $class_name (@classes) {
        eval "require $class_name";
        die __PACKAGE__, "->GetIndexers $@" if $@;

        my $factory = $class_name->new
            or die __PACKAGE__, "->GetIndexers $class_name->new returned null";
        push @indexers, $factory->create_indexer($ws_name);
    }

    return @indexers;
}

=head1 OBJECT INTERFACE

=head2 $factory->create_searcher($workspace_name,
                                 config_type => $config_type )

Returns an implementation of the L<Socialtext::Search::Searcher> interface
which will search the given workspace.

=cut

sub create_searcher {
    my ( $self ) = @_;

    if (ref $self) {
        croak(ref $self, ": internal bug: create_searcher not implemented");
    }
    else {
        croak(__PACKAGE__, "::create_searcher called in a weird way");
    }
}

=head2 $factory->create_indexer($workspace_name,
                                config_type => $config_type )

Returns an implementation of the L<Socialtext::Search::Indexer> interface
which will search the given workspace.

=cut

sub create_indexer {
    my ( $self ) = @_;

    if (ref $self) {
        croak(ref $self, ": internal bug: create_indexer not implemented");
    }
    else {
        croak(__PACKAGE__, "::create_indexer called in a weird way");
    }
}

=head2 $factory->template_vars()

Returns a list of variables to pass to templates.

=cut

sub template_vars {
    my $self = shift;
    return ();
}

sub _make_authorizer {
    my $self = shift;
    my $user = shift;

    return sub {
        my ($workspace_name) = @_;
        my $workspace = Socialtext::Workspace->new( name => $workspace_name );

        if ( defined $workspace ) {
            return Socialtext::Authz->new->user_has_permission_for_workspace(
                user       => $user,
                permission => ST_READ_PERM,
                workspace  => $workspace );
        } else {
            Socialtext::Exception::NoSuchResource->throw(
                name => $workspace_name );
        }
    };
}


=head1 SEE ALSO

L<Socialtext::AppConfig>,
L<http://en.wikipedia.org/wiki/Abstract_factory_pattern>

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

