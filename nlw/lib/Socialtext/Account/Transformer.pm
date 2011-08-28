package Socialtext::Account::Transformer;
# @COPYRIGHT@
use Moose;
use Socialtext::Account;
use Socialtext::Group;
use Socialtext::Role;
use Socialtext::User;
use Socialtext::JobCreator;
use Socialtext::Signal;
use Socialtext::SQL qw/sql_execute/;
use List::MoreUtils qw/any/;
use namespace::clean(except => 'meta');

has 'into_account_name' => (
    is => 'ro', isa => 'Str',
    required => 1,
);

has 'creator' => (
    is => 'ro', isa => 'Socialtext::User',
    default => sub { Socialtext::User->SystemUser() }
);

has 'into_account' => (
    is => 'ro', isa => 'Socialtext::Account',
    lazy_build => 1,
);
sub _build_into_account {
    my $self = shift;
    my $acct = Socialtext::Account->new(name => $self->into_account_name)
        or die "No account named '" . $self->into_account_name . "'\n";

    return $acct;
}

sub sanity_check {
    my $self = shift;
    my %p    = @_;

    my $account_name = delete $p{account_name};
    
    die "No account name argument passed\n" unless $account_name;

    die "Cannot transform into the 'Deleted' account\n"
        if $self->into_account->name eq 'Deleted';

    die "Account $account_name cannot be the same as into account\n"
        if $account_name eq $self->into_account_name;

    die "Cannot transform a system account\n"
        if any {$_ eq $account_name} Socialtext::Account->RequiredAccounts();

    my $acct = Socialtext::Account->new(name => $account_name)
        or die "No account named '$account_name'\n";

    die "Cannot transform the default account\n"
        if $acct->account_id == Socialtext::Account->Default->account_id;

    my $group = Socialtext::Group->GetGroup(
        driver_group_name  => $acct->name,
        created_by_user_id => Socialtext::User->SystemUser->user_id,
        primary_account_id => $self->into_account->account_id,
    );
    die "Group with name '$account_name' already exists\n" if $group;
}

# If you do choose to pass 'insane' here, you better know what you're doing.
# It's possible to really mess things up without a sanity check.
sub acct2group {
    my $self = shift;
    my %p = @_;

    my $account_name = delete $p{account_name};
    my $insane       = delete $p{insane};

    $self->sanity_check(account_name => $account_name)
        unless $insane;

    my $origin = Socialtext::Account->new(name => $account_name)
        or die "Cannot find account $account_name\n";

    my $group = Socialtext::Group->Create({
        driver_group_name  => $origin->name,
        created_by_user_id => Socialtext::User->SystemUser->user_id,
        primary_account_id => $self->into_account->account_id,
    });

    $self->_xfer_users_and_groups(
        from     => $origin,
        to_group => $group,
        origin   => $origin,
    );

    $self->_xfer_workspaces(
        from     => $origin,
        to_group => $group,
        origin   => $origin,
    );

    $self->_xfer_signals(
        from     => $origin,
        to_group => $group,
    );

    $origin->delete();

    return $group;
}

sub _xfer_users_and_groups {
    my $self     = shift;
    my %p        = @_;

    my $from       = delete $p{from};
    my $to_group   = delete $p{to_group};
    my $origin     = delete $p{origin};
    my $force_role = delete $p{force_role};

    for my $thing (qw/users groups/) {
        my $do = "_xfer_$thing";
        $self->$do(
            from     => $from,
            to_group => $to_group,
            origin   => $origin,
            $force_role ? (force_role => $force_role) : (),
        );
    }
}

sub _xfer_users {
    my $self     = shift;
    my %p        = @_;

    my $from       = delete $p{from};
    my $to_group   = delete $p{to_group};
    my $origin     = delete $p{origin};
    my $force_role = delete $p{force_role};

    my $users = $from->users(direct => 1);
    while (my $user = $users->next()) {
        if ($user->primary_account_id == $origin->account_id) {
            $user->primary_account($self->into_account);
        }

        # if user is already an admin in the group, let's not overwrite.
        my $current_role = $to_group->role_for_user($user, {direct => 1});
        next if $current_role && $current_role->name eq 'admin';

        my $role = ($force_role)
            ? $force_role : $from->role_for_user($user, { direct => 1 });
        $to_group->assign_role_to_user(user => $user, role => $role);
    }
}

