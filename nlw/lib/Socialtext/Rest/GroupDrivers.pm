package Socialtext::Rest::GroupDrivers;
# @COPYRIGHT@
use Moose;
extends 'Socialtext::Rest::Collection';
use Socialtext::Group;
use Socialtext::HTTP ':codes';
use Socialtext::JSON qw/decode_json/;
use namespace::clean -except => 'meta';

# Anybody can see these, since they are just the list of workspaces the user
# has 'selected'.
sub permission { +{} }

sub collection_name { 'Groups Drivers' }

sub _entities_for_query {
    my $self = shift;
    my $user = $self->rest->user();
    return $self->unauthorized unless $user->is_business_admin;

    my @drivers;
    for my $factory_id (Socialtext::Group->Drivers()) {
        my $factory = eval {
            Socialtext::Group->Factory( driver_key => $factory_id );
        };
        push @drivers, $factory if $factory;
    }
    return @drivers;
}

sub _entity_hash {
    my $self  = shift;
    my $driver = shift;
    return {
        driver_key => $driver->driver_key,
    };
}

override extra_headers => sub {
    my $self = shift;
    my $resource = shift;

    return (
        '-cache-control' => 'private',
    );
};

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::GroupDrivers - List group drivers on the system.

=head1 SYNOPSIS

    GET /data/group_drivers

=head1 DESCRIPTION

View the list of Group Drivers.  Only visible by a Business Admin.

=cut
