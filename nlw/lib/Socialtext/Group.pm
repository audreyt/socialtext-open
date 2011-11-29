package Socialtext::Group;
# @COPYRIGHT@

use Moose;
use Carp qw(croak);
use List::Util qw(first);
use Socialtext::AppConfig;
use Socialtext::Cache;
use Socialtext::Events;
use Socialtext::Log qw(st_log);
use Socialtext::MultiCursor;
use Socialtext::Timer qw/time_scope/;
use Socialtext::SQL qw(get_dbh :exec :time :txn);
use Socialtext::SQL::Builder qw(sql_abstract);
use Socialtext::UserSet qw/:const/;
use Socialtext::JobCreator;
use Socialtext::Authz::SimpleChecker;
use List::MoreUtils qw/any/;
use Socialtext::Exceptions qw/auth_error/;
use Socialtext::Permission qw(ST_ADMIN_PERM ST_ADMIN_WORKSPACE_PERM);
use namespace::clean -except => 'meta';

###############################################################################
# The "Group" equivalent to a User Homunculus.
has 'homunculus' => (
    is => 'ro', isa => 'Socialtext::Group::Homunculus',
    required => 1,
    handles => [qw(
        group_id
        driver_key
        driver_name
        driver_id
        driver_unique_id
        driver_group_name
        display_name
        name
        description
        primary_account_id
        account_id
        primary_account
        creation_datetime
        created_by_user_id
        creator
        cached_at
        is_system_managed
        expire
        can_update_store
        update_store
        delete
        user_set_id
        permission_set
        display_permission_set
    )],
);

has $_.'_count' => (
    is => 'rw', isa => 'Int',
    lazy_build => 1
) for qw(user workspace account);

with 'Socialtext::UserSetContained',
     'Socialtext::UserSetContainer' => {
        # Moose 0.89 renamed to -excludes and -alias
        ($Moose::VERSION >= 0.89 ? '-excludes' : 'excludes')
            => [qw(enable_plugin disable_plugin
                   add_account assign_role_to_account)],
     };
sub enable_plugin { die "cannot enable a plugin for a group" }
sub disable_plugin { die "cannot disable a plugin for a group" }

around 'update_store' => sub {
    my $orig = shift;
    my $self = shift;
    my $proto = shift;

    my $group_set = $proto->{permission_set};
    if ($group_set && $group_set ne $self->permission_set) {
        my $workspaces = $self->workspaces(exclude_auw_paths=>1);
        my $ws_set = $self->WorkspaceCompatPermSet($group_set);

        die "no compatible workspace permissions for '$group_set'"
            if $workspaces->count() > 0 && !$ws_set;

        while (my $ws = $workspaces->next()) {
            die "workspace has multiple groups" if $ws->group_count > 1;
            $ws->permissions->set(set_name => $ws_set);
        }
    }

    $self->$orig($proto);
};

# Basic implementation for now.
sub allow_invitation { shift->can_update_store() }

sub invite {
    my $self = shift;
    my %p    = @_;  # passed straight through.

    require Socialtext::GroupInvitation;
    return Socialtext::GroupInvitation->new(
        group      => $self,
        from_user  => $p{from_user},
        extra_text => $p{extra_text},
        ($p{viewer} ? (viewer => $p{viewer}) : ()),
    );
}

###############################################################################
# Sticking this here for now; eventually we'll refactor this out into
# something more like ST::UserSetContainer::Permissions (so we can slurp in
# ST:WS:Perms), but we're not getting there today.
sub user_can {
    my $self = shift;
    my %p    = (
        user       => undef,
        permission => undef,
        @_
    );

    require Socialtext::Authz;
    my $authz = Socialtext::Authz->new();
    return $authz->user_has_permission_for_group(
        group         => $self,
        %p,
    );
}

