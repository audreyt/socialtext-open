package Socialtext::Job::Invite;
# @COPYRIGHT@
use Socialtext::User;
use Socialtext::Account;
use Socialtext::Workspace;
use Socialtext::Group;
use Socialtext::AccountInvitation;
use Moose;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

has sender => (
    is => 'ro', isa => 'Socialtext::User',
    lazy_build => 1,
);
sub _build_sender {
    my $self = shift;
    return Socialtext::User->new( user_id => $self->arg->{sender_id} );
}

# Can be either an account, a workspace, or a group.
has object => (
    is => 'ro', isa => 'Socialtext::UserSetContainer',
    lazy_build => 1,
);
sub _build_object {
    my $self = shift;

    if (my $acct_id = $self->arg->{account_id}) {
        return Socialtext::Account->new(account_id => $acct_id);
    }
    elsif (my $ws_id = $self->arg->{workspace_id}) {
        return Socialtext::Workspace->new(workspace_id => $ws_id);
    }
    elsif (my $group_id = $self->arg->{group_id}) {
        return Socialtext::Group->GetGroup(group_id => $group_id);
    }

    return undef;
}

sub do_work {
    my $self = shift;

    my $object = $self->object;
    my $user   = $self->user;

    unless ( $object->has_user($user) ) {
        my $msg = "User " . $user->user_id . " is not in object";
        return $self->failed($msg, 255);
    }

    eval {
        my $invitation = $object->invite(
            from_user   => $self->sender,
            extra_text  => $self->arg->{extra_text},
            template    => $self->arg->{template} || 'st',
        );

        # {bz: 3357} - Somehow the constructor does not set layout of $invitation
        # properly; manually re-assign the fields until we get a cycle to investigate.
        #
        # We know that if "use Socialtext::AccountInvitation;" is put to the
        # beginning of ceqlotron, then the constructor works properly; but the
        # actual root cause is yet to be found.
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

Socialtext::Job::Invite - Send an invite to a user for a user set container.

=head1 SYNOPSIS

    use Socialtext::JobCreator;

    Socialtext::JobCreator->insert(
        'Socialtext::Job::Invite',
        {
            account_id => 1,
            user_id    => 13,
            sender_id  => 169,
        },
    );

=head1 DESCRIPTION

Schedule a job to be run by TheCeq which will send an e-mail message to the
User to indicate to them that they have been invited to the given Account.

=cut
