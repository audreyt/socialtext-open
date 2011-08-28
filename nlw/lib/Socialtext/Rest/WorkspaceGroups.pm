package Socialtext::Rest::WorkspaceGroups;
# @COPYRIGHT@
use Moose;
use Socialtext::Workspace;
use Socialtext::HTTP ':codes';
use Socialtext::JSON qw/decode_json/;
use Socialtext::Permission qw/ST_ADMIN_WORKSPACE_PERM ST_READ_PERM/;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Collection';
with 'Socialtext::Rest::Pageable';
with 'Socialtext::Rest::WorkspaceRole';

has 'workspace' => (is => 'rw', isa => 'Maybe[Object]', lazy_build => 1);

sub permission { +{ GET => undef, POST => undef } }
sub allowed_methods { 'POST', 'GET' }
sub collection_name { "Workspace Groups" }

sub if_authorized {
    my $self = shift;
    my $method = shift;
    my $call = shift;

    return $self->not_authorized
       if $self->rest->user->is_guest();

    my $permission = ($method eq 'GET')
        ? ST_READ_PERM
        : ST_ADMIN_WORKSPACE_PERM;

    my $has_perm = $self->workspace->permissions->user_can(
        user => $self->rest->user,
        permission => $permission,
    );

    unless ($has_perm or $self->rest->user->is_business_admin) {
        return $self->not_authorized;
    }

    return $self->$call(@_);
}

sub _get_total_results {
    my $self = shift;
    return $self->workspace->total_group_roles(
        include_aggregates => 1,
        limit => $self->items_per_page,
        offset => $self->start_index,
        direct => 1,
    );
}

sub _get_entities {
    my $self = shift;
    my $rest = shift;

    my $roles = $self->workspace->sorted_group_roles(
        include_aggregates => 1,
        limit => $self->items_per_page,
        offset => $self->start_index,
        direct => 1,
        order_by => $self->order || 'driver_group_name',
        sort_order => $self->reverse ? 'DESC' : 'ASC',
    );
    $roles->apply(sub {
        my $info = shift;
        my $group = Socialtext::Group->GetGroup(group_id => $info->{group_id});
        my $role = Socialtext::Role->new(role_id => $info->{role_id});
        return {
            permission_set => $group->permission_set,
            group_id => $group->group_id,
            name => $group->driver_group_name,
            user_count => $info->{user_count},
            workspace_count => $info->{workspace_count},
            primary_account_name => $group->primary_account->name,
            primary_account_id => $group->primary_account->account_id,
            creation_date => $group->creation_datetime->ymd,
            created_by_user_id => $group->created_by_user_id,
            created_by_username => $group->creator->guess_real_name,
            role_id => $info->{role_id},
            role_name => $role->name,
            uri => "/data/group/$info->{group_id}"
        };
    });
    my @groups = $roles->all;
    return \@groups;
}

sub _entity_hash { return $_[1] }

sub _build_workspace {
    my $self = shift;

    return Socialtext::Workspace->new( 
        name => Socialtext::String::uri_unescape( $self->acct ),
    );
}

sub POST_json {
    my $self = shift;
    my $rest = shift;
    my $data = decode_json( $rest->getContent() );

    unless ($self->user_can('is_business_admin')) {
        $rest->header(
            -status => HTTP_401_Unauthorized,
        );
        return '';
    }

    my $workspace = $self->workspace;
    unless ( defined $workspace ) {
        $rest->header(
            -status => HTTP_404_Not_Found,
        );
        return '';
    }

    unless ( defined $data and ref($data) eq 'HASH' ) {
        $rest->header(
            -status => HTTP_400_Bad_Request,
        );
        return '';
    }

    my $group_id = $data->{group_id};
    unless ($group_id) {
        $rest->header(
            -status => HTTP_400_Bad_Request,
        );
        return "Missing a group_id";
    }

    my $group = Socialtext::Group->GetGroup(group_id => $group_id);
    unless ($group) {
        $rest->header(
            -status => HTTP_400_Bad_Request,
        );
        return "Group_id ($group_id) is not a valid group";
    }

    if ($group->permission_set eq 'self-join') {
        $rest->header(-status => HTTP_400_Bad_Request);
        return "cannot add self-join group to workspace";
    }

    if ($group->permission_set eq 'private'
        && $workspace->permissions->current_set_name ne 'member-only'
    ) {
        $rest->header(-status => HTTP_400_Bad_Request);
        return "cannot add private group to public workspace";
    }

    my $role;
    if (my $role_name = $data->{role_name}) {
        $role = Socialtext::Role->new(name => $role_name);
        unless ($role) {
            $rest->header(
                -status => HTTP_400_Bad_Request,
            );
            return "Role ($role_name) is not a valid role";
        }
    }

    if ($workspace->has_group($group)) {
        $rest->header(
            -status => HTTP_409_Conflict,
        );
        return "Group_id ($group_id) is already in this workspace.";
    }

    $workspace->add_group(
        group => $group,
        ($role ? (role => $role) : ()),
    );

    $rest->header(-status => HTTP_201_Created);
    return '';
}

sub PUT_json {
    my $self = shift;

    $self->can_admin(sub {
        $self->modify_roles(sub {
            my $ws = $self->workspace;
            my $updates = decode_json($self->rest->getContent());

            for my $update (@$updates) {
                my $group_id  = $update->{group_id};
                my $role_name = $update->{role_name};

                my $role   = Socialtext::Role->new(name => $role_name);
                my $target = eval {
                    Socialtext::Group->GetGroup(group_id => $group_id)
                };

                die data_validation_error(errors => ["bad group_id or role"])
                    unless $target and $role;

                my $exists = $ws->has_group($target, {direct => 1});
                die data_validation_error(errors => ["group not in workspace"])
                    unless $exists;

                $ws->assign_role_to_group(
                    actor => $self->rest->user,
                    group => $target,
                    role  => $role,
                );
            }
        });
    });
}

__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
1;

=head1 NAME

Socialtext::Rest::WorkspaceGroups - Groups in a workspace.

=head1 SYNOPSIS

    GET /data/workspaces/:ws/groups

    POST /data/workspaces/:ws/groups as application/json
    - Body should be a JSON hash containing a group_id and optionally a role_name.

=head1 DESCRIPTION

Every Socialtext workspace has a collection of zero or more groups
associated with it. At the URI above, it is possible to view a list of those
groups.

=cut