# Give account admins permission to read and admin the group
around 'role_for_user' => sub {
    my $orig = shift;
    my $self = shift;
    my $user = shift;
    my %p = (@_==1) ? %{$_[0]} : @_;

    my $can_admin = $self->primary_account->user_can(
        user => $user,
        permission => ST_ADMIN_PERM,
    );
    if ($can_admin) {
        return Socialtext::Role->Admin->role_id if $p{ids_only};
        return Socialtext::Role->Admin;
    }
    return $orig->($self, $user, %p);
};

sub uri {
    my $self = shift;
    return Socialtext::URI::uri(
        path   => 'st/group/' . $self->group_id,
    );
}

sub user_can_update_perms {
    my $self = shift;
    my $user = shift;

    return 0 unless $self->can_update_store;
    return 0 unless $user->is_business_admin || $self->user_can(
        user       => $user,
        permission => ST_ADMIN_PERM,
    );

    return 1 unless $self->workspace_count > 0;

    my $workspaces = $self->workspaces(exclude_auw_paths=>1);
    while (my $ws = $workspaces->next()) {
        return 0 if $ws->group_count > 1;

        return 0 unless $user->is_business_admin || $ws->permissions->user_can(
            user => $user,
            permission => ST_ADMIN_WORKSPACE_PERM,
        );
    }

    return 1;
}

sub workspace_compat_perm_set {
    my $self = shift;
    return $self->WorkspaceCompatPermSet($self->permission_set);
}

sub WorkspaceCompatPermSet {
    my $class = shift;
    my $set   = shift;
    return {
       'self-join' => 'self-join',
       'private'   => 'member-only',
    }->{$set};
}

###############################################################################
sub Drivers {
    my $drivers = Socialtext::AppConfig->group_factories();
    return split /;/, $drivers;
}

###############################################################################
sub Count {
    my $class   = shift;
    my %p       = @_;
    return $class->All(@_, _count_only => 1);
}

sub ByAccountId {
    my $class   = shift;
    my %p       = @_;
    croak "needs an account_id" unless $p{account_id};
    return $class->All(@_);
}

sub ByWorkspaceId {
    my $class   = shift;
    my %p       = @_;
    croak "needs a workspace_id" unless $p{workspace_id};
    return $class->All(@_);
}

