package Socialtext::Authz;
# @COPYRIGHT@
use Moose;
use Socialtext::Timer qw/time_scope/;
use Socialtext::SQL qw/sql_singlevalue sql_execute/;
use Socialtext::Cache;
use Socialtext::User::Default::Users qw(:system-user);
use Socialtext::UserSet qw/:const/;
use List::MoreUtils qw/any/;
use namespace::clean -except => 'meta';

our $VERSION = '1.0';

sub user_has_permission_for_workspace {
    my $self = shift;
    my %p = (
        workspace  => undef,
        permission => undef,
        user       => undef,
        @_
    );

    # TODO: make this like the other two containers
    return 0 unless $p{workspace}->real;
    return $p{workspace}->permissions->user_can(
        user       => $p{user},
        permission => $p{permission},
    );
}

sub _user_has_permission_for_container {
    my $self = shift;
    my %p = (
        permission => undef,
        container  => undef,
        user       => undef,
        id_matrix  => undef,
        auth_user_must_share_account => undef,
        @_
    );

    return 1 if ($p{user}->username eq $SystemUsername);

    return 0 unless $p{permission};
    my $pname = ref($p{permission}) ? $p{permission}->name : $p{permission};

    my @role_ids = $p{container}->role_for_user($p{user}, ids_only => 1);
    if (!@role_ids) {
        if ($p{user}->is_guest) {
            push @role_ids, Socialtext::Role->Guest->role_id;
        }
        elsif ($p{auth_user_must_share_account}) {
            if ($self->user_sets_share_an_account($p{user},$p{container})) {
                push @role_ids, Socialtext::Role->AuthenticatedUser->role_id;
            }
            else {
                push @role_ids, Socialtext::Role->Guest->role_id;
            }
        }
        else {
            push @role_ids, Socialtext::Role->AuthenticatedUser->role_id;
        }
    }

    for my $role_id (@role_ids) {
        my $m = $p{id_matrix}->{$role_id} || [];
        return 1 if any {$_ eq $pname} @$m;
    }
    return 0;
}

sub _role_matrix_to_id_matrix {
    my $matrix = shift;
    my %id_matrix;
    for my $role (keys %$matrix) {
        my $role_id = Socialtext::Role->new(name => $role)->role_id;
        $id_matrix{$role_id} = $matrix->{$role};
    }
    return \%id_matrix;
}

# Hardcode the permissions matrix in here for now. When it comes time to
# actually implement a permissions backend, we'll have a definition for the
# default group permissions here.
{
    # Warning: permissions here must also exist in the ST::Permission module.
    my %permission_matrix = (
        private => {
            admin              => [qw/admin read edit/],
            member             => [qw/      read edit/],
            authenticated_user => [                   ],
            guest              => [                   ],
        },
        'self-join' => {
            admin              => [qw/admin read edit/],
            member             => [qw/      read edit/],
            authenticated_user => [qw/      read     /],
            guest              => [                   ],
        },
    );
    my %id_matrix;

    sub user_has_permission_for_group {
        my $self = shift;
        my %p = (
            permission    => undef,
            group         => undef,
            user          => undef,
            ignore_badmin => undef,
            @_
        );

        # XXX NOTE: business admins have special privileges for groups
        unless ($p{ignore_badmin}) {
            return 1 if $p{user}->is_business_admin;
        }

        my $pset = $p{group}->permission_set;
        $pset = 'private' unless exists $permission_matrix{$pset};

        $id_matrix{$pset} ||=
            _role_matrix_to_id_matrix($permission_matrix{$pset});
        $p{container} = delete $p{group},
        return $self->_user_has_permission_for_container(
            %p,
            id_matrix  => $id_matrix{$pset},
            auth_user_must_share_account => 1,
        );
    }
}

{
    # Warning: permissions here must also exist in the ST::Permission module.
    my %matrix = (
        admin              => [qw/admin read edit            /],
        member             => [qw/      read edit            /],
        impersonator       => [qw/      read edit impersonate/],
        authenticated_user => [                               ],
        guest              => [                               ],
    );
    my $id_matrix;

    sub user_has_permission_for_account {
        my $self = shift;
        my %p = (
            permission => undef,
            account    => undef,
            user       => undef,
            @_
        );

        $id_matrix ||= _role_matrix_to_id_matrix(\%matrix);
        $p{container} = delete $p{account},
        return $self->_user_has_permission_for_container(
            %p, id_matrix  => $id_matrix,
        );
    }
}

