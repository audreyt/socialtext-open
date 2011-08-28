package Socialtext::UserSetContainer;
# @COPYRIGHT@
use Moose::Role;
use Carp qw/croak/;
use Socialtext::SQL qw/:exec :txn/;
use Socialtext::l10n qw/loc/;
use Socialtext::UserSet qw/:const/;
use Socialtext::UserSetPerspective;
use Socialtext::Exceptions qw/param_error/;
use Socialtext::Cache ();
use Socialtext::MultiCursor;
use Socialtext::Timer qw/time_scope/;
use Socialtext::Log qw/st_log/;
use Time::HiRes qw/time/;
use List::MoreUtils qw/any/;
use Guard;
use namespace::clean -except => 'meta';

requires 'user_set_id';
requires 'impersonation_ok';

has 'user_set' => (
    is => 'ro', isa => 'Socialtext::UserSet',
    lazy_build => 1,
);

sub _build_user_set {
    my $self = shift;
    return Socialtext::UserSet->new(
        owner => $self,
        owner_id => $self->user_set_id,
    );
}

sub plugins_enabled {
    my $self = shift;
    my $authz = Socialtext::Authz->new();
    return $authz->plugins_enabled_for_user_set(user_set => $self, @_);
}

sub is_plugin_enabled {
    my ($self, $plugin_name) = @_;
    my $authz = Socialtext::Authz->new();
    return $authz->plugin_enabled_for_user_set(
        user_set    => $self,
        plugin_name => $plugin_name,
        direct => 1,
    );
}

sub enable_plugin {
    my ($self, $plugin, $scope) = @_;
    $scope ||= 'account';

    require Socialtext::Pluggable::Adapter;
    my $plugin_class = Socialtext::Pluggable::Adapter->plugin_class($plugin);
    $self->_check_plugin_scope($plugin, $plugin_class, $scope);

    return if $self->is_plugin_enabled($plugin);

    Socialtext::Pluggable::Adapter->EnablePlugin($plugin => $self);

    sql_execute(q{
        INSERT INTO user_set_plugin VALUES (?,?)
    }, $self->user_set_id, $plugin);

    Socialtext::Cache->clear('authz_plugin');
    Socialtext::Cache->clear('user_accts');

    for my $dep ($plugin_class->dependencies, $plugin_class->enables) {
        $self->enable_plugin($dep);
    }
}

sub disable_plugin {
    my ($self, $plugin, $scope) = @_;
    $scope ||= 'account';

    require Socialtext::Pluggable::Adapter;
    my $plugin_class = Socialtext::Pluggable::Adapter->plugin_class($plugin);
    $self->_check_plugin_scope($plugin, $plugin_class, $scope);

    # Don't even bother disabling deps if the plugin is already enabled
    return unless $self->is_plugin_enabled($plugin);

    Socialtext::Pluggable::Adapter->DisablePlugin($plugin => $self);

    sql_execute(q{
        DELETE FROM user_set_plugin
        WHERE user_set_id = ? AND plugin = ?
    }, $self->user_set_id, $plugin);

    Socialtext::Cache->clear('authz_plugin');
    Socialtext::Cache->clear('user_accts');

    # Disable any reverse depended packages
    for my $rdep ($plugin_class->reverse_dependencies) {
        $self->disable_plugin($rdep);
    }
}

sub _check_plugin_scope {
    my ($self,$plugin,$plugin_class,$scope) = @_;

    die loc("error.invalid-scope=plugin,scope", $plugin, $scope) . "\n"
        unless $plugin_class->scope eq $scope;
}

sub PluginsEnabledForAll {
    my $class = shift;
    my $table = shift;
    my $sth = sql_execute(
        q{SELECT field FROM "System" where field like '%-enabled-all'});
    my @plugins = map { $_->[0] =~ m/(.+)-enabled-all/; $1 }
                    @{ $sth->fetchall_arrayref };
    my @enabled_for_all;
    for my $plugin (@plugins) {
        my $count = sql_singlevalue(<<EOT);
SELECT count(*) FROM "$table"
    WHERE user_set_id NOT IN (
        SELECT user_set_id FROM user_set_plugin
            WHERE plugin = '$plugin'
    )
EOT
        push @enabled_for_all, $plugin if $count == 0;
    }
    return @enabled_for_all;
}