sub _xfer_signals {
    my $self = shift;
    my %p    = @_;

    my $from     = delete $p{from};
    my $to_group = delete $p{to_group};

    # get a list of signal_id's that we're gonna update.
    my $result = sql_execute(q{
        SELECT signal_id
          FROM signal_user_set
         WHERE user_set_id = ?
    }, $from->user_set_id);
    my $sigs_to_index = $result->fetchall_arrayref({});

    # update the signals
    sql_execute(q{
        UPDATE signal_user_set
           SET user_set_id = ?
         WHERE user_set_id = ?
    }, $to_group->user_set_id, $from->user_set_id);

    # re-index the updated signals.
    my $creator = Socialtext::JobCreator->new();
    for my $proto ( @$sigs_to_index ) {
        $creator->index_signal($proto->{signal_id});
    }
}

sub _xfer_groups {
    my $self     = shift;
    my %p        = @_;

    my $from       = delete $p{from};
    my $to_group   = delete $p{to_group};
    my $origin     = delete $p{origin};
    my $force_role = delete $p{force_role};

    my $mc = $from->groups(direct => 1);
    while (my $group = $mc->next()) {
        if ($group->primary_account_id == $origin->account_id) {
            # we should never hit this; all remotely sourced groups are in the
            # default account, which we can't transform.
            die "Cannot move group" unless $group->can_update_store();

            $group->update_store({
                primary_account_id => $self->into_account->account_id});
        }

        # if user is already an admin in the group, let's not overwrite.
        my $current_role = $to_group->role_for_group($group, {direct => 1});
        next if $current_role && $current_role->name eq 'admin';

        my $role = ($force_role)
            ? $force_role : $from->role_for_group($group, { direct => 1 });

        $to_group->assign_role_to_group(group => $group, role => $role);
    }
}

sub _xfer_workspaces {
    my $self     = shift;
    my %p        = @_;

    my $from     = delete $p{from};
    my $to_group = delete $p{to_group};
    my $origin   = delete $p{origin};

    my $mc = Socialtext::Workspace->ByAccountId(
        account_id => $from->account_id);

    # we need to make sure that users/groups in these workspaces make it into
    # the new group.
    while (my $ws = $mc->next()) {
        if ($ws->is_all_users_workspace) {
            # Make this workspace not an all users workspace
            $ws->remove_account(account => $ws->account);
        }
        $ws->update(account_id => $self->into_account->account_id);
        $self->_xfer_users_and_groups(
            from       => $ws,
            to_group   => $to_group,
            origin     => $origin,
            force_role => Socialtext::Role->Member(),
        );
        $ws->add_group(group => $to_group);
    }
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;

=head1 NAME

Socialtext::Account::Transformer - Transform an Account into a Group

=head1 SYNOPSIS

    use Socialtext::Account::Transformer;

    my $transformer = Socialtext::Account::Transformer->new(
        into_account_name => $account_name,
    );

    eval { 
        $transformer->acct2group(account_name => $account1_name);
        $transformer->acct2group(account_name => $account2_name);
        $transformer->acct2group(account_name => $account3_name);
        ...
    };
    die $@ if $@;

    OR

    eval {
        $transformer->sanity_check(account_name => $another_account_name);
        $transformer->acct2group(
            account_name => $anouther_account_name,
            insane       => 1,
        );
    }

=head1 DESCRIPTION

Prior to the introduction of Groups in Socialtext, we used Accounts as
Group-like objects. This is a utility module that can be used to change one
such Account into a proper Group.

=head1 AUTHOR

Socialtext, Inc.,  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc.,  All Rights Reserved.

=cut
