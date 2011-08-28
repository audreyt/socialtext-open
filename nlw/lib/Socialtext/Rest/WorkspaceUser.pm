package Socialtext::Rest::WorkspaceUser;
# @COPYRIGHT@
use Moose;
use Socialtext::HTTP ':codes';
use Socialtext::User;
use Socialtext::Workspace;
use Socialtext::JSON qw(decode_json);
use Socialtext::Exceptions qw(conflict rethrow_exception);
use Socialtext::SQL qw(get_dbh :txn);
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Entity';
with 'Socialtext::Rest::WorkspaceRole';

sub allowed_methods {'DELETE, PUT'}

has 'target_user' => (
    is => 'ro', isa => 'Maybe[Socialtext::User]', lazy_build => 1,
);

sub _build_target_user {
    my $self = shift;
    my $user = eval { Socialtext::User->Resolve($self->username) };
    return $user;
}

around 'can_admin' => sub {
    my $orig = shift;
    my $self = shift;

    my $ws     = $self->workspace;
    my $target = $self->target_user;
    my $actor  = $self->rest->user;

    return $self->no_workspace() unless $ws;

    return $self->http_404($self->rest, 'user not found')
        unless $target;

    unless ($ws->has_user($target) ) {
        return $self->http_404(
            $self->rest,
            $target->username . " is not a member of " . $ws->name
        );
    }

    return $self->$orig(@_);
};

# Remove a user from a workspace
sub DELETE {
    my ( $self, $rest ) = @_;
    my $actor = $rest->user;
    my $target = $self->target_user;

    # Users can remove themselves regardless of whether they are an admin.
    if ($actor->user_id == $target->user_id) {
        return $self->modify_roles(sub {
            $self->workspace->remove_user( user => $self->target_user );
        });
    }

    $self->can_admin(sub {
        $self->modify_roles(sub {
            $self->workspace->remove_user( user => $self->target_user );
        });
    });
}

# Remove a user from a workspace
sub PUT {
    my ( $self, $rest ) = @_;
    $self->can_admin(sub {
        my $content = $rest->getContent();
        $self->modify_roles(sub {
            my $object = decode_json( $content );
            die 'role parameter is required' unless $object->{role_name};

            my $role = Socialtext::Role->new(name => $object->{role_name});
            die "role '$object->{role_name}' doesn't exist" unless $role;

            $self->workspace->assign_role_to_user(
                user => $self->target_user, role => $role
            );
        });
    });
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;