sub role_default {
    my ($self,$thing) = @_;
    return Socialtext::Role->Member;
}

sub add_role {
    my $self = shift;
    my %p = (@_==1) ? %{$_[0]} : @_;
 
    my $t = time();
    $self->_role_change_checker({%p,action=>'add'});

    my $thing = $p{object};
    my $role  = $p{role} || $self->role_default($thing);

    $self->role_change_check($p{actor},'add',$thing,$role)
        unless $p{force};
    eval { $self->user_set->add_object_role($thing, $role) };
    if ($@) {
        if ($@ =~ /constraint/i) {
            confess "could not add role: object already exists with some role";
        }
        die $@;
    }

    eval { $self->role_change_event($p{actor},'add',$thing,$role) };
    eval { $self->_log_role_change($p{actor},'add',$thing,$role,$t) };
    return;
}

sub assign_role {
    my $self = shift;
    my %p = (@_==1) ? %{$_[0]} : @_;
 
    my $t = time;
    $self->_role_change_checker({%p,action=>'update'});

    my $thing = $p{object};
    my $role = $p{role} || $self->role_default($thing);

    my $uset = $self->user_set;
    my $change;
    if ($uset->directly_connected($thing->user_set_id => $self->user_set_id)) {
        $change = 'update';
        $self->role_change_check($p{actor},$change,$thing,$role);
        $uset->update_object_role($thing, $role);
    }
    else {
        $change = 'add';
        $self->role_change_check($p{actor},$change,$thing,$role);
        $uset->add_object_role($thing, $role);
    }

    eval { $self->role_change_event($p{actor},$change,$thing,$role) };
    eval { $self->_log_role_change($p{actor},$change,$thing,$role,$t) };
    return;
}

sub remove_role {
    my $self = shift;
    my %p = (@_==1) ? %{$_[0]} : @_;
 
    my $t = time;
    $self->_role_change_checker({%p,action=>'remove'});

    my $thing = $p{object};
    $self->role_change_check($p{actor},'remove',$thing);
    my $role_id = $self->user_set->direct_object_role($thing);
    unless ($role_id) {
        die "object not in this user set, ".
            "set:".$self->user_set_id." obj:".$thing->user_set_id;
    }

    $self->user_set->remove_object_role($thing);

    my $role_removed = Socialtext::Role->new(role_id => $role_id);
    eval { $self->role_change_event($p{actor},'remove',$thing,$role_removed) };
    eval { $self->_log_role_change($p{actor},'remove',$thing,$role_removed,$t) };
    return $role_removed;
}

sub has_at_least_one_admin {
    my $self = shift;
    # XXX: conflates admin role with admin-like privs.
    my $admins = $self->role_count(
        role => Socialtext::Role->Admin(),
        direct => 1,
    );
    return ($admins >= 1);
}

sub shares_account_with {
    my $self = shift;
    my $set  = shift;
    return Socialtext::Authz->new->user_sets_share_an_account($set, $self);
}

sub _role_change_checker {
    my ($self,$p) = @_;

    if ($p->{role}) {
        $p->{role} ||= $self->role_default($p->{object});
        if (!blessed $p->{role}) {
            if ($p->{role} =~ /\D/) {
                $p->{role} = Socialtext::Role->new(name => $p->{role})
            }
            else {
                $p->{role} = Socialtext::Role->new(role_id => $p->{role})
            }
        }
        param_error "role parameter must be a Socialtext::Role"
            unless (blessed $p->{role} && $p->{role}->isa('Socialtext::Role'));
        param_error 'Cannot explicitly assign a default role: '.$p->{role}->name
            if $p->{role}->used_as_default;
    }

    param_error "requires an actor parameter that's a Socialtext::User"
        unless (blessed($p->{actor}) && $p->{actor}->isa('Socialtext::User'));

    my $o = $p->{object};
    param_error "object parameter must be blessed" unless blessed $o;
    unless ($o->isa('Socialtext::User') ||
            $o->does('Socialtext::UserSetContainer') ||
            $o->isa('Socialtext::UserMetadata'))
    {
        param_error "object parameter must be a Socialtext::User, Socialtext::UserMetadata or implement role Socialtext::UserSetContainer";
    }

    if ($o->isa('Socialtext::User') &&
        $o->is_system_created &&
        $p->{action} ne 'remove')
    {
        param_error 'Cannot give a role to a system-created user';
    }
}

