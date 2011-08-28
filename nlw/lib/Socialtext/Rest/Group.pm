package Socialtext::Rest::Group;
# @COPYRIGHT@
use Moose;
use Socialtext::HTTP ':codes';
use Socialtext::JSON;
use Socialtext::l10n qw(loc);
use Socialtext::Permission qw(ST_READ_PERM ST_ADMIN_PERM
                              ST_ADMIN_WORKSPACE_PERM);
use Socialtext::Exceptions ();
use Socialtext::Group;
use Socialtext::Rest::SetController;
use Socialtext::Upload;
use Try::Tiny;

use Socialtext::SQL 'sql_txn';
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Entity';
with 'Socialtext::Rest::ForGroup';

sub permission      { +{} }
sub allowed_methods {'GET, POST, PUT'}
sub entity_name     { "Group" }

sub if_authorized {
    my $self = shift;
    my $method = shift;
    my $call = shift;
    my $user = $self->rest->user;

    return $self->not_authorized if $user->is_guest;

    my $group = $self->group;
    return $self->no_resource("group") unless $group;

    my $permission = ($method eq 'GET') ? ST_READ_PERM : ST_ADMIN_PERM;

    my $can_do =
        $self->user_is_related || # MAYBE can (more checks per method)
        $group->user_can(user => $user, permission => $permission) ||
        $self->user_can_admin;

    return $self->not_authorized() unless $can_do;

    unless ($method eq 'GET' || $group->can_update_store) {
        return $self->http_400($self->rest,"This group cannot be modified.");
    }

    return try {
        $self->$call(@_);
    }
    catch {
        my $e = $_;
        my $err_status = HTTP_500_Internal_Server_Error;
        if (blessed($e)) {
            if ($e->isa('Socialtext::Exception::Auth')) {
                return $self->not_authorized();
            }
            elsif ($e->http_status) {
                $err_status = $e->http_status;
            }
            elsif ($e->isa("Socialtext::Exception::BadRequest") ||
                   $e->isa('Socialtext::Exception::DataValidation'))
            {
                $err_status = HTTP_400_Bad_Request;
            }
            elsif ($e->isa("Socialtext::Exception::Conflict")) {
                $err_status = HTTP_409_Conflict;
            }
            $e = $e->as_string;
        }
        my ($msg) = ($e =~ m{(.+?)(?:^Trace begun)? at \S+ line .*}ims);
        $msg ||= $e;
        $self->rest->header(-type => 'text/plain',
                            -status => $err_status);
        return $msg;
    };
}

sub controller {
    my $self = shift;
    return Socialtext::Rest::SetController->new(
        @_,
        actor     => $self->rest->user,
        container => $self->group,
    );
}

# users can voluntarily remove themselves from any group they are a member of
sub can_self_remove {
    my $self = shift;
    return !$self->user_can_admin;
}

sub can_self_administer {
    my $self = shift;
    return $self->group->permission_set eq 'self-join'
        && !$self->user_can_admin;
}

# GET /data/groups/:group_id
sub get_resource {
    my $self = shift;
    return $self->if_authorized('GET', sub {
        my $q = $self->rest->query;
        my $hash = $self->group->to_hash(
            show_members => $q->param('show_members') ? 1 : 0,
            show_admins  => $q->param('show_admins') ? 1 : 0,
        );

        if ($q->param('can_update_perms')) {
            $hash->{can_update_perms} = 
                $self->group->user_can_update_perms($self->rest->user);
        }
        return $hash;
    });
}

