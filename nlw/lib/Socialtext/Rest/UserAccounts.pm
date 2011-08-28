package Socialtext::Rest::UserAccounts;
# @COPYRIGHT@
use Moose;
use Socialtext::User;
use Socialtext::HTTP qw(:codes);
use Socialtext::l10n;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Collection';
with 'Socialtext::Rest::Pageable';

# We punt to the permission handling stuff below.
sub permission { +{ GET => undef } }

has 'user' => (
    is => 'ro', isa => 'Socialtext::User', lazy_build => 1,
);
sub _build_user {
    my $self = shift;
    my $user = eval { Socialtext::User->Resolve($self->username) };
    die Socialtext::Exception::NotFound->new() unless $user;
    return $user;
}

sub if_authorized {
    my $self = shift;
    my $method = shift;
    my $call = shift;

    if ($method eq 'POST') {
        return $self->not_authorized
            unless $self->rest->user->is_business_admin;
    }
    elsif ($method eq 'GET') {
        return $self->not_authorized
            unless $self->rest->user->is_business_admin
                or $self->rest->user->user_id == $self->user->user_id;
    }
    else {
        return $self->bad_method;
    }

    return $self->$call(@_);
}

has 'accounts' => (
    is => 'ro', isa => 'ArrayRef',
    lazy_build => 1,
);
sub _build_accounts {
    my $self = shift;
    my $rest   = $self->rest;

    my @accounts;
    my %account_ids;

    my $user_accounts = $self->user->accounts;
    my $pri_acct = $self->user->primary_account_id;
    for my $acct (@$user_accounts) {
        my $acct_id = $acct->account_id;
        my $acct_hash = {
            account_id => $acct_id,
            account_name => $acct->name,
            is_primary => ($acct_id == $pri_acct ? 1 : 0),
        };
        push @accounts, $acct_hash;
        $account_ids{$acct_id} = {
            hash => $acct_hash,
            obj  => $acct,
        };
    }

    my $user_wksps = $self->user->workspaces;
    while (my $wksp = $user_wksps->next) {
        my $acct_id = $wksp->account_id;
        my $wksp_hash = {
            name => $wksp->name,
            workspace_id => $wksp->workspace_id,
        };

        my $acct_hash = $account_ids{$acct_id};
        next if $wksp->has_account($acct_hash->{obj});

        push @{ $acct_hash->{hash}{via_workspace} }, $wksp_hash;
    }

    eval { 
        my $user_groups = $self->user->groups;
        while (my $grp = $user_groups->next) {
            my $group_hash = {
                name => $grp->driver_group_name,
                group_id => $grp->group_id,
            };
            my $grp_accts = $grp->accounts;
            while (my $acct = $grp_accts->next) {
                my $acct_id = $acct->account_id;

                my $acct_hash = $account_ids{$acct_id}{hash};
                push @{ $acct_hash->{via_group} }, $group_hash;
            }
        }
    };
    if ($@) {
        warn "ERROR: $@";
    }

    return \@accounts;
}

sub _get_entities {
    my $self = shift;
    my $order = $self->rest->query->param('order') || 'account_id';
    my $accounts = $self->accounts;
    my @sorted;
    if ($self->reverse) {
        @sorted = $order eq 'account_id'
            ? sort { $b->{$order} <=> $a->{$order} } @$accounts
            : reverse lsort_by $order => @$accounts;
    }
    else {
        @sorted = $order eq 'account_id'
            ? sort { $a->{$order} <=> $b->{$order} } @$accounts
            : lsort_by $order => @$accounts;
    }
    return [
        $self->pageable
            ? splice(@sorted, $self->start_index || 0, $self->items_per_page)
            : @sorted
    ];
};

sub _get_total_results {
    my $self = shift;
    my $accounts = $self->accounts;
    return scalar @$accounts;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::UserAccounts - List the accounts a user belongs to & why

=head1 SYNOPSIS

    GET /data/users/:username/accounts

=head1 DESCRIPTION

View the list of accounts a user is a member of.  Caller can only see groups
they created or are also a member of.  Business admins can see all groups.

=cut