sub All {
    my $class = shift;
    my %p     = @_;
    
    my $from = 'groups';
    my @cols = ('group_id');
    my @where;
    my $order;
    my $t = time_scope('group_cursor');

    my $ob = $p{order_by} || 'driver_group_name';
    $p{sort_order} ||= 'ASC';

    push @where, primary_account_id => $p{primary_account_id}
        if $p{primary_account_id};

    push @where, driver_key => $p{driver_key}
        if $p{driver_key};

    if ($p{account_id}) {
        push @where, \[q{groups.user_set_id IN (
                            SELECT from_set_id
                              FROM user_set_path 
                             WHERE into_set_id = ?)
                         }, $p{account_id} + ACCT_OFFSET];
    }

    if ($p{workspace_id}) {
        push @where, \[q{groups.user_set_id IN (
                            SELECT from_set_id
                              FROM user_set_path
                             WHERE into_set_id = ?)
                        }, $p{workspace_id} + WKSP_OFFSET];
    }

    if ($p{permission_set}) {
        push @where, \[q{groups.permission_set =?}, $p{permission_set}];
    }

    if ($p{_count_only}) {
        @cols = ('COUNT(group_id) as count');
        $order = undef; # force no ORDER BY
    }
    else {
        if ($ob =~ /^\w+$/ and $p{sort_order} =~ /^(?:ASC|DESC)$/i) {
            push @cols, 'driver_group_name';
            if ($ob eq 'driver_group_name') {
                $order = "LOWER($ob) $p{sort_order}";
            }
            else {
                $order = "$ob $p{sort_order}";
                unless ($ob eq 'group_id') {
                    $order .= ", LOWER(driver_group_name) ASC";
                }
            }
            $order .= ", group_id ASC" unless ($ob eq 'group_id');
        }

        if ($p{include_aggregates}) {
            push @cols, 'COALESCE(user_count,0) AS user_count';
            $from .= q{
                LEFT JOIN (
                    SELECT into_set_id AS user_set_id,
                        COUNT(DISTINCT from_set_id) AS user_count
                    FROM user_set_path
                    WHERE from_set_id }.PG_USER_FILTER.q{
                    GROUP BY user_set_id
                ) gu_count USING (user_set_id)
            };

            push @cols, 'COALESCE(workspace_count,0) AS workspace_count';
            $from .= q{
                LEFT JOIN (
                    SELECT from_set_id AS user_set_id,
                        COUNT(DISTINCT into_set_id) AS workspace_count
                    FROM user_set_path
                    WHERE into_set_id }.PG_WKSP_FILTER.q{
                    GROUP BY user_set_id
                ) gw_count USING (user_set_id)
            };
        }

        if ($ob eq 'creator') {
            push @cols, 'users.email_address AS creator';
            $from .= q{ JOIN users ON (groups.created_by_user_id = user_id) };
        }
        elsif ($ob eq 'primary_account') {
            push @cols, '"Account".name AS primary_account';
            $from .= q{ JOIN "Account" ON (
                groups.primary_account_id="Account".account_id) };
        }
        elsif ($ob eq 'role_name') {
            push @cols, 'role_name';
            $from .= q{
                LEFT JOIN (
                    SELECT from_set_id AS user_set_id,
                           name AS role_name
                      FROM user_set_path
                      JOIN "Role" USING (role_id)
                     WHERE into_set_id } . PG_WKSP_FILTER . q{
                ) gw_role USING (user_set_id)
            };
        }
    }

    my ($sql, @bind) = sql_abstract()->select(
        \$from, \@cols, \@where, $order, $p{limit}, $p{offset});
    my $sth = sql_execute($sql, @bind);

    if ($p{_count_only}) {
        my ($count) = $sth->fetchrow_array();
        return $count;
    }

    my $apply;
    if ($p{_apply_gwr}) {
        my $ws = Socialtext::Workspace->new(workspace_id => $p{workspace_id});
        $apply = sub {
            my $row = shift;
            my $group = $class->GetGroup(group_id=>$row->{group_id});
            my $role = $ws->role_for_group($group);
            if ($p{include_aggregates}) {
                $group->$_($row->{$_}) for qw(user_count workspace_count);
            }
            return {
                workspace_id => $ws->workspace_id,
                group_id => $group->group_id,
                role_id => $role->role_id,
                workspace => $ws,
                group => $group,
                role => $role
            };
        };
    }
    elsif ($p{ids_only}) {
        $apply = sub { shift->{group_id} };
    }
    else {
        $apply = sub {
            my $row = shift;
            my $group = $class->GetGroup(group_id=>$row->{group_id});
            unless ($group) {
                warn "Couldn't fetch group_id: $row->{group_id}";
                return;
            }
            if ($p{include_aggregates}) {
                $group->$_($row->{$_}) for qw(user_count workspace_count);
            }
            return $group;
        };
    }
    my $cursor = Socialtext::MultiCursor->new(
        iterables => [ $sth->fetchall_arrayref({}) ],
        apply => $apply,
    );

    return $cursor;
}

sub User_can_create_group {
    my $class = shift;
    my $user  = shift or croak "Must supply a user";

    return Socialtext::AppConfig->users_can_create_groups()
            || $user->is_business_admin()
            || any { 
                   Socialtext::Authz::SimpleChecker->new(
                       user => $user, container => $_
                   )->check_permission('admin') 
               } $user->accounts;

}

