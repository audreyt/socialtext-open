package Socialtext::Rest::AccountWorkspaces;
# @COPYRIGHT@

use Moose;
use Socialtext::Account;
use Socialtext::Exceptions qw(param_error);
use Socialtext::Workspace::Permissions;
use Socialtext::MultiCursorFilter;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Collection';

sub permission { +{ GET => undef } }
sub collection_name { "Account Workspaces" }

sub _entities_for_query {
    my $self      = shift;
    my $rest      = $self->rest;
    my $user      = $rest->user;
    my $query     = $rest->query->param('q') || '';
    my $acct_name = $self->acct();
    my $account   = Socialtext::Account->Resolve($acct_name);
    my $set_filter = $rest->query->param('permission_set');

    return () unless $account;

    my $workspaces = $account->workspaces();

    if ($set_filter) {
        param_error "permission_set is invalid" if
            !Socialtext::Workspace::Permissions->SetNameIsValid($set_filter);

        $workspaces = Socialtext::MultiCursorFilter->new(
            cursor => $workspaces,
            filter => sub { shift->permissions->current_set_name eq $set_filter },
        );
    }

    my @workspaces = $workspaces->all();

    if ( $user->is_business_admin && $query eq 'all' ) {
        return @workspaces;
    }

    return grep { $_->has_user( $user ) } @workspaces;
}

sub _entity_hash {
    my $self      = shift;
    my $workspace = shift;

    return +{
        name  => $workspace->name,
        uri   => '/data/workspaces/' . $workspace->name,
        title => $workspace->title,
        modified_time => $workspace->creation_datetime,
        id => $workspace->workspace_id,
        permission_set => $workspace->permissions->current_set_name,
        is_all_users_workspace => $workspace->is_all_users_workspace ? 1 : 0,
    };
}

__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
1;

=head1 NAME

Socialtext::Rest::AccountWorkspaces - Workspaces in an account.

=head1 SYNOPSIS

    GET /data/accounts/:acct/workspaces

=head1 DESCRIPTION

Every socialtext account has a collection of zero or more workspaces
associated with it. At the URI above, it is possible to view a list of those
workspaces.

=cut