my %_change_to_log_action = (
    add => 'ASSIGN',
    update => 'CHANGE',
    remove => 'REMOVE',
);

sub _log_role_change {
    my ($self,$actor,$change,$thing,$role,$start) = @_;

    my $r_name = $role->name;
    my $action = $_change_to_log_action{$change};
    my ($t_short, $t_id) = _log_identifier_for_thing($thing);
    my ($c_short, $c_id) = _log_identifier_for_thing($self);
    my (undef,    $a_id) = _log_identifier_for_thing($actor);

    my $msg = $action . ',' . uc($t_short) . '_ROLE,'.
        "role:$r_name,${t_short}:$t_id,${c_short}:$c_id,".
        "actor:$a_id,".
        '['.(time-$start).']';
    st_log()->info($msg);
}

sub _log_identifier_for_thing {
    my $thing = shift;

    if ($thing->isa('Socialtext::User') ||
        $thing->isa('Socialtext::UserMetadata'))
    {
        my $uname = $thing->can('username') ? $thing->username : $thing->email_address_at_import;
        return 'user', $uname.'('.$thing->user_id.')';
    }
    elsif ($thing->isa('Socialtext::Group')) {
        return 'group', $thing->driver_group_name.'('.$thing->group_id.')';
    }
    elsif ($thing->isa('Socialtext::Workspace')) {
        return 'workspace', $thing->name.'('.$thing->workspace_id.')';
    }
    elsif ($thing->isa('Socialtext::Account')) {
        return 'account', $thing->name.'('.$thing->account_id.')';
    }
    elsif ($thing->does('Socialtext::UserSetContainer')) {
        return 'user-set', '('.$thing->user_set_id.')';
    }
    die "unrecognized object type for logging: $thing";
}

sub role_change_check {
    my ($self,$actor,$change,$thing,$role) = @_;
    return;
}

sub role_change_event {
    my ($self,$actor,$change,$thing,$role) = @_;

    Socialtext::Cache->clear('authz_plugin');

    Socialtext::Cache->clear('ws_roles')
        unless $self->isa('Socialtext::Account');

    if ($thing->isa('Socialtext::User')) {
        require Socialtext::JSON::Proxy::Helper;
        Socialtext::JSON::Proxy::Helper->ClearForUsers($thing->user_id);
        if ($change ne 'update') {
            require Socialtext::JobCreator;
            Socialtext::JobCreator->index_person( $thing );
        }
    }
    elsif ($thing->isa('Socialtext::Group')) {
        require Socialtext::JSON::Proxy::Helper;
        Socialtext::JSON::Proxy::Helper->ClearForGroup( $thing->group_id );
        if ($change ne 'update') { 
            require Socialtext::JobCreator;
            my $users = $thing->users;
            while (my $user = $users->next) {
                Socialtext::JobCreator->index_person( $user );
            }
            Socialtext::JobCreator->index_group( $thing );
        }
    }

    require Socialtext::Pluggable::Adapter;
    my $adapter = Socialtext::Pluggable::Adapter->new;
    $adapter->make_hub($actor);
    $adapter->hook('nlw.roles.changed' => [$self,$actor,$change,$thing,$role]);
}

sub _mk_method ($&) {
    my $func = shift;
    my $call = shift;
    __PACKAGE__->meta->add_method(
        $func => Moose::Meta::Method->wrap(
            $call,
            name         => $func,
            package_name => __PACKAGE__
        )
    );
}