# PUT /data/groups/:group_id
sub PUT_json {
    my $self  = shift;
    my $rest  = $self->rest;
    my $group = $self->group;
    my $data  = $self->decoded_json_body();

    return $self->not_authorized() unless $self->user_can_admin;

    if (ref($data) ne 'HASH') {
        $rest->header( -status => HTTP_400_Bad_Request );
        return 'Content should be a JSON hash.';
    }
    unless ($data->{name}) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return 'Name is required';
    }

    my $set = $data->{permission_set};
    if ($set && $set ne $group->permission_set) {
        my $workspaces = $group->workspaces(exclude_auw_paths => 1);
        while (my $ws = $workspaces->next()) {

            my $can_admin_ws = $ws->permissions->user_can(
                user       => $rest->user,
                permission => ST_ADMIN_WORKSPACE_PERM,
            );

            Socialtext::Exception::DataValidation->throw( 
                message => loc("error.user-cannot-manage-associated-wikis-for-group"),
                http_status => HTTP_403_Forbidden

            ) unless $can_admin_ws;
        }
    }

    try {
        $group->update_store({
            driver_group_name => $data->{name},
            description => $data->{description} || "",
            permission_set => $set,
            $data->{account_id} ?
                (primary_account_id => $data->{account_id}) : (),
        });
    }
    catch {
        my $e = $_;
        if ($e =~ m/duplicate key value violates/) {
            Socialtext::Exception::Conflict->throw(message =>
                loc("error.updating-group-exists=name", $data->{name}));
        }
        elsif ($e =~ m/workspace has multiple groups/) {
            Socialtext::Exception::Conflict->throw(
                message => loc("error.updating-group=name", $e),
                http_status => HTTP_403_Forbidden
            );

        }
        elsif (blessed($e) && $e->isa('Socialtext::Exception::DataValidation')){ 
            $e->{http_status} = HTTP_400_Bad_Request;
            $e->rethrow;
        }
        die $e;
    };

    my $photo_id = $data->{photo_id};
    if ($photo_id) {
        try {
            my $blob;
            my $upload = Socialtext::Upload->Get(attachment_uuid => $photo_id);
            $upload->binary_contents(\$blob);
            $group->photo->set(\$blob);
            $upload->purge;
        }
        catch {
            warn "Error setting profile photo: $_";
        };
    }
    elsif (defined $photo_id) { # zero or empty-string
        $group->photo->purge;
    }

    $self->rest->header(-status => HTTP_202_Accepted);
    return '';
}

sub _check_one_admin {
    my $self = shift;
    Socialtext::Exception::Conflict->throw(
        message => loc("error.group-needs-at-least-one-admin")
    ) unless $self->group->has_at_least_one_admin;
}

sub _do_self_add {
    my ($self, $data) = @_;
    my $group = $self->group;
    my @errors;
    my $actor = $self->rest->user;
    my $mod = $data->[0];

    if (@$data != 1 ||
        ($mod->{user_id} && $mod->{user_id} != $actor->user_id) ||
        ($mod->{username} && $mod->{username} ne $actor->username))
    {
        push @errors, "can only self-add in self-join mode";
    }
    elsif ($mod->{role_name} ne 'member') {
        push @errors, "can only assign member role in self-join mode";
    }

    Socialtext::Exception::DataValidation->throw(
        http_status => HTTP_403_Forbidden,
        errors => \@errors
    )
        if @errors;

    $group->add_user(
        actor => $actor, user => $actor, role => Socialtext::Role->Member);

    $self->rest->header(-status => HTTP_202_Accepted);
    return '';
}

# POST /data/groups/:group_id/membership
# TODO: use the SetController like the other modification methods
sub POST_to_membership {
    my $self = shift;
    my $data  = $self->decoded_json_body;
    $data = (ref($data) eq 'HASH') ? [$data] : $data;

    my $group = $self->group;
    my @errors;
    my $actor = $self->rest->user;

    # let visitors add themselves.
    return $self->_do_self_add($data) if $self->can_self_administer;

    # otherwise reject related, non-admin, users.
    return $self->not_authorized() unless $self->user_can_admin;

    for (my $i=0; $i<=$#$data; $i++) {
        my $item = $data->[$i];
        unless ($item->{user_id} || $item->{username}) {
            push @errors, "Entry $i Missing user_id/username";
            next;
        }

        my $role = Socialtext::Role->new(name => $item->{role_name});
        unless ($role) {
            push @errors, "Entry $i Missing/invalid role '$item->{role_name}'";
            next;
        }

        my $user = Socialtext::User->new(
            $item->{user_id} ? (user_id => $item->{user_id})
                             : (username => $item->{username})
        );
        unless ($user) {
            push @errors, "Entry $i user not found";
            next;
        }

        unless ($group->has_user($user)) {
            push @errors, "Entry $i user id ".$user->user_id." is not a member";
            next;
        }

        $group->assign_role_to_user(
            actor => $actor, user => $user, role => $role);
    }

    Socialtext::Exception::DataValidation->throw(errors => \@errors) if @errors;

    $self->_check_one_admin;

    $self->rest->header(-status => HTTP_202_Accepted);
    return '';
}

# POST /data/groups/:group_id/trash
sub POST_to_trash {
    my $self = shift;

    my $data  = $self->decoded_json_body;
    $data = (ref($data) eq 'HASH') ? [$data] : $data;

    my $ctrl = $self->controller(
        scopes  => ['user'],
        actions => ['remove'],
    );

    # allow for self-removal on self-join groups
    if ($self->can_self_remove) {
        $ctrl->self_action_only(1);
    }
    else {
        # otherwise, user must be an admin to remove
        return $self->not_authorized() unless $self->user_can_admin;
    }

    $ctrl->alter_members($data);
    $self->_check_one_admin;

    $self->rest->header(-status => HTTP_204_No_Content);
    return '';
}