###############################################################################
sub Factory {
    my ($class, %p) = @_;
    my $driver_name = $p{driver_name};
    my $driver_id   = $p{driver_id};
    my $driver_key  = $p{driver_key};
    if ($driver_key) {
        ($driver_name, $driver_id) = split /:/, $driver_key;
    }
    else {
        $driver_key = join ':', $driver_name, $driver_id;
    }

    my $driver_class = join '::', $class->base_package(), $driver_name, 'Factory';
    eval "require $driver_class";
    die "couldn't load $driver_class in call to Socialtext::Group->Factory: $@" if $@;

    my $factory = eval { $driver_class->new(driver_key => $driver_key) };
    if ($@) {
        st_log->warning( $@ );
    }
    return $factory;
}

###############################################################################
sub Create {
    my ($class, $proto_group) = @_;
    my $timer = Socialtext::Timer->new;

    # find first updateable factory
    my $factory =
        first { $_->can_update_store }
        grep  { defined $_ }
        map   { $class->Factory(driver_key => $_) }
        $class->Drivers();
    unless ($factory) {
        die "No writable Group factories configured.";
    }

    # ask that factory to create the Group Homunculus
    my $homey = $factory->Create($proto_group);
    $factory->CreateInitialRelationships($homey);
    my $group = Socialtext::Group->new(homunculus => $homey);
    Socialtext::JobCreator->index_group($group);

    my $msg = 'CREATE,GROUP,group_id:' . $group->group_id
              . '[' . $timer->elapsed . ']';
    st_log()->info($msg);

    # Clear the json cache so group navlist get the new group
    require Socialtext::JSON::Proxy::Helper;
    Socialtext::JSON::Proxy::Helper->PurgeCache;

    return $group;
}

###############################################################################
sub GetGroup {
    my $class = shift;
    my %p = (@_==1) ? %{+shift} : @_;

    $p{group_id} -= GROUP_OFFSET
        if exists $p{group_id} and $p{group_id} > GROUP_OFFSET;

    # Allow for lookups by "Group Id" to be cached.
    if ((scalar keys %p == 1) && (exists $p{group_id})) {
        my $cached = $class->cache->get($p{group_id});
        return $cached if $cached;
    }

    # Get the list of Drivers that the Group _could_ be found in; if we were
    # given a Driver Key explicitly then use that, otherwise go searching for
    # the Group in the list of configured Drivers.
    my @drivers = $p{driver_key} || $class->Drivers();

    # Go find the Group
    foreach my $driver_key (@drivers) {
        # instantiate the Group Factory, skipping if Factory doesn't exist
        my $factory = $class->Factory(driver_key => $driver_key);
        next unless $factory;

        # see if this Factory knows about the Group
        my $homey = $factory->GetGroupHomunculus(%p);
        if ($homey) {
            my $group = Socialtext::Group->new(homunculus => $homey);
            $class->cache->set( $group->group_id, $group );
            return $group;
        }
    }

    # nope, didn't find
    return;
}

{
    # IN-MEMORY cache of Groups, by Group Id.
    my $CacheByGroupId;
    sub cache {
        $CacheByGroupId ||= Socialtext::Cache->cache('group:group_id');
        return $CacheByGroupId;
    }
}

###############################################################################
# Peek at the Group's attrs without auto_vivifying.
sub GetProtoGroup {
    my $class = shift;
    my %p = (@_==1) ? %{+shift} : @_;

    my @drivers = $p{driver_key} || $class->Drivers();
    foreach my $driver_key (@drivers) {
        # instantiate the Group Factory, skipping if Factory doesn't exist
        my $factory = $class->Factory(driver_key => $driver_key);
        next unless $factory;

        my $proto = $factory->_get_cached_group( \%p );
        next unless defined $proto;

        $proto->{cached_at} = sql_parse_timestamptz( $proto->{cached_at} );
        return $proto;
    }

    # nope, didn't find
    return undef;
}

