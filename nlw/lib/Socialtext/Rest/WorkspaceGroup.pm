package Socialtext::Rest::WorkspaceGroup;
# @COPYRIGHT@

use Moose;
use Socialtext::HTTP ':codes';
use Socialtext::Group;
use Socialtext::Workspace;
use Socialtext::Permission qw(ST_ADMIN_PERM);
use Socialtext::Exceptions qw(conflict rethrow_exception);
use Socialtext::SQL qw(get_dbh :txn);
use Socialtext::JSON qw/decode_json/;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Entity';
with 'Socialtext::Rest::WorkspaceRole';

sub allowed_methods { 'DELETE' };

has 'target_group' => (
    is => 'ro', isa => 'Maybe[Socialtext::Group]', lazy_build => 1,
);

sub _build_target_group {
    my $self = shift;
    my $group_id = $self->group_id;
    my $group = eval{ Socialtext::Group->GetGroup(group_id => $group_id) };
    return $group;
}

around 'can_admin' => sub {
    my $orig = shift;
    my $self = shift;

    my $ws    = $self->workspace;
    my $group = $self->target_group;
    my $actor = $self->rest->user;

    return $self->no_workspace() unless $ws;

    return $self->http_404($self->rest, 'group not found')
        unless $group;

    unless ($ws->has_group($group)) {
        return $self->http_404(
            $self->rest,
            $group->driver_group_name . " is not a member of " . $ws->name
        );
    }

    return $self->$orig(@_);
};

# Remove a Group from a Workspace
sub DELETE {
    my ($self, $rest) = @_;
    $self->can_admin(sub {
        # Remove the Group from the WS
        $self->modify_roles(sub {
            $self->workspace->remove_group( group => $self->target_group );
        });
    });
}

# Remove a Group from a Workspace
sub PUT {
    my ($self, $rest) = @_;
    $self->can_admin(sub {
        my $content = $rest->getContent();
        $self->modify_roles(sub {
            my $object = decode_json( $content );
            die 'role parameter is required' unless $object->{role_name};

            my $role = Socialtext::Role->new(name => $object->{role_name});
            die "role '$object->{role_name}' doesn't exist" unless $role;

            $self->workspace->assign_role_to_group(
                group => $self->target_group, role => $role
            );
        });
    });
}

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::WorkspaceGroups - Groups in a Workspace

=head1 SYNOPSIS

  DELETE /data/workspaces/:ws_name/groups/:group_id

=head1 DESCRIPTION

Every Socialtext Workspace has a collection of zero or more Groups associated
with it.  At the URIs above, it is possible to remove a Group from a
Workspace.

=cut
