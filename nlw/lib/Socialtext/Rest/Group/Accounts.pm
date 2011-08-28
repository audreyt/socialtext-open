package Socialtext::Rest::Group::Accounts;
# @COPYRIGHT@
use Moose;
use Socialtext::Group;
use Socialtext::Permission qw/ST_READ_PERM/;
use Socialtext::l10n;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Collection';
with 'Socialtext::Rest::Pageable';
with 'Socialtext::Rest::ForGroup';

# Anybody can see these, since they are just the list of workspaces the user
# has 'selected'.
sub permission { +{} }

sub collection_name { 'Group accounts' }

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

has accounts => (
    is => 'ro', isa => 'ArrayRef', lazy_build => 1
);

sub _build_accounts {
    my $self = shift;
    my @accounts = $self->group->accounts->all;
    return \@accounts;
}

sub _get_entities {
    my $self = shift;
    my $order = $self->rest->query->param('order') || 'name';
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
}

sub _get_total_results {
    my $self = shift;
    my $accounts = $self->accounts;
    return scalar @$accounts;
}

sub _entity_hash { 
    my ($self, $account) = @_;
    my $hash = $account->to_hash;
    $hash->{workspace_count} = $account->workspace_count;
    $hash->{user_count} = $account->user_count;
    return $hash;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::Group::Accounts - List accounts a group is in

=head1 SYNOPSIS

    GET /data/groups/:group_id/accounts

=head1 DESCRIPTION

View the list of accounts the specified group is in.

=cut