sub IndexGroups {
    my $class = shift;
    my $opts  = shift || {};

    unless ($opts->{no_delete}) {
        require Socialtext::Search::Solr::Factory;
        my $factory = Socialtext::Search::Solr::Factory->new;
        my $indexer = $factory->create_indexer();
        $indexer->delete_groups();
    }

    sql_begin_work();
    my $sth = sql_execute('SELECT group_id FROM groups');
    my @jobs;
    while (my ($group_id) = $sth->fetchrow_array) {
        push @jobs, {
            coalesce => "$group_id-reindex", # don't coalesce with normal jobs
            arg => $group_id,
        };
    }

    st_log()->info("going to insert ".scalar(@jobs)." GroupReIndex jobs");
    my $template_job = TheSchwartz::Moosified::Job->new(
        funcname => 'Socialtext::Job::GroupReIndex',
        priority => -30,
    );
    Socialtext::JobCreator->bulk_insert($template_job, \@jobs);
    st_log()->info("done GroupReIndex bulk_insert");

    sql_commit();
    return scalar(@jobs);
}

###############################################################################
# Base package for Socialtext Group infrastructure.
use constant base_package => __PACKAGE__;

###############################################################################
sub accounts {
    my ($self, %p) = @_;

    my $table = $p{include_indirect} ? 'user_set_path' : 'user_set_include';

    # all accounts with direct (or indirect) membership
    my $sth = sql_execute(qq{
        SELECT DISTINCT account_id
        FROM $table
        JOIN "Account" ON (into_set_id = user_set_id)
        WHERE from_set_id = ?
    }, $self->user_set_id);
    my $ids = $sth->fetchall_arrayref || [];
    return Socialtext::MultiCursor->new(
        iterables => [$ids],
        apply     => $p{ids_only} ? sub {$_[0][0]} : sub {
            return Socialtext::Account->new(account_id => $_[0][0]);
        },
    );
}

sub _build_user_count    { shift->users->count }
sub _build_account_count { shift->accounts->count }

after 'role_change_event' => sub {
    my ($self,$actor,$change,$thing,$role) = @_;
    if ($thing->isa('Socialtext::User') && $change ne 'update') {
        my $ev_action = $change.'_user';
        Socialtext::Events->Record({
            event_class => 'group',
            action => $ev_action,
            actor => $actor,
            person => $thing,
            group => $self,
        });
    }
};

after 'role_change_check' => sub {
    my ($self,$actor,$change,$thing,$role) = @_;

    return if $self->user_can(
        user       => $actor,
        permission => ST_ADMIN_PERM
    );

    if ($change eq 'remove' && $thing->can('user_id') &&
        $actor->user_id == $thing->user_id)
    {
        # users can always self-part
        return;
    }

    # allow self-updating users for the self-join type of groups
    if ($self->permission_set eq 'self-join' &&
        $thing->can('user_id') && 
        $actor->user_id == $thing->user_id &&
        $self->shares_account_with($actor)
    ) {
        if ($change eq 'add' || $change eq 'update') {
            return if $role->name eq 'member';
            # an admin adds themselves as the first action to an empty group
            if ($role->name eq 'admin') {
                return if $self->role_count == 0;
            }
        }
    }

    auth_error "You are not allowed to modify this group's membership";
};

###############################################################################
sub workspaces {
    my $self = shift;
    my %p = @_;

    my $t = time_scope('group_workspaces');

    my $sql = q{
        SELECT DISTINCT into_set_id
          FROM user_set_path usp
         WHERE from_set_id = ?
           AND into_set_id }.PG_WKSP_FILTER.q{
    };

    if ($p{exclude_auw_paths}) {
        # There isn't a path via some account from this group to the workspace
        # in question.
        $sql .= q{
           AND NOT EXISTS (
              SELECT 1
                FROM user_set_path_component uspc
               WHERE uspc.user_set_path_id = usp.user_set_path_id
                 AND uspc.user_set_id }.PG_ACCT_FILTER.q{
           )
        }
    }

    my $sth = sql_execute($sql, $self->user_set_id);
    return Socialtext::MultiCursor->new(
        iterables => $sth->fetchall_arrayref(),
        apply => sub {
            my $ws_id = (shift) - WKSP_OFFSET;
            return Socialtext::Workspace->new(workspace_id => $ws_id);
        },
    );
}

