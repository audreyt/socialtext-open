package Socialtext::Rest::GroupDriverGroups;
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

sub collection_name { 'Groups Driver Groups' }

sub _entities_for_query {
    my $self = shift;
    my $user = $self->rest->user();
    return $self->unauthorized unless $user->is_business_admin;

    my $factory = Socialtext::Group->Factory(driver_key => $self->driver_key);
    unless ($factory) {
        $self->rest->header(-status => HTTP_404_Not_Found);
        return;
    }
    return $factory->Available( all => 1 );
}

sub _entity_hash {
    my $self  = shift;
    my $group = shift;
    return $group;
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

Socialtext::Rest::GroupDriverGroups - List groups in a driver on the system.

=head1 SYNOPSIS

    GET /data/group_drivers/:driver/groups

=head1 DESCRIPTION

View the list of groups present in a given driver.  Only visible by a Business
Admin.

=cut