sub plugin_enabled_for_user {
    my $self = shift;
    my %p = @_;
    my $user = delete $p{user};
    return 1 if ($user->username eq $SystemUsername);
    return $self->plugin_enabled_for_user_set(
        %p,
        user_set => $user->user_set_id,
    );
}

# is a plugin available in some common account between two users
sub plugin_enabled_for_users {
    my $self = shift;
    my %p = @_;

    my $actor = delete $p{actor};
    my $user = delete $p{user};
    my $plugin_name = delete $p{plugin_name} || delete $p{plugin};
    return 0 unless ($actor && $user && $plugin_name);

    my $user_id = $user->user_id;
    my $actor_id = $actor->user_id;

    if ($actor_id eq $user_id) {
        return $self->plugin_enabled_for_user(
            user => $actor,
            plugin => $plugin_name
        );
    }

    return $self->plugin_enabled_for_user_sets(
        actor_id => $actor_id,
        user_set_id => $user_id,
        plugin => $plugin_name,
    );
}

sub plugin_enabled_for_user_sets {
    my $self        = shift;
    my %p           = @_;
    my $set_id_a    = $p{actor_id} || $p{set_id_a};
    my $set_id_b    = $p{user_set_id} || $p{set_id_b};
    my $plugin_name = $p{plugin_name} || $p{plugin};

    my $t = time_scope 'plugin_enabled_for_user_sets';

    my $cache = Socialtext::Cache->cache('authz_plugin');
    my $cache_key = "plugs_4_2_us3ts:$set_id_a\0$set_id_b\0$plugin_name";
    my $enabled = $cache->get($cache_key);
    return $enabled if defined $enabled;

    # This reads: find all user containers C with plugin P enabled that are
    # related to entity A, then check each user_set to see if entity B is also
    # in container C (*OR* B == C).
    my $sql = q{
        SELECT 1
        FROM user_set_path r1
        JOIN user_set_plugin p1 ON (r1.into_set_id = p1.user_set_id)
        WHERE p1.plugin = $1 AND r1.from_set_id = $2
          AND (
              r1.into_set_id = $3
                OR
              EXISTS (
                    SELECT 1
                    FROM user_set_path r2
                    WHERE r1.into_set_id = r2.into_set_id 
                      AND r2.from_set_id = $3
              )
          )
        LIMIT 1
    };

    $enabled = sql_singlevalue($sql, $plugin_name,
                               $set_id_a, $set_id_b) ? 1 : 0;

    $cache->set($cache_key, $enabled);
    return $enabled;
}

sub plugin_enabled_for_user_in_accounts {
    my $self = shift;
    my %p = @_;
    my $user = delete $p{user};
    my $accounts = delete $p{accounts};
    my $plugin_name = delete $p{plugin_name} || delete $p{plugin};

    if (!@$accounts) {
        Carp::cluck "what?! no accounts?!";
        return 0;
    }
    return 1 if ($user->username eq $SystemUsername);

    my $user_id = $user->user_id;

    my @account_ids = map { ref($_) ? $_->account_id : $_ } @$accounts;

    my $cache = Socialtext::Cache->cache('authz_plugin');
    my $cache_key = "user_acct_plug:$user_id\0" . join("\0", @account_ids);
    my $enabled_plugins = {};
    if ($enabled_plugins = $cache->get($cache_key)) {
        return $enabled_plugins->{$plugin_name} ? 1 : 0;
    }

    my $qs = join ',', map { '?' } @account_ids;
    my $sql = <<SQL;
        SELECT plugin
        FROM user_set_plugin plug
        JOIN "Account" a USING (user_set_id)
        JOIN user_set_path path ON (path.into_set_id = a.user_set_id)
        WHERE path.from_set_id = ? AND account_id IN ($qs)
SQL

    my $sth = sql_execute($sql, $user_id, @account_ids);
    while (my $row = $sth->fetchrow_arrayref) {
        $enabled_plugins->{$row->[0]} = 1;
    }

    $cache->set($cache_key, $enabled_plugins);
    return $enabled_plugins->{$plugin_name} ? 1 : 0;
}

sub plugin_enabled_for_user_in_account {
    my $self = shift;
    my %p = @_;
    return $self->plugin_enabled_for_user_in_accounts(
        accounts => [ delete $p{account} ], %p
    );
}

