package Socialtext::Rest::Group::Workspaces;
# @COPYRIGHT@
use Moose;
use Socialtext::Exceptions;
use Socialtext::Group;
use Socialtext::Permission qw/ST_READ_PERM ST_ADMIN_WORKSPACE_PERM
                              ST_ADMIN_PERM/;
use Socialtext::HTTP ':codes';
use Socialtext::JSON;
use Socialtext::SQL ':txn';
use Socialtext::l10n;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Collection';

sub permission { +{} }
sub collection_name { 'Group Workspaces' }

sub _entities_for_query {
    my $self = shift;
    my $group_id = $self->group_id;
    my $user = $self->rest->user;

    my $exclude_auw = $self->rest->query->param('exclude_auw_paths') || 0;

    my $group = Socialtext::Group->GetGroup(group_id => $group_id)
        or die Socialtext::Exception->NotFound->new();

    my $can_read = $group->user_can(
        user       => $user,
        permission => ST_READ_PERM,
    );
    die Socialtext::Exception::Auth->new()
       unless $user->is_business_admin
           || $group->creator->user_id == $user->user_id
           || $can_read;

    return lsort_by title =>
       $group->workspaces(exclude_auw_paths => $exclude_auw)->all();
}

sub _entity_hash {
    my $self      = shift;
    my $workspace = shift;

    return +{
        name          => $workspace->name,
        uri           => '/data/workspaces/' . $workspace->name,
        title         => $workspace->title,
        modified_time => $workspace->creation_datetime,
        id            => $workspace->workspace_id,
        workspace_id  => $workspace->workspace_id,
        default       => $workspace->is_default ? 1 : 0,
        is_all_users_workspace => $workspace->is_all_users_workspace ? 1 : 0,
    };
}

sub POST_json {
    my $self = shift;
    my $rest = shift;
    my $user = $rest->user;

    # I've written this find group/check perms code too many times, this
    # should be factored out into a RestGroups role.
    my $group = Socialtext::Group->GetGroup(group_id => $self->group_id);
    unless ($group) {
        $rest->header(-status => HTTP_404_Not_Found);
        return "not found";
    }

    my $perm = $group->user_can(user => $user, permission => ST_ADMIN_PERM);
    unless ($perm || $user->is_business_admin) {
        $rest->header(-status => HTTP_401_Unauthorized);
        return "user not authorized";
    }

    my $json = eval { decode_json($rest->getContent()) };
    $json = (ref($json) eq 'HASH') ? [$json] : $json;

    unless (ref($json) eq 'ARRAY') {
        $rest->header(-status => HTTP_400_Bad_Request);
        return "bad json";
    }

    eval { sql_txn {
        foreach my $meta (@$json) {
            $self->_add_group(
                $group,
                $meta->{workspace_id},
                $meta->{role} || 'member'
            );
        }
    }};
    if (my $e = $@) {
        my ($status, $message);

        if (my $err = ref($e)) {
            if ($err eq 'Socialtext::Exception::Auth') {
                $status = HTTP_401_Unauthorized;
            }
            elsif ($err eq 'Socialtext::Exception::Conflict') {
                $status = HTTP_409_Conflict;
            }
            else {
                $status = HTTP_400_Bad_Request;
            }

            $message = $e->message;
        }
        else {
            $status  = HTTP_400_Bad_Request;
            $message = '';
        }

        $rest->header(-status => $status);
        return "$message";
    }

    $rest->header(-status => HTTP_201_Created);
    return encode_json($group->to_hash);
}

sub _add_group {
    my $self         = shift;
    my $group        = shift;
    my $workspace_id = shift;
    my $role_name    = shift;

    my $user = $self->rest->user;

    my $ws = Socialtext::Workspace->new(workspace_id => $workspace_id)
        or die Socialtext::Exception::Params->new("no such workspace");

    my $perm = $ws->permissions->user_can(
        user => $user,
        permission => ST_ADMIN_WORKSPACE_PERM,
    );
    die Socialtext::Exception::Auth->new("user cannot admin workspace")
        unless $perm || $user->is_business_admin;

    my $role = Socialtext::Role->new( name => $role_name)
        or die Socialtext::Exception::Params->new("no such role");

    my $current = $ws->role_for_group($group, {direct => 1})
       and die Socialtext::Exception::Conflict->new(
           "group already in workspace"
       );

    $ws->add_group(group => $group, role => $role, actor => $user);
}

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::Group::Workspaces - Resource handler for the Workspaces a
Group is a member of.

=head1 SYNOPSIS

    GET /data/groups/:group_id/workspaces
    POST /data/groups/:group_id/workspaces

=head1 DESCRIPTION

View the details for a list of Workspaces that a Group is a member of.

OR add this group to workspaces (will fail if already a member of one of those workspaces). (Undocumented API)

=cut
