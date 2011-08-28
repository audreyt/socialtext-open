package Socialtext::Rest::Groups;
# @COPYRIGHT@
use Moose;
use Socialtext::Group;
use Socialtext::HTTP ':codes';
use Socialtext::JSON qw/decode_json encode_json/;
use Socialtext::File;
use Socialtext::SQL ':txn';
use Socialtext::Exceptions;
use Socialtext::Role;
use Socialtext::Permission 'ST_ADMIN_WORKSPACE_PERM';
use Socialtext::JobCreator;
use Socialtext::Upload;
use Scalar::Util qw(blessed);
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Collection';
with 'Socialtext::Rest::Pageable';

# Anybody can see these, since they are just the list of groups the user
# has 'selected'.
sub permission { +{} }

sub collection_name { 'Groups' }

sub _entity_hash { 
    my ($self, $group) = @_;
    my $minimal = $self->rest->query->param('minimal');
    if ($minimal or $self->rest->query->param('ids_only')) {
        if (blessed($group) and $group->can('to_hash')) {
            return $group->to_hash(minimal => $minimal) ;
        }
        else {
            return $group;
        }
    }
    my $show_members = $self->rest->query->param('show_members');
    return {
        group_id => $group->group_id,
        name => $group->name,
        user_count => $group->user_count,
        workspace_count => $group->workspace_count,
        creation_date => $group->creation_datetime->ymd,
        created_by_user_id => $group->created_by_user_id,
        created_by_username => $group->creator->guess_real_name,
        uri => "/data/groups/" . $group->group_id,
        primary_account_id => $group->primary_account_id,
        primary_account_name => $group->primary_account->name,
        description => $group->description,
        permission_set => $group->permission_set,
        $show_members
            ? ( members => $group->users_as_minimal_arrayref('member') )
            : (),
    };
}

sub _get_total_results {
    my $self = shift;
    my $user = $self->rest->user;
    if ($user->is_business_admin and $self->rest->query->param('all')) {
        Socialtext::Group->Count;
    }
    elsif (defined $self->{_total_results}) {
        return $self->{_total_results};
    }
    else {
        return $user->group_count;
    }
}

sub _get_entities {
    my $self = shift;
    my $user = $self->rest->user;
    my $q    = $self->rest->query;

    my $filter = $q->param('q') || $q->param('filter') || '';
    my $discoverable = $q->param('discoverable');
    my $all = $user->is_business_admin && $self->rest->query->param('all');
 
    if ($filter) {
        my $group_ids = [
            $user->groups(discoverable => $discoverable, ids_only => 1)->all
        ];

        require Socialtext::Search::Solr::Factory;
        my $searcher = Socialtext::Search::Solr::Factory->create_searcher();
        my ($results, $count) = $searcher->begin_search(
            $filter,
            undef,
            undef,
            doctype   => 'group',
            limit     => $self->items_per_page, 
            offset    => $self->start_index,
            direction => $self->reverse ? 'desc' : 'asc',
            order     => 'title',
            group_ids => $group_ids,
            $all ? () : (viewer => $user),
        );
        $self->{_total_results} = $count;

        # This was:
        #     return [ map { $_->group } @{ $results->() } ];
        # but somehow it corrupts $_'s memory to "=cut " if LDAP
        # is enabled; rewrite using named variable for now.
        my @result;
        for my $hit (@{ $results->() }) {
            push @result, $hit->group;
        }
        return \@result;
    }
    else {
        if ($all) {
            my $iter = Socialtext::Group->All(
                order_by => $self->order,
                sort_order => $self->reverse ? 'DESC' : 'ASC',
                include_aggregates => 1,
                creator => 1,
                primary_account => 1,
                limit => $self->items_per_page,
                offset => $self->start_index,
            );
            return [ $iter->all ];
        }
        elsif (defined $self->rest->query->param('startIndex') and not $self->rest->query->param('skipTotalResult')) {
            # We need to supply "total_results".
            my $full_set = [ $user->groups( discoverable => $discoverable )->all ];
            $self->{_total_results} = @$full_set; # XXX - Re-implement this entire paragraph with a Count method.
            splice(@$full_set, 0, $self->start_index) if $self->start_index;
            splice(@$full_set, $self->items_per_page) if @$full_set > $self->items_per_page;
            return $full_set;
        }
        else {
            # Old API; no need to supply total_results.
            return [ $user->groups(
                ids_only => scalar $self->rest->query->param('ids_only'),
                minimal => scalar $self->rest->query->param('minimal'),
                discoverable => $discoverable,
                limit => $self->items_per_page,
                offset => $self->start_index,
            )->all ];
        }
    }
}