sub plugins_enabled_for_user_set {
    my $self = shift;
    my %p = @_;
    my $t = time_scope 'plugins_for_uset';
    my $user_set = delete $p{user_set};
    my $direct   = delete $p{direct} || 0;
    my $user_set_id = ref($user_set) ? $user_set->user_set_id : $user_set;

    my $cache = Socialtext::Cache->cache('authz_plugin');
    my $cache_key = "plugs_4_uset:$user_set_id\0plugins\0direct=$direct";
    my $plugins = $cache->get($cache_key);
    return @$plugins if defined $plugins;

    my $table = $direct ? 'user_set_plugin' : 'user_set_plugin_tc';
    my $sql = <<EOT;
        SELECT DISTINCT plugin
        FROM $table
        WHERE user_set_id = ?
EOT

    my $sth = sql_execute($sql, $user_set_id);
    $plugins = [ map { $_->[0] } @{$sth->fetchall_arrayref} ];

    $cache->set($cache_key, $plugins);
    return @$plugins; # return copy
}

sub plugin_enabled_for_user_set {
    my $self = shift;
    my %p = @_;
    my $plugin_name = delete $p{plugin_name} || delete $p{plugin};
    my @plugins = $self->plugins_enabled_for_user_set(%p);
    return (any { $_ eq $plugin_name } @plugins) ? 1 : 0;
}

sub user_sets_share_an_account {
    my $self = shift;
    my $set_a = shift;
    my $set_b = shift;
    die "must supply two objects with user_set_id accessors"
        unless (blessed($set_a) && $set_a->can('user_set_id') and 
                blessed($set_b) && $set_b->can('user_set_id'));

    my $sql = q{
        SELECT 1
          FROM user_set_path path_a
         WHERE from_set_id = $1 AND into_set_id }. PG_ACCT_FILTER .q{
           AND EXISTS (
               SELECT 1
                 FROM user_set_path path_b
                WHERE from_set_id = $2
                  AND path_b.into_set_id = path_a.into_set_id
           )
        LIMIT 1
    };
    my $sth = sql_execute($sql, $set_a->user_set_id, $set_b->user_set_id);
    return $sth->rows == 1;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;
__END__

=head1 NAME

Socialtext::Authz - API for permissions checks

=head1 SYNOPSIS

  use Socialtext::Authz;

  my $authz = Socialtext::Authz->new;
  $authz->user_has_permission_for_workspace(
      user       => $user,
      permission => $permission,
      workspace  => $workspace,
  );

=head1 DESCRIPTION

This class provides an API for checking if a user has specific permissions.
While this can be checked by using the various object's class's API, the goal
of this layer is to provide an abstraction that can be used to implement
authorization outside of the DBMS, for example by using LDAP.

=head1 METHODS

This class provides the following methods:

=head2 Socialtext::Authz->new()

Returns a new C<Socialtext::Authz> object.

=head2 $authz->user_has_permission_for_workspace(PARAMS)

Returns a boolean indicating whether the user has the specified
permission for the given workspace.

Requires the following PARAMS:

=over 8

=item * user - a user object

=item * permission - a permission object

=item * workspace - a workspace object

=back

=head2 $authz->plugin_enabled_for_user(PARAMS)

Returns a boolean indicating whether the user has the ability to use a plugin through one of his/her account memberships.

When checking if two users can both use a plugin, see C<< $authz->plugin_enabled_for_users(PARAMS) >>.

Requires the following PARAMS:

=over 8

=item * user - a user object

=item * plugin - the name of the plugin to check (or plugin_name)

=back

=head2 $authz->plugin_enabled_for_users(PARAMS)

Returns a boolean indicating if a plugin can be used for some interaction between two users.  Currently, this is implemented as a check to see if both users share any accounts where the plugin is enabled.  In the future, this may be expanded out to use an access-control mechanism that may or may not use user-specified access assertions.

Requires the following PARAMS:

=over 8

=item * actor - a user object, the "subject" in an interaction.

=item * user - another user object, the "object" in an interaction.

=item * plugin - the name of the plugin to check (or plugin_name)

=back

Typical usage might be that actor is the current logged-in user where the actor wishes to interact with a user the context of a plugin.  To use Socialtext People as an example, actor wishes to view a user's profile: this method would return true if actor is allowed to interact with that user's profile.

=head2 $authz->plugin_enabled_for_user_in_account(PARAMS)

Returns a boolean indicating whether a user is permitted to use a plugin within the context of an account.  To use Socialtext People as an example, say the user wants to view a directory listing for an account: this method would return true if the user was able to view listings for this account.

Requires the following PARAMS:

=over 8

=item * user - a user object

=item * account - a C<Socialtext::Account> object

=item * plugin - the name of the plugin to check (or plugin_name)

=back

=head1 AUTHOR

Socialtext, C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc. All Rights Reserved.

=cut