for my $thing_name (qw(user group account)) {
    my $id_filter = {
        user    => PG_USER_FILTER,
        group   => PG_GROUP_FILTER,
        account => PG_ACCT_FILTER,
    }->{$thing_name};
    my $id_offset = {
        user    => USER_OFFSET,
        group   => GROUP_OFFSET,
        account => ACCT_OFFSET,
    }->{$thing_name};

    my $realize_thing = {
        user    => sub { Socialtext::User->new(user_id        => $_[0]) },
        group   => sub { Socialtext::Group->GetGroup(group_id => $_[0]) },
        account => sub { Socialtext::Account->new(account_id  => $_[0]) },
    }->{$thing_name};
    my $thing_checker = {
        user => sub {
            $_[0]
                && blessed($_[0])
                && ($_[0]->isa('Socialtext::User')
                or $_[0]->isa('Socialtext::UserMetadata'));
        },
        group =>
            sub { $_[0] && blessed($_[0]) && $_[0]->isa('Socialtext::Group') 
        },
        account => sub {
            $_[0] && blessed($_[0]) && $_[0]->isa('Socialtext::Account');
        },
    }->{$thing_name};

    my $from_set_filter = $thing_name eq 'user' ? q{
        AND from_set_id NOT IN (
            SELECT user_id FROM users WHERE is_profile_hidden)
            } : '';

    # grep: sub add_user sub add_group sub add_account
    _mk_method "add_$thing_name" => sub {
        my $self = shift;
        my %p = (@_==1) ? %{$_[0]} : @_;
 
        my $actor = $p{actor} || Socialtext::User->SystemUser;
        my $o = $p{$thing_name};
        confess "must supply a $thing_name" unless $thing_checker->($o);

        $self->add_role(
            actor  => $actor,
            object => $o,
            role   => $p{role},
        );

        $o->clear_cache if $o->can('clear_cache');
    };

    # grep: sub assign_role_to_user sub assign_role_to_group
    #       sub assign_role_to_account
    _mk_method "assign_role_to_$thing_name" => sub {
        my $self = shift;
        my %p = (@_==1) ? %{$_[0]} : @_;
 
        my $actor = $p{actor} || Socialtext::User->SystemUser;
        my $o = $p{$thing_name};
        confess "must supply a $thing_name" unless $thing_checker->($o);

        $self->assign_role(
            actor  => $actor,
            object => $o,
            role   => $p{role},
        );
        $o->clear_cache if $o->can('clear_cache');
    };

    # grep: sub remove_user sub remove_group sub remove_account
    _mk_method "remove_$thing_name" => sub {
        my $self = shift;
        my %p = (@_==1) ? %{$_[0]} : @_;
 
        my $actor = $p{actor} || Socialtext::User->SystemUser;
        my $o = $p{$thing_name};
        confess "must supply a $thing_name" unless $thing_checker->($o);

        my $removed;
        eval {
            $removed = $self->remove_role(
                actor  => $actor,
                object => $o,
                role   => $p{role},
            );
            $o->clear_cache if $o->can('clear_cache');
        };
        if ($@) {
            return if ($@ =~ /object not in this user.set/);
            die $@;
        }
        return $removed;
    };

    # grep: sub has_user sub has_group sub has_account
    _mk_method "has_$thing_name" => sub {
        my $self = shift;
        my $o = shift;
        my %p = (@_==1) ? %{$_[0]} : @_;
 
        confess "must supply a $thing_name" unless $thing_checker->($o);
        if ($p{direct}) {
            return $self->user_set->object_directly_connected($o);
        }
        else {
            return $self->user_set->object_connected($o);
        }
    };

    # grep: sub role_for_user sub role_for_group sub role_for_account
    _mk_method "role_for_$thing_name" => sub {
        my $self = shift;
        my $o = shift;
        my %p = (@_==1) ? %{$_[0]} : @_;
 
        confess "must supply a $thing_name" unless $thing_checker->($o);
        my @return;
        if ($p{direct}) {
            my $role_id = $self->user_set->direct_object_role($o);
            return $role_id if $p{ids_only};
            return Socialtext::Role->new(role_id => $role_id);
        }
        else {
            my @role_ids = $self->user_set->object_roles($o);
            if ($p{ids_only}) {
                return @role_ids if wantarray;
                return $role_ids[0];
            }
            else {
                # FIXME: this sort function is lame; it doesn't consider
                # permissions at all and it uses hash params pointlessly.
                my @roles =
                    map { Socialtext::Role->new(role_id => $_) } @role_ids;
                @roles = Socialtext::Role->SortByEffectiveness(roles=>\@roles);
                @roles = reverse @roles;
                return @roles if wantarray;
                return $roles[0];
            }
        }
    };

    # grep: sub user_has_role sub group_has_role sub account_has_role
    _mk_method "${thing_name}_has_role" => sub {
        my $self = shift;
        my %p = (@_==1) ? %{$_[0]} : @_;
 
        my $o = $p{$thing_name};
        confess "must supply a $thing_name" unless $thing_checker->($o);
        my $role = $p{role};
        confess "must supply a role"
            unless ($role && $role->isa('Socialtext::Role'));
        my $role_id = $role->role_id;

        my @role_ids = $self->user_set->object_roles($o);
        return any {$_ eq $role_id} @role_ids;
    };

    # grep: sub user_count sub group_count sub account_count
    _mk_method "${thing_name}_count" => sub {
        my $self = shift;
        my %p = (@_==1) ? %{$_[0]} : @_;
 
        my $t = time_scope("uset_${thing_name}_count");
        my $table = $p{direct} ? 'user_set_include' : 'user_set_path';
        my $filter = $p{show_hidden} ? '' : $from_set_filter;
        my $count = sql_singlevalue(qq{
            SELECT COUNT(DISTINCT(from_set_id))
            FROM $table
            WHERE from_set_id $id_filter
              AND into_set_id = ?
              $filter
        }, $self->user_set_id);
    };

    # grep: sub user_ids sub group_ids sub account_ids
    _mk_method "${thing_name}_ids" => sub {
        my $self = shift;
        my %p = (@_==1) ? %{$_[0]} : @_;
 
        my $t = time_scope("uset_${thing_name}_ids");
        my $table = $p{direct} ? 'user_set_include' : 'user_set_path';
        my $filter = $p{show_hidden} ? '' : $from_set_filter;
        my $order = $p{order} ? 'ORDER BY from_set_id' : '';
        my $sth = sql_execute(qq{
            SELECT DISTINCT from_set_id
            FROM $table
            WHERE from_set_id $id_filter
              AND into_set_id = ?
              $filter
              $order
        }, $self->user_set_id);
        return [map { $_->[0] - $id_offset } @{$sth->fetchall_arrayref || []}];
    };

    # grep: sub users sub groups sub accounts
    _mk_method "${thing_name}s" => sub {
        my $self = shift;
        my %p = (@_==1) ? %{$_[0]} : @_;

        my $t = time_scope("uset_${thing_name}s");
        my $meth = "${thing_name}_ids";
        my $ids = $self->$meth(%p);
        return Socialtext::MultiCursor->new(
            iterables => $ids,
            apply     => $realize_thing,
        );
    };

    # grep: sub user_roles sub group_roles sub account_roles
    _mk_method "${thing_name}_roles" => sub {
        my $self = shift;
        my %p = (@_==1) ? %{$_[0]} : @_;
 
        my $t = time_scope("uset_${thing_name}_roles");

        my $table = $p{direct} ? 'user_set_include' : 'user_set_path';
        my $role_filter = $p{role_id} ? "AND role_id = ?" : '';
        my $sth = sql_execute(qq{
            SELECT DISTINCT from_set_id, role_id
            FROM $table
            WHERE from_set_id $id_filter
              AND into_set_id = ?
              $role_filter
        }, $self->user_set_id, ($p{role_id} ? ($p{role_id}) : ()));
        my $rows = $sth->fetchall_arrayref();
        return Socialtext::MultiCursor->new(
            iterables => [$rows],
            apply     => sub {
                my $row = shift;
                return [
                    $realize_thing->($row->[0]),
                    Socialtext::Role->new(role_id => $row->[1]),
                ];
            },
        );
    };
}