###############################################################################
sub photo {
    my $self = shift;
    require Socialtext::Group::Photo;
    return Socialtext::Group::Photo->new( group => $self );
}

###############################################################################
sub to_hash {
    my $self = shift;
    my %opts = @_;

    my $hash = {
        group_id           => $self->group_id,
        name               => $self->driver_group_name,
        description        => $self->description,
        user_count         => $self->user_count,
        primary_account_id => $self->primary_account_id,
        permission_set     => $self->permission_set,
    };
    if (!$opts{minimal}) {
        $hash = {
            %$hash,
            workspace_count      => $self->workspace_count,
            creation_date        => $self->creation_datetime->ymd,
            created_by_user_id   => $self->created_by_user_id,
            created_by_username  => $self->creator->guess_real_name,
            primary_account_name => $self->primary_account->name,
        };
    }

    if ($opts{show_members}) {
        $hash->{members} = $self->users_as_minimal_arrayref('member');
    }
    if ($opts{show_admins}) {
        $hash->{admins} = $self->users_as_minimal_arrayref('admin');
    }
    if ($opts{plugins}) {
        $hash->{plugins_enabled} = [ sort $self->plugins_enabled ],
    }
    if ($opts{show_account_ids}) {
        $hash->{account_ids} = [ $self->accounts(ids_only => 1)->all ];
    }

    return $hash;
}

sub users_as_minimal_arrayref {
    my $self = shift;
    my $role_name = shift;

    my %user_roles_params;
    if ($role_name and (my $role = Socialtext::Role->new(name => $role_name))) {
        $user_roles_params{role_id} = $role->role_id;
    }

    my @members;
    my $cursor = $self->user_roles(%user_roles_params);
    while (my $ur = $cursor->next) {
        my ($user, $role) = @$ur;
        my $hash = $user->to_hash(minimal => 1);
        $hash->{role} = $role->name;
        push @members, $hash;
    }

    return \@members;
}

sub serialize_for_export {
    my $self = shift;
    return {
        # Convert IDs to "name"s for export
        primary_account_name    => $self->primary_account->name,
        driver_group_name       => $self->driver_group_name,
        description             => $self->description,
        creation_datetime       => sql_format_timestamptz($self->creation_datetime),
        created_by_username     => $self->creator->username,
        group_id                => $self->group_id, 
        permission_set          => $self->permission_set,
        # (group_id is used to stitch together signals on import )
    };
}

sub _build_workspace_count {
    return shift->workspaces->count;
}

sub impersonation_ok {
    # group-context impersonation is never allowed
    return;
}

__PACKAGE__->meta->make_immutable;
1;
__END__

=head1 NAME

Socialtext::Group - Socialtext Group object

=head1 SYNOPSIS

  use Socialtext::Group;

  # get a list of all registered Group factories/drivers
  @drivers = Socialtext::Group->Drivers();

  # instantiate a specific Group Factory
  $factory = Socialtext::Group->Factory(driver_key => $driver_key);
  $factory = Socialtext::Group->Factory(
    driver_name => $driver_name,
    driver_id   => $driver_id,
    );

  # create a new Group
  $group = Socialtext::Group->Create( \%proto_group );

  # retrieve an existing Group
  $group = Socialtext::Group->GetGroup(group_id => $group_id);

  # get the Users in the Group
  $user_multicursor = $group->users();

  # get the User Ids for the Users in the Group
  $user_id_aref = $group->user_ids();

  # get the Workspaces the Group has access to
  $ws_multicursor = $group->workspaces();

  # add a User to the Group
  $group->add_user(user => $user, role => $role);

  # update a user's role in the Group
  $group->assign_role_to_user(user => $user, role => $role);

  # remove a User from a Group
  $group->remove_user(user => $user);

  # check if a User already exists in the Group
  $exists = $group->has_user($user);

  # get the Role for a User in the Group
  $role = $group->role_for_user($user);

  # get cached counts
  $n = $group->user_count;
  $n = $group->workspace_count;

  # serialize the Group metadata for export
  $hash = $group->serialize_for_export();