# Map to `POST /data/groups/:group_id/users
sub POST_to_users {
    my $self = shift;
    my $data = _parse_data($self->decoded_json_body);
    
    my $ctrl = $self->controller(
        scopes  => ['user'],
        actions => ['add'],
    );

    # allow for self-add on self-join groups
    if ($self->can_self_administer) {
        $ctrl->self_action_only(1);
        $ctrl->roles(['member']);
    }
    else {
        # otherwise, user must be an admin
        return $self->not_authorized() unless $self->user_can_admin;
    }

    $ctrl->hooks()->{post_user_add} = sub {$self->user_invite($data, @_)}
        if ($data->{send_message});

    $ctrl->alter_members($data->{users});

    $self->_check_one_admin;

    $self->rest->header(-status => HTTP_202_Accepted);
    return '';
}

# Makes POST_to_users backwards compatible.
sub _parse_data {
    my $data = shift;

    # This is the "new" format, it's a hashref with users index.
    if (ref($data) eq 'HASH') {
        if ($data->{users}) {
            $data = {
                users => $data->{users},
                send_message => $data->{send_message} || 0,
                additional_message => $data->{additional_message},
            };
        }
        elsif ($data->{username} || $data->{user_id}) {
            $data = { users => [$data] };
        }
    }
    elsif (ref($data) eq 'ARRAY') {
        $data = { users => $data };
    }

    # We still may have passed bad data, return if we don't have an arrayref
    # at this point.
    Socialtext::Exception::BadRequest->throw(
        message => loc("error.list-of-users-required"))
        unless ref($data->{users}) eq 'ARRAY';

    for my $user_entry (@{$data->{users}}) {
        # force these to be "adds" in the SetController
        $user_entry->{role_name} ||= 'member';
    }

    return $data;
}

# PUT /data/groups/:group_id/users
sub PUT_to_users {
    my $self = shift;
    my $data = $self->decoded_json_body;

    my $ctrl = $self->controller(
        scopes  => ['user'],
        actions => [qw(add remove update)],
    );

    # allow for self-add/removal on self-join groups
    if ($self->can_self_administer) {
        $ctrl->actions([qw(add remove)]);
        $ctrl->self_action_only(1);
        $ctrl->roles(['member']);
    }
    else {
        # otherwise, user must be an admin
        return $self->not_authorized() unless $self->user_can_admin;
    }
    
    $ctrl->hooks()->{post_user_add} = sub {$self->user_invite($data, @_)}
        if ($data->{send_message});

    $ctrl->alter_members($data->{entry});

    $self->_check_one_admin;

    $self->rest->header(-status => HTTP_202_Accepted);
    return '';
}

sub user_invite {
    my $self       = shift;
    my $data       = shift;
    my $user_role  = shift;

    my $message = $data->{additional_message} || '';

    Socialtext::JobCreator->insert(
        'Socialtext::Job::GroupInvite',
        {
            job => { priority => 80 },
            group_id  => $self->group->group_id,
            user_id   => $user_role->{object}->user_id,
            sender_id => $user_role->{actor}->user_id,
            ($message ? (extra_text => $message) : ()),
        },
    );
}

# DELETE /data/groups/:group_id
sub DELETE {
    my $self = shift;

    # reject related, non-admin, users.
    return $self->not_authorized() unless $self->user_can_admin;

    $self->group->delete($self->rest->user);
    $self->rest->header(-status => HTTP_204_No_Content);
    return '';
}

# put sql_txn *first* so it runs *after* the if_authorized check (remember:
# around works like a stack; first in, last executed)
around qr/^(?:POST|PUT|DELETE)/ => \&sql_txn;

around qr/^POST/   => sub { $_[1]->if_authorized('POST',   @_[0,2..$#_]) };
around qr/^PUT/    => sub { $_[1]->if_authorized('PUT',    @_[0,2..$#_]) };
around qr/^DELETE/ => sub { $_[1]->if_authorized('DELETE', @_[0,2..$#_]) };

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::Group - Group resource handler

=head1 SYNOPSIS

    GET /data/groups/:group_id
    PUT /data/groups/:group_id
    POST /data/groups/:group_id
    DELETE /data/groups/:group_id
    POST /data/groups/:group_id/trash
    POST /data/groups/:group_id/membership
    POST /data/groups/:group_id/users

=head1 DESCRIPTION

View and alter a group.

=cut
