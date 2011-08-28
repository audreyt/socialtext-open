package Socialtext::Rest::Group::Users;
# @COPYRIGHT@
use Moose;
extends 'Socialtext::Rest::Groups';
use Socialtext::Group;
use Socialtext::HTTP ':codes';
use Socialtext::JSON qw/decode_json/;
use Socialtext::Permission qw/ST_READ_PERM ST_ADMIN_PERM/;
use Socialtext::User::Find::Container;
use Socialtext::User;
use Socialtext::JobCreator;
use Socialtext::l10n qw(loc);
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Users';
with 'Socialtext::Rest::ForGroup';

# Anybody can see these, since they are just the list of workspaces the user
# has 'selected'.
sub permission { +{} }
sub allowed_methods { 'GET' }
sub collection_name { 'Group users' }

sub if_authorized {
    my $self = shift;
    my $method = shift;
    my $call = shift;
    my $user = $self->rest->user;

    return $self->not_authorized if $user->is_guest;

    my $group = $self->group;
    return $self->no_resource('group') unless $self->group;

    # we should _never_ return here, but just in case.
    return $self->bad_method() unless $method eq 'GET';

    my $can_do = 
        $self->user_is_related ||
        $self->group->user_can(user => $user, permission => ST_READ_PERM) ||
        $self->user_can_admin;

    return $self->not_authorized() unless $can_do;

    return $self->$call(@_);
}

sub _build_user_find {
    my $self = shift;
    my $group = $self->group;
    my $viewer = $self->rest->user;
    my $q = $self->rest->query;

    my $show_pvt = $q->param('want_private_fields')
        && $viewer->is_business_admin;

    my %args = (
        viewer    => $viewer,
        limit     => $self->items_per_page,
        offset    => $self->start_index,
        container => $group,
        direct    => $q->param('direct') || undef,
        order     => $q->param('order') || '',
        reverse   => $q->param('reverse') || undef,
        show_pvt  => $show_pvt,
        # these may get changed by 'just_visiting':
        filter    => $q->param('filter') || undef,
        all       => $q->param('all') || undef,
        minimal   => $q->param('minimal') || 0,
    );

    # {bz: 4492}: Private group's user list is always accessible to business admins.
    if ($viewer->is_business_admin) {
        $args{all} = 1;
    }

    # {bz: 4510}: Admins should be regarded as visitors for non-"?all=1" cases,
    # otherwise they can't see members from related self-join groups.
    $self->user_can_admin(0) unless $args{all};

    $args{just_visiting} = 1 if $self->user_is_visitor;

    return Socialtext::User::Find::Container->new(\%args);
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::Group::Users - List users in a group

=head1 SYNOPSIS

    GET /data/groups/:group_id/users

POST action was moved to Socialtext::Rest::Group

=head1 DESCRIPTION

Retrieve the list of users in the specified group.

=cut