=head1 DESCRIPTION

This class provides methods for dealing with Groups.

=head1 METHODS

=over

=item B<Socialtext::Group-E<gt>Drivers()>

Returns a list of registered Group factories/drivers back to the caller, as a
list of their "driver_key"s.  These "driver_key"s can be used to instantiate a
factory by calling C<Socialtext::Group-E<gt>Factory()>.

=item B<Socialtext::Group-E<gt>Factory(%opts)>

Instantiates a Group Factory, as defined by the provided C<%opts>.

Valid instantiation C<%opts> include:

=over

=item driver_key =E<gt> $driver_key

Factory instantiation via driver key (which contains both the name of the
driver and its id).

=item driver_name =E<gt> $driver_name, driver_id =E<gt> $driver_id

Factory instantiation via driver name+id.

=back

=item B<Socialtext::Group-E<gt>Create(\%proto_group)>

Attempts to create a Group with the given C<\%proto_group> hash-ref, returning
the newly created Group object back to the caller.  The Group will be created
in the first updateable Group Factory store, as found in the list of
C<Drivers()>.

For more information on the required attributes for a Group, please refer to
L<Socialtext::Group::Factory> and its C<Create()> method.

=item B<Socialtext::Group-E<gt>GetGroup(\%proto_group)>

Looks for a Group matching the provided C<\%proto_group> key/value pairs, and
returns a C<Socialtext::Group> object for that Group if one exists.

The C<\%proto_group> hash-ref B<must> contain sufficient information in order
to I<uniquely> identify a single Group in the database.

Please refer to the primary and unique key definitions in
C<Socialtext::Group::Homunculus> for more information on which sets of columns
can be used to uniquely identify a Group record.

=item B<Socialtext::Group-E<gt>All(PARAMS)>

Returns a C<Socialtext::MultiCursor> containing all Groups.

Accepts the following PARAMS:

=over

=item account_id => $account_id

Restricts results to only contain those Groups that have the provided
C<$account_id> as their Primary Account Id.

=item driver_key => $driver_key

Restricts results to only contain those Groups that were created by the Group
Factory identified by the given C<$driver_key>.

=item order_by => $field

Orders the results on the given C<$field>, which can be any one of:

=over

=item * any of the columns in the "groups" table,

=item * "creator", the e-mail address of the creating User,

=item * "primary_account", the name of the Group's Primary Account.

=item * "user_count", the count of Users in the Group

Requires that C<include_aggregates> be passed through (see below).

=item * "workspace_count", the count of Workspaces the Group is a member of

Requires that C<include_aggregates> be passed through (see below).

=back

By default, the Groups are returned ordered by their Group Name.

=item sort_order => (ASC|DESC)

Specifies that the Groups should be returned in ascending or descending order.

=item ids_only => 1

Return I<only> the Group Ids.  By default, Group objects are returned.

=item include_aggregates => 1

Specifies that the C<Socialtext::Group> objects returned should B<already>
have their "user_count" and "workspace_count" attributes pre-calculated.

By default, you'll get back Group objects that you could call to calculate the
counts on, but if you know you're going to need this then you can optimize by
asking for those aggregates to be pre-calculated.

Having these aggregates pre-calculated B<also> allows for you to sort based on
the aggregate values.

=item limit => N, offset => N

For paging through a long list of groups.

=back

=item B<Socialtext::Group-E<gt>ByAccountId(PARAMS)>