sub role_count {
    my ($self, %p) = @_;
    my $table = $p{direct} ? 'user_set_include' : 'user_set_path';
    return sql_singlevalue(qq{
        SELECT COUNT(*)
          FROM $table
         WHERE role_id = ?
           AND into_set_id = ?
    }, $p{role}->role_id, $self->user_set_id);
}

sub _sorted_user_roles_order_by {
    my $ob = shift;
    my ($join,$sort,@cols);

    $join = q{
        JOIN users u USING (user_id)
    };

    if ($ob eq 'username') {
        push @cols, 'u.driver_username';
        $sort = 'u.driver_username';
    }
    elsif ($ob eq 'user_id') {
        $sort = 'u.user_id';
    }
    elsif ($ob =~ /^email(?:_address)?$/) {
        push @cols, 'u.email_address';
        $sort = 'u.email_address';
    }
    elsif ($ob =~ /^(?:display_|best_full_)?name$/) {
        push @cols, 'u.display_name';
        $sort = 'u.display_name';
    }
    elsif ($ob eq 'source') {
        push @cols, 'u.driver_key';
        $sort = 'u.driver_key';
    }
    elsif ($ob eq 'creation_datetime') {
        push @cols, 'meta.creation_datetime';
        $join = ' JOIN "UserMetadata" meta USING (user_id)';
        $sort = 'meta.creation_datetime';
    }
    elsif ($ob eq 'creator') {
        push @cols, 'creator.display_name AS creator';
        $join = q{
            JOIN "UserMetadata" meta USING (user_id)
            JOIN (SELECT user_id, display_name FROM users) creator
              ON meta.created_by_user_id = creator.user_id
        };
        $sort = 'creator';
    }
    elsif ($ob =~ /^(?:primary_)?account(?:_name)?$/) {
        push @cols, 'a.name AS account_name';
        $join = q{
            JOIN "UserMetadata" meta USING ( user_id )
            JOIN (SELECT account_id, name FROM "Account") a
              ON meta.primary_account_id = a.account_id
        };
        $sort = 'account_name';
    }
    else {
        croak "Cannot sort users in a container by '$ob'";
    }

    return ($join,$sort,@cols);
}

