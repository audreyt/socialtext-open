package Socialtext::Job::WorkspaceInvite;
# @COPYRIGHT@
use Socialtext::User;
use Socialtext::Workspace;
use Socialtext::WorkspaceInvitation;
use Moose;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

has sender => (
    is => 'ro', isa => 'Socialtext::User',
    lazy_build => 1,
);

has workspace => (
    is => 'ro', isa => 'Socialtext::Workspace',
    lazy_build => 1,
);

sub _build_sender {
    my $self = shift;
    return Socialtext::User->new( user_id => $self->arg->{sender_id} );
}

sub _build_workspace {
    my $self = shift;
    return Socialtext::Workspace->new(
        workspace_id => $self->arg->{workspace_id},
    );
}

sub do_work {
    my $self = shift;

    my $workspace = $self->workspace;
    my $user    = $self->user;

    unless ( $workspace->has_user($user) ) {
        my $msg = "User " . $user->user_id 
            . " is not in workspace " . $workspace->workspace_id;
        return $self->failed($msg, 255);
    }

    eval {
        my $invitation = Socialtext::WorkspaceInvitation->new(
            workspace   => $workspace,
            from_user   => $self->sender,
            extra_text  => $self->arg->{extra_text},
        );

        # {bz: 3357} - Somehow the constructor does not set layout of $invitation
        # properly; manually re-assign the fields until we get a cycle to investigate.
        $invitation->{from_user} = $self->sender;
        $invitation->{extra_text} = $self->arg->{extra_text};

        $invitation->invite_notify($user);
    };
    if ( my $e = $@ ) {
        return $self->failed($e, 255);
    }

    $self->completed();
}

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::WorkspaceInvite - Send an invite to a user for a workspace.

=head1 SYNOPSIS

    use Socialtext::JobCreator;

    Socialtext::JobCreator->insert(
        'Socialtext::Job::WorkspaceInvite',
        {
            workspace_id => 1,
            user_id    => 13,
            sender_id  => 169,
        },
    );

=head1 DESCRIPTION

Schedule a job to be run by TheCeq which will send an e-mail message to the
User to indicate to them that they have been invited to the given Workspace.

=cut
