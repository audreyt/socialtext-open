package Socialtext::Rest::UserSharedGroups;
# @COPYRIGHT@
use Moose;
use Socialtext::User;
use Socialtext::HTTP qw(:codes);
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Collection';

# We punt to the permission handling stuff below.
sub permission { +{ GET => undef } }
sub entity_name { "User " . $_[0]->username . " groups" }

# Same logic as UserSharedAccounts - refactor later?
sub authorized_to_view {
    my ($self, $user) = @_;
    my $acting_user = $self->rest->user;
    return $user
        && (   $acting_user->is_business_admin()
            || ( $user->username eq $acting_user->username )
        );
}

sub _entities_for_query {
    my $self = shift;
    my $user = Socialtext::User->new( username => $self->username );
    my $other = Socialtext::User->new( username => $self->otheruser );

    unless ($self->authorized_to_view($user)) {
        $self->rest->header( -status => HTTP_401_Unauthorized );
        return ();
    }

    return $user->shared_groups($other);
}

sub _entity_hash {
    my ($self, $group) = @_;
    return $group->to_hash(
        show_members => $self->{_show_members},
        show_account_ids => 1,
        plugins => 1
    );
}

around get_resource => sub {
    my $orig = shift;
    my $self = shift;

    $self->{_show_members} = $self->rest->query->param('show_members') ? 1 : 0;
    return $orig->($self, @_);
};

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::UserSharedGroups - List the groups a user belongs to

=head1 SYNOPSIS

    GET /data/users/:username/shared_groups/:otheruser

=head1 DESCRIPTION

View the list of groups a user shares with another user.

Caller can only see groups they share with other users.

Business admins can see every user's shared groups with other users.

=cut