override extra_headers => sub {
    my $self = shift;
    my $resource = shift;

    return (
        '-cache-control' => 'private',
    );
};

sub POST_json {
    my $self = shift;
    my $rest = shift;
    my $user = $rest->user;

    unless ($user->is_authenticated && !$user->is_deleted
                && Socialtext::Group->User_can_create_group($user)) {
        $rest->header(-status => HTTP_401_Unauthorized);
        return '';
    }

    my $data = eval { decode_json($rest->getContent()) };
    if ($@) {
        $rest->header(-status => HTTP_400_Bad_Request);
        return "bad json\n";
    }

    unless ($data->{name} || $data->{ldap_dn}) {
        $rest->header(-status => HTTP_400_Bad_Request);
        return "Either ldap_dn or name is required to create a group.";
    }

    unless ( defined $data and ref($data) eq 'HASH' ) {
        $rest->header(-status => HTTP_400_Bad_Request);
        return '';
    }

    $data->{account_id} ||= $user->primary_account_id;

    my $group;
    eval { sql_txn {
        $group = ($data->{ldap_dn})
            ? $self->_create_ldap_group($data)
            : $self->_create_native_group($data);

        $self->_add_members_to_group($group, $data);

        my @created = $self->_create_workspaces(
            $group->workspace_compat_perm_set(), $data->{new_workspaces});

        $self->_add_group_to_workspaces(
            $group, @{$data->{workspaces}}, @created);

    }};
    if (my $e = $@) {
        my $status = (ref($e) eq 'Socialtext::Exception::Auth')
            ? HTTP_401_Unauthorized
            : HTTP_400_Bad_Request;

        $rest->header(-status => $status);
        return $e;
    }

    if (my $photo_id = $data->{photo_id}) {
        eval {
            my $blob;
            my $upload = Socialtext::Upload->Get(attachment_uuid => $photo_id);
            $upload->binary_contents(\$blob);
            $group->photo->set(\$blob);
            $upload->purge;
        };
        if (my $e = $@) {
            warn "Couldn't set profile photo: $e";
        }
    }

    $rest->header(-status => HTTP_201_Created);
    return encode_json($group->to_hash);
}

sub _add_members_to_group {
    my $self    = shift;
    my $group   = shift;
    my $data    = shift;
    my $invitor = $self->rest->user;

    return unless $data and $data->{users};
    die "group is not updateable\n" unless $group->can_update_store;

    my $notify  = $data->{send_message} || 0;
    my $message = $data->{additional_message} || '';

    my $abdicated_role;
    for my $meta (@{$data->{users}}) {
        my $name_or_id = $meta->{username} || $meta->{user_id};
        my $invitee = Socialtext::User->Resolve($name_or_id)
            or die "no such user\n";

        my $shared_plugin = $invitor->can_use_plugin_with('groups', $invitee);
        die Socialtext::Exception::Auth->new()
            unless $shared_plugin || $invitor->is_business_admin;

        my $role = Socialtext::Role->new(
            name => ($meta->{role}) ? $meta->{role} : 'member' );
        die "no such role: '$meta->{role}'\n" unless $role;

        if ($invitee->user_id == $invitor->user_id) {
            if ($role->role_id != Socialtext::Role->Admin->role_id) {
                # The creating user wish to become a non-admin;
                # remember this decision but postpone it until after
                # adding the rest of the users into the new group.
                $abdicated_role = $role;
            }
        }
        next if $group->role_for_user($invitee, {direct => 1});

        $group->add_user(
            user  => $invitee,
            role  => $role,
            actor => $invitor,
        );

        if ($notify) {
            Socialtext::JobCreator->insert(
                'Socialtext::Job::GroupInvite',
                {
                    job => { priority => 80 },
                    group_id  => $group->group_id,
                    user_id   => $invitee->user_id,
                    sender_id => $invitor->user_id,
                    $message ? (extra_text => $message) : (),
                }
            );
        }
    }

    if ($abdicated_role) {
        $group->assign_role_to_user(
            user  => $invitor,
            role  => $abdicated_role,
            actor => $invitor,
        );
    }
}

