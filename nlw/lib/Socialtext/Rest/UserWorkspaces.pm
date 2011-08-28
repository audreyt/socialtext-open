package Socialtext::Rest::UserWorkspaces;
# @COPYRIGHT@
use Moose;
extends 'Socialtext::Rest::Collection';
use Socialtext::User;
use Socialtext::Exceptions qw(not_found auth_error param_error);
use Socialtext::MultiCursorFilter;
use Socialtext::Permission;
use Socialtext::Timer 'time_scope';
use Socialtext::Workspace;
use Socialtext::Workspace::Permissions;
use namespace::clean -except => 'meta';

with 'Socialtext::Rest::Pageable';

sub permission { +{} }
sub collection_name { 'User Workspaces' }

sub ensure_actor_can_view {
    my $self    = shift;
    my $subject = shift;
    my $actor   = $self->rest->user();

    not_found unless $subject;

    my $is_subject = $actor->user_id == $subject->user_id;
        auth_error unless $is_subject || $actor->is_business_admin;
}

sub _get_total_results {
    my $self    = shift;
    my $subject = eval {Socialtext::User->Resolve($self->username) };
    $self->ensure_actor_can_view($subject);

    my $filter = $self->rest->query->param('permission_set');
    unless ($filter) {
        return $subject->workspace_count(
            direct => 1,
            $self->_permission_filter(),
        );
    }

    param_error "permission_set is invalid" if
        !Socialtext::Workspace::Permissions->SetNameIsValid($filter);

    my $workspaces = Socialtext::MultiCursorFilter->new(
        cursor => $subject->workspaces(
            direct => 1,
            $self->_permission_filter(),
        ),
        filter => sub { shift->permissions->current_set_name eq $filter },
    );

    return $workspaces->count();
}

sub _permission_filter {
    my $self = shift;
    if (my $perm_name = $self->rest->query->param('permission')) {
        my $perm = Socialtext::Permission->new(name => $perm_name);
        param_error unless $perm;

        return (permission_id => $perm->permission_id);
    }

    return ();
}

sub _get_entities {
    my $self    = shift;
    my $subject = eval {Socialtext::User->Resolve($self->username) };

    $self->ensure_actor_can_view($subject);
 
    my %limit_and_offset = (
        limit => $self->items_per_page,
        offset => $self->start_index,
    );

    my $filter = $self->rest->query->param('permission_set');
    if ($filter) {
        param_error "permission_set is invalid" if
            !Socialtext::Workspace::Permissions->SetNameIsValid($filter);
        %limit_and_offset = ();
    }

    my $t = $filter
        ? time_scope('mcfiltered_user_workspaces_results')
        : time_scope('user_workspaces_results');

    my $workspaces = $subject->workspaces(
        order_by => $self->order || 'name',
        sort_order => $self->reverse ? 'DESC' : 'ASC',
        direct => 1,
        %limit_and_offset,
        $self->_permission_filter(),
    );

    if ($filter) {
        $workspaces = Socialtext::MultiCursorFilter->new(
            cursor => $workspaces,
            limit => $self->items_per_page,
            offset => $self->start_index,
            filter => sub { shift->{permission_set} eq $filter },
        );
    }

    $workspaces->apply(sub {
        my $item = shift;
        my $ws   = Socialtext::Workspace->new(workspace_id => $item->{workspace_id});
        return {
            workspace_id => $ws->workspace_id,
            name => $ws->name,
            title => $ws->title,
            uri => '/data/workspaces/' . $ws->name,
            account_id => $ws->account->account_id,
            account_name => $ws->account->name,
            created_by_user_id => $ws->creator->user_id,
            created_by_username => $ws->creator->username,
            create_datetime => $ws->creation_datetime_object->ymd,
            user_count => $ws->user_count,
            group_count => $ws->group_count,
            default => $ws->is_default ? 1 : 0,
            permission_set => $ws->permissions->current_set_name,
            is_all_users_workspace => $ws->is_all_users_workspace ? 1 : 0,

            # for backwards compatibility
            id => $ws->workspace_id,
            modified_time => $ws->creation_datetime,
        };
    });

    my @workspaces = $workspaces->all();
    return \@workspaces;
}

sub _entity_hash { return $_[1] }

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::UserWorkspaces

=head1 SYNOPSIS

    GET /data/users/:username/workspaces
    GET /data/users/:username/workspaces?permisison=read

=head1 DESCRIPTION

View the workspaces that a user has a role in.

=cut
