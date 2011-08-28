package Socialtext::Rest::Group::User;
# @COPYRIGHT@
use Moose;
use Socialtext::HTTP ':codes';
use Socialtext::Group;
use Socialtext::User;
use Socialtext::Permission qw/ST_READ_PERM ST_ADMIN_PERM/;
use namespace::clean -except => 'meta';
extends 'Socialtext::Rest::Entity';

sub allowed_methods {'DELETE'}

sub DELETE {
    my $self = shift;
    my $rest = shift;

    unless ($rest->user->is_authenticated) {
        $rest->header( -status => HTTP_401_Unauthorized );
        return '';
    }

    my $group = Socialtext::Group->GetGroup( group_id => $self->group_id );
    my $user = eval {
        Socialtext::User->Resolve($self->user);
    };
    unless ($group and $user) {
        $rest->header( -status => HTTP_404_Not_Found );
        return 'Resource not found';
    }

    my $can_admin = $group->user_can(
        user => $rest->user, permission => ST_ADMIN_PERM,
    );
    unless ($can_admin or $self->user_can('is_business_admin')) {
        $self->rest->header(-status => HTTP_403_Forbidden);
        return '';
    }

    # Group is not Socialtext sourced, we don't control its membership.
    unless ( $group->can_update_store ) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return 'Group membership cannot be changed';
    }

    unless ( $group->has_user($user) ) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return 'User does not have a role in the Group';
    }

    $group->remove_user( user => $user );
    $rest->header( -status => HTTP_204_No_Content);
    return '';
}

sub HEAD {
    my $self = shift;
    my $rest = shift;

    # Check for auth
    unless ($rest->user->is_authenticated) {
        $rest->header( -status => HTTP_401_Unauthorized );
        return '';
    }

    # Check for permission
    my $group = Socialtext::Group->GetGroup(group_id => $self->group_id);
    my $can_read = $group->user_can(
        user => $rest->user, permission => ST_READ_PERM,
    );
    unless ($can_read or $self->user_can('is_business_admin')) {
        $self->rest->header(-status => HTTP_403_Forbidden);
        return '';
    }

    # Check for existence
    my $user  = Socialtext::User->Resolve($self->user);
    if ($group && $user && $group->has_user($user)) {
        $rest->header( -status => HTTP_204_No_Content);
        return '';
    }
    else {
        $rest->header( -status => HTTP_404_Not_Found );
        return 'Resource not found';
    }
}

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::Group::User - User in a Group

=head1 SYNOPSIS

    DELETE /data/groups/:group_id/users/:user

=head1 DESCRIPTION

Delete a User from a Group

=cut
