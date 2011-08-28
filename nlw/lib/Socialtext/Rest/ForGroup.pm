package Socialtext::Rest::ForGroup;
# @COPYRIGHT@
use Moose::Role;
use Socialtext::Group;
use Socialtext::Permission qw(ST_ADMIN_PERM);
use namespace::clean -except => 'meta';

has 'group' => (is => 'ro', isa => 'Maybe[Socialtext::Group]', lazy_build => 1);

has 'user_is_related' => (is => 'ro', isa => 'Bool', lazy_build => 1);
# see builder for definition of "visitor"
has 'user_is_visitor' => (is => 'ro', isa => 'Bool', lazy_build => 1);
has 'user_can_admin'  => (is => 'rw', isa => 'Bool', lazy_build => 1);

sub _build_group {
    my $self = shift;

    my $group_id = $self->group_id;
    my $group = Socialtext::Group->GetGroup(group_id => $group_id);
    return $group;
}

sub _build_user_is_related {
    my $self = shift;
    return $self->hub->authz->user_sets_share_an_account(
        $self->rest->user, $self->group);
}

sub _build_user_is_visitor {
    my $self = shift;
    my $visitor = $self->rest->user;
    my $group = $self->group;

    # visitor is a user related to this group by some account that is doing
    # some self-join related activity.

    return if $self->user_can_admin;
    return if $group->has_user($visitor);
    return if $group->permission_set ne 'self-join';
    return $self->user_is_related;
}

sub _build_user_can_admin {
    my $self = shift;
    my $user = $self->rest->user;
    return
        $user->is_technical_admin ||
        $user->is_business_admin ||
        $self->group->user_can(user => $user, permission => ST_ADMIN_PERM);
}

override 'not_authorized' => sub {
    my $self = shift;
    return super() if $self->rest->user->is_guest;
    return $self->user_is_related ? super() : $self->no_resource("group");
};

1;
__END__

=head1 NAME

Socialtext::Rest::GroupAttrs - Role for Group-y ReST handlers

=head1 SYNOPSIS

    with 'Socialtext::Rest::GroupAttrs';
    sub POST_whatever {
        my $self = shift;
        my $group = $self->group;
    
        if ($self->user_can_admin) {
            
        }
        elsif ($self->user_is_related) {
        }
        elsif ($self->user_is_visitor) {
        }
    }

=head1 DESCRIPTION

Utility methods and accessors for working with groups and their membership.

=cut