sub _create_workspaces {
    my $self      = shift;
    my $ws_perms  = shift;
    my $to_create = shift;
    my $creator   = $self->rest->user;

    my @ws_meta = ();
    for my $meta (@$to_create) {
        my $ws = Socialtext::Workspace->create(
            name       => $meta->{name},
            title      => $meta->{title},
            account_id => $creator->primary_account_id,
            created_by_user_id => $creator->user_id,
        );

        $ws->permissions->set(set_name => $ws_perms);

        push @ws_meta, {workspace_id => $ws->workspace_id, role => 'member'};
    }

    return @ws_meta;
}

sub _add_group_to_workspaces {
    my $self    = shift;
    my $group   = shift;
    my @ws_meta = @_;
    my $invitor = $self->rest->user;

    for my $ws (@ws_meta) {
        my $workspace = Socialtext::Workspace->new(
            workspace_id => $ws->{workspace_id}
        ) or die "no such workspace\n";

        my $perm = $workspace->permissions->user_can(
            user       => $invitor,
            permission => ST_ADMIN_WORKSPACE_PERM,
        );
        die Socialtext::Exception::Auth->new()
            unless $perm || $self->rest->user->is_business_admin;

        my $role = Socialtext::Role->new(
            name => ($ws->{role}) ? $ws->{role} : 'member' );
        die "no such role: '$ws->{role}'\n" unless $role;

        if ($group->permission_set eq 'private'
            && $workspace->permissions->current_set_name ne 'member-only'
        ) {
            die Socialtext::Exception::DataValidation->new();
        }

        next if $workspace->role_for_group($group, {direct => 1});

        $workspace->add_group(
            group => $group,
            role  => $role,
            actor => $invitor,
        );
    }
}

sub _create_ldap_group {
    my $self    = shift;
    my $data    = shift;
    my $rest    = $self->rest;
    my $ldap_dn = $data->{ldap_dn};

    die Socialtext::Exception::Auth->new()
        unless $rest->user->is_business_admin;

    Socialtext::Group->GetProtoGroup(driver_unique_id => $ldap_dn)
        and die "group already exists\n";

    my $group = Socialtext::Group->GetGroup(
        driver_unique_id   => $data->{ldap_dn},
        primary_account_id => $data->{account_id},
    ) or die "ldap group does not exist\n";

    return $group;
}

sub _create_native_group {
    my $self    = shift;
    my $data    = shift;
    my $creator = $self->rest->user;

    Socialtext::Group->GetProtoGroup(
        driver_group_name  => $data->{name},
        primary_account_id => $data->{account_id},
        created_by_user_id => $creator->user_id,
    ) and die "group already exists\n";

    my $group = Socialtext::Group->Create({
        driver_group_name  => $data->{name},
        primary_account_id => $data->{account_id},
        created_by_user_id => $creator->user_id,
        description        => $data->{description},
        permission_set     => $data->{permission_set},
    });

    return $group;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::Groups - List groups on the system.

=head1 SYNOPSIS

    GET /data/groups

=head1 DESCRIPTION

View the list of groups.  You can only see groups you created or are a
member of, unless you are a business admin, in which case you can see
all groups.

=cut
