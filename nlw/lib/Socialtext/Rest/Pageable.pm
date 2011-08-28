package Socialtext::Rest::Pageable;
# @COPYRIGHT@
use Moose::Role;

use constant max_per_page => 100;

requires qw(_get_total_results _get_entities);

has 'default_page_size' => (is => 'ro', isa => 'Int', lazy_build => 1);
sub _build_default_page_size { 25 }

has 'pageable' => ( is => 'ro', isa => 'Bool', lazy_build => 1 );
sub _build_pageable {
    my $self = shift;
    defined $self->rest->query->param('startIndex')
        or defined $self->rest->query->param('offset')
        or defined $self->rest->query->param('count')
        or defined $self->rest->query->param('limit');
}

has 'start_index' => ( is => 'ro', isa => 'Int', lazy_build => 1 );
sub _build_start_index {
    my $self = shift;
    my $index = $self->rest->query->param('startIndex');
    $index = $self->rest->query->param('offset') unless defined $index;
    $index = 0 unless defined $index;
    $index = 0 unless $index =~ m/^\d+$/;
    return $index;
}

has 'items_per_page' => ( is => 'ro', isa => 'Maybe[Int]', lazy_build => 1 );
sub _build_items_per_page {
    my $self = shift;
    return unless $self->pageable;
    my $count = $self->rest->query->param('count');
    $count = $self->rest->query->param('limit') unless defined $count;
    $count = $self->default_page_size
        unless defined $count and $count =~ m/^\d+$/;
    return $count > max_per_page ? max_per_page : $count;
}

has 'reverse' => ( is => 'ro', isa => 'Bool', lazy_build => 1 );
sub _build_reverse {
    my $self = shift;
    $self->rest->query->param('reverse');
}

has 'order' => ( is => 'ro', isa => 'Maybe[Str]', lazy_build => 1 );
sub _build_order {
    my $self = shift;
    my $order = $self->rest->query->param('order');
    return undef unless $order && $order =~ m/^\w+$/;
    return $order;
}

sub get_resource {
    my ($self, $rest, $content_type) = @_;

    Socialtext::Timer->Continue('_get_entities');
    my $results = $self->_get_entities($rest, $content_type);
    Socialtext::Timer->Pause('_get_entities');

    Socialtext::Timer->Continue('_entity_hash_map');
    @$results = map { $self->_entity_hash($_) } @$results;
    Socialtext::Timer->Pause('_entity_hash_map');

    my $total_results;
    unless ($self->rest->query->param('skipTotalResults')) {
        $total_results = $self->_get_total_results;
        $total_results = $total_results+0 if defined $total_results;
    }

    if ($self->pageable and $content_type eq 'application/json') {
        if (defined $self->rest->query->param('startIndex')) {
            # Emit OpenSocial-compatible payload
            return {
                startIndex => $self->start_index+0,
                itemsPerPage => $self->items_per_page+0,
                entry => $results,
                defined $total_results ? (totalResults => $total_results) : (),
            }
        }
        else {
            if (@$results > $self->items_per_page) {
                $#$results = $self->items_per_page - 1;
            }
            return $results;
        }
    }
    else {
        return $results;
    }
}

sub _entity_hash {
    my ($self, $item) = @_;
    return $item;
}

=head1 NAME

Socialtext::Rest::Pageable - TBD

=head1 SYNOPSIS

TBD

=head1 DESCRIPTION

TBD

=cut


1;