Returns a C<Socialtext::MultiCursor> containing a list of all of the Groups
that have the specified Account as their Primary Account.

Accepts the same PARAMS as C<All()> above, but B<requires> that an
C<account_id> parameter be provided to specify the Primary Account Id that we
should be pulling up Groups for.

This method is basically a helper method for C<All()> above but which ensures
that you've actually passed through an C<account_id> parameter.

=item B<Socialtext::Group-E<gt>Count(PARAMS)>

Returns a count of Groups based on PARAMS (which are the same as for C<All()>
above).

=item B<Socialtext::Group-E<gt>GetProtoGroup($key, $val)>

Looks for group matching the give C<$key/$val> pair, and returns a
hashref for the group's attributes.

Uses the same C<$key> args as C<Socialtext::Group-E<gt>GetGroup()>.

=item B<Socialtext::Group-E<gt>base_package()>

Returns the Perl namespace underneath which all of the Group related modules
can be found.

=item B<$group-E<gt>users()>

Returns a C<Socialtext::MultiCursor> of Users who have a Role in this Group.

=item B<$group-E<gt>user_ids()>

Returns a list-ref containing the User Ids of the Users who have a Role in
this Group.

=item B<$group-E<gt>user_count>

Returns a B<cached> count of Users who have a Role in this Group

=item B<$group-E<gt>add_user(user=E<gt>$user, role=E<gt>$role)>

Adds a given C<$user> to the Group with the specified C<$role>.

If no C<$role> is provided, a default Role will be used instead.

Throws an exception if the User B<already> has a Role in the Group.

=item B<$group-E<gt>assign_role_to_user(user=E<gt>$user, role=E<gt>$role)>

Same as C<add_user>, but if the User B<already> has a Role in the Group,
the User's Role will be B<updated> to match the given C<$role>.

=item B<$group-E<gt>remove_user(user=E<gt>$user)>

Removes any Role that the given C<$user> may have in the Group.  If the User
has no Role in the Group, this method does nothing.

=item B<$group-E<gt>has_user($user)>

Checks to see if the given C<$user> has a Role in this Group, returning true
if the User has a Role, false otherwise.

=item B<$group-E<gt>role_for_user($user)>

Returns a C<Socialtext::Role> object representing the Role that the given
C<$user> has in this Group.  If the User has no Role in the Group, this method
returns empty-handed.

=item B<$group-E<gt>workspaces()>

Returns a C<Socialtext::MultiCursor> of Workspaces that this Group has a Role
in.

=item B<$group-E<gt>workspace_count>

Returns a B<cached> count of Workspaces in which this Group has a Role

=item B<$group-E<gt>serialize_for_export()>

Serializes the Group metadata for export, and returns it to the caller as a
hash-ref.

=item B<$group-E<gt>homunculus()>

Returns the Group Homunculus for the Group.

=item B<$group-E<gt>group_id()>

=item B<$group-E<gt>driver_key()>

=item B<$group-E<gt>driver_name()>

=item B<$group-E<gt>driver_id()>

=item B<$group-E<gt>driver_unique_id()>

=item B<$group-E<gt>driver_group_name()>

=item B<$group-E<gt>description()>

=item B<$group-E<gt>primary_account_id()>

=item B<$group-E<gt>primary_account()>

=item B<$group-E<gt>creation_datetime()>

=item B<$group-E<gt>created_by_user_id()>

=item B<$group-E<gt>creator()>

=item B<$group-E<gt>cached_at()>

=item B<$group-E<gt>is_system_managed()>

=item B<$group-E<gt>expire()>

=item B<$group-E<gt>can_update_store()>

=item B<$group-E<gt>update_store()>

=item B<$group-E<gt>delete()>

Delegated to the homunculus attribute (a C<Socialtext::Group::Homunculus>).

=back

=head1 AUTHOR

Socialtext, Inc.,  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc.,  All Rights Reserved.

=cut
