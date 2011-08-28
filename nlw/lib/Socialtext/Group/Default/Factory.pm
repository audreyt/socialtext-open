package Socialtext::Group::Default::Factory;
# @COPYRIGHT@

use Moose;
use DateTime::Duration;
use namespace::clean -except => 'meta';

with qw(
    Socialtext::Group::Factory
);

has '+driver_key' => (
    default => 'Default',
);

# the Default store *is* updateable
sub can_update_store { 1 }

# the Default store is *not* cacheable
sub is_cacheable { 0 }

# the Default store doesn't need to look up Groups; they would've been found
# automatically when searching for "do I have a cached copy of this Group?"
sub _lookup_group {
    return;
}

# Unused in this factory.
sub _update_group_members {
    return;
}

# Returns list of available Groups
sub Available {
    my $self = shift;

    my $cursor = Socialtext::Group->All(
        driver_key         => $self->driver_key,
        order_by           => 'driver_group_name',
        sort_order         => 'ASC',
        include_aggregates => 1,
    );

    my @results;
    while (my $group = $cursor->next) {
        my $group_hash = {
            driver_key          => $group->driver_key,
            driver_group_name   => $group->driver_group_name,
            driver_unique_id    => $group->driver_unique_id,
            already_created     => 1,
            member_count        => $group->{user_count},
        };
        push @results, $group_hash;
    }
    return @results;
}

# creates a new Group, and stores it in the data store
sub Create {
    my ($self, $proto_group) = @_;

    # validate the data we were provided
    $proto_group->{driver_key}       = $self->driver_key();
    $proto_group->{group_id}         = $self->NewGroupId();
    $proto_group->{driver_unique_id} = $proto_group->{group_id};
    $self->ValidateAndCleanData(undef, $proto_group);

    # create a new record for this Group in the DB
    $self->NewGroupRecord($proto_group);

    # create a homunculus, and return that back to the caller
    return $self->NewGroupHomunculus($proto_group);
}

# updates a Group in the data store
sub Update {
    my ($self, $group, $proto_group) = @_;

    # validate the data we were provided
    $self->ValidateAndCleanData($group, $proto_group);

    # update the record for this Group in the DB
    my $primary_key = $group->primary_key();
    my $updates_ref = {
        %{$proto_group},
        %{$primary_key},
    };
    $self->UpdateGroupRecord($updates_ref);

    # merge the updates back into the Group object, skipping primary key
    # columns (which *aren't* updateable)
    my $to_merge = $self->FilterNonPrimaryKeyColumns($updates_ref);
    foreach my $attr (keys %{$to_merge}) {
        my $setter = $group->meta->find_attribute_by_name($attr);
        next unless $setter;
        $setter->set_value($group,$updates_ref->{$attr});
    }
    return $group;
}

# effectively infinite cache lifetime
sub _build_cache_lifetime {
    return DateTime::Duration->new(years => 1000);
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;

=head1 NAME

Socialtext::Group::Default::Factory - Internally sourced Group Factory

=head1 SYNOPSIS

  use Socialtext::Group;

  $factory = Socialtext::Group->Factory(driver_key => 'Default');

=head1 DESCRIPTION

C<Socialtext::Group::Default::Factory> provides an implementation of a Group
Factory that is sourced internally by Socialtext (e.g. Groups are defined by
the local DB).

Consumes the C<Socialtext::Group::Factory> Role.

=head1 METHODS

=over

=item B<$factory-E<gt>can_update_store()>

Returns true; the Default Group Factory B<is> updateable.

=item B<$factory-E<gt>is_cacheable()>

Returns false; the Default Group Factory is B<not> cacheable.

=item B<$factory-E<gt>Available(PARAMS)>

Returns a list of available Groups that have been created through this Factory
instance.

Implements C<Available()> as specified by C<Socialtext::Group::Factory>;
please refer to L<Socialtext::Group::Factory> for more information.

=item B<$factory-E<gt>Create(\%proto_group)>

Attempts to create a new Group based on the information provided in the
C<\%proto_group> hash-ref.

Implements C<Create()> as specified by C<Socialtext::Group::Factory>; please
refer to L<Socialtext::Group::Factory> for more information.

=item B<$factory-E<gt>Update($group, \%proto_group)>

Updates the C<$group> with the information in the provided C<\%proto_group>
hash-ref.

Implements C<Update()> as specified by C<Socialtext::Group::Factory>; please
refer to L<Socialtext::Group::Factory> for more information.

=back

=head1 AUTHOR

Socialtext, Inc.,  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc.,  All Rights Reserved.

=cut