sub _sorted_user_roles_apply {
    my $row = shift;
    return {
        %$row,
        user => Socialtext::User->new(user_id => $row->{user_id}),
    };
}

{
    my $perspective = Socialtext::UserSetPerspective->new(
    cols => [ 'uxr.user_id AS user_id' ],
    subsort => "user_id ASC, role_id ASC",
    view => [
        from  => 'users',
        into  => 'container',
        alias => 'uxr',
    ],
    aggregates => {
        workspace_count => [ into => 'workspaces', using => 'user_id' ],
        group_count     => [ into => 'groups',     using => 'user_id' ],
        account_count   => [ into => 'accounts',   using => 'user_id' ],
    },
    order_by => \&_sorted_user_roles_order_by,
    apply    => \&_sorted_user_roles_apply,
    );

    sub sorted_user_roles {
        my ($self, %opts) = @_;
        my $t = time_scope('sorted_user_roles');
        require Socialtext::User;
        $opts{where} = ['uxr.user_set_id' => $self->user_set_id];
        $opts{thing} = $self;
        return $perspective->get_cursor(\%opts);
    }

    sub total_user_roles {
        my ($self, %opts) = @_;
        my $t = time_scope('total_user_roles');
        require Socialtext::Group;
        $opts{where} = ['uxr.user_set_id' => $self->user_set_id];
        $opts{thing} = $self;
        return $perspective->get_total(\%opts);
    }
}

sub _sorted_group_roles_order_by {
    my $ob = shift;
    my ($join,$sort,@cols);

    $join = q{
        JOIN groups g USING (user_set_id)
    };

    if ($ob =~ /^(?:display_|driver_group_)?name$/) {
        push @cols, 'g.driver_group_name AS display_name';
        $sort = 'display_name';
    }
    elsif ($ob eq 'group_id') {
        $sort = 'group_id';
    }
    elsif ($ob eq 'source') {
        push @cols, 'g.driver_key';
        $sort = 'g.driver_key';
    }
    elsif ($ob eq 'creation_datetime') {
        push @cols, 'g.creation_datetime';
        $sort = 'g.creation_datetime';
    }
    elsif ($ob eq 'creator') {
        push @cols, 'crtr.display_name AS creator';
        $join .= q{
            JOIN users crtr ON (g.created_by_user_id = crtr.user_id)
        };
        $sort = 'creator';
    }
    elsif ($ob =~ /^(?:primary_)?account(?:_name)?$/) {
        push @cols, 'a.name AS account_name';
        $join .= q{
            JOIN (SELECT account_id, name FROM "Account") a
              ON g.primary_account_id = a.account_id
        };
        $sort = 'account_name';
    }
    else {
        croak "Cannot sort groups in a container by '$ob'";
    }

    return ($join,$sort,@cols);
}

sub _sorted_group_roles_apply {
    my $row = shift;
    return {
        %$row,
        group => Socialtext::Group->GetGroup(group_id => $row->{group_id}),
    };
}

{
    my $perspective = Socialtext::UserSetPerspective->new(
    cols => [
        'user_set_id',
        'user_set_id - '.PG_GROUP_OFFSET.' AS group_id',
    ],
    subsort => "user_set_id ASC, role_id ASC",
    view => [
        from       => 'groups',
        from_alias => 'user_set_id',    # for JOINing convenience
        into       => 'container',
        alias      => 'gxr',
    ],
    aggregates => {
        workspace_count  => [ into => 'workspaces', using => 'user_set_id' ],
        supergroup_count => [ into => 'groups',     using => 'user_set_id' ],
        subgroup_count   => [ from => 'groups',     using => 'user_set_id' ],
        account_count    => [ into => 'accounts',   using => 'user_set_id' ],
        user_count       => [ from => 'users',      using => 'user_set_id' ],
    },
    order_by => \&_sorted_group_roles_order_by,
    apply    => \&_sorted_group_roles_apply,
    );
    sub sorted_group_roles {
        my ($self, %opts) = @_;
        my $t = time_scope('sorted_group_roles');
        require Socialtext::Group;
        $opts{where} = ['gxr.into_set_id' => $self->user_set_id];
        $opts{thing} = $self;
        return $perspective->get_cursor(\%opts);
    }

    sub total_group_roles {
        my ($self, %opts) = @_;
        my $t = time_scope('total_group_roles');
        require Socialtext::Group;
        $opts{where} = ['gxr.into_set_id' => $self->user_set_id];
        $opts{thing} = $self;
        return $perspective->get_total(\%opts);
    }
}

1;

__END__

=head1 NAME

Socialtext::UserSetContainer - Role for things containing UserSets

=head1 SYNOPSIS

    package MyContainer;
    use Moose;
    has 'user_set_id' => (..., isa => 'Int');
    with 'Socialtext::UserSetContainer';
    
    my $o = MyContainer->new(); # or w/e
    my $uset = $o->user_set;
    
    $o->is_plugin_enabled('people');
    $o->enable_plugin('people');
    $o->disable_plugin('people');
    
    # fails if a direct role already exists
    $o->add_role( # also in _user and _group flavours
        actor  => $user,
        object => $some_user_or_set,
        role   => Socialtext::Role->Member,
    );

    # force a role, pre-existing or not
    $o->assign_role( # also in _user and _group flavours
        actor  => $user,
        object => $some_user_or_set,
        role   => Socialtext::Role->Admin,
    );

    $o->remove_role( # also in _user and _group flavours
        actor  => $user,
        object => $some_user_or_set,
    );
    
    $o->has_user($user);
    $o->has_group($group);
    $o->has_user($user, direct => 1);
    $o->has_group($group, direct => 1);
    
    my @roles = $o->role_for_user($user);
    my $role = $o->role_for_user($user, direct => 1);
    my @roles = $o->role_for_group($group);
    my $role = $o->role_for_group($group, direct => 1);
    
    # Perspectives:
    my $mc = $o->sorted_group_roles(...); # groups in this container
    my $mc = $o->sorted_user_roles(...); # users in this container

=head1 DESCRIPTION

Adds a C<user_set> attribute to your class that automatically constructs the
L<Socialtext::UserSet> object for this container.

Requires that the base class has a C<user_set_id> accessor.

Instances maintain a weak reference to the owning object.

=cut
