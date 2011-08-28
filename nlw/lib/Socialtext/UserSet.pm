package Socialtext::UserSet;
# @COPYRIGHT@
use Moose;
use Socialtext::SQL qw/get_dbh :txn sql_ensure_temp/;
use Socialtext::Timer qw/time_scope/;
use List::MoreUtils qw/part/;
use Memoize;
use Guard;
use namespace::clean -except => 'meta';

our $VERSION = 1.0;
extends 'Exporter';

has 'trace' => (is => 'rw', isa => 'Bool', default => undef);

has 'owner_id' => (is => 'rw', isa => 'Int');
has 'owner' => (
    is       => 'rw',
# would really like this to work, but it doesn't.
#     isa      => 'Socialtext::Workspace|Socialtext::Account|Socialtext::Group',
    isa => 'Object',
    weak_ref => 1
);

use constant USER_OFFSET    => 0;
use constant USER_END       => 0x10000000;
use constant PG_USER_OFFSET => 0;
use constant PG_USER_FILTER => " <= x'10000000'::int";

use constant GROUP_OFFSET    => 0x10000000;
use constant GROUP_END       => 0x20000000;
use constant PG_GROUP_OFFSET => "x'10000000'::int";
use constant PG_GROUP_FILTER => " BETWEEN x'10000001'::int AND x'20000000'::int";

use constant WKSP_OFFSET    => 0x20000000;
use constant WKSP_END       => 0x30000000;
use constant PG_WKSP_OFFSET => "x'20000000'::int";
use constant PG_WKSP_FILTER => " BETWEEN x'20000001'::int AND x'30000000'::int";

use constant ACCT_OFFSET    => 0x30000000;
use constant ACCT_END       => 0x40000000;
use constant PG_ACCT_OFFSET => "x'30000000'::int";
use constant PG_ACCT_FILTER => " > x'30000000'::int";

our @all_consts = qw(
    USER_OFFSET USER_END PG_USER_OFFSET PG_USER_FILTER
    GROUP_OFFSET GROUP_END PG_GROUP_OFFSET PG_GROUP_FILTER
    WKSP_OFFSET WKSP_END PG_WKSP_OFFSET PG_WKSP_FILTER
    ACCT_OFFSET ACCT_END PG_ACCT_OFFSET PG_ACCT_FILTER
);
our @EXPORT = ();
our @EXPORT_OK = (@all_consts,'user_set_id_partition');
our %EXPORT_TAGS = (
    'all' => [@EXPORT_OK,'user_set_id_partition'],
    'const' => \@all_consts,
);

# defined below:
sub _object_role_method ($);
sub _object_owner_method ($);

=head1 NAME

Socialtext::UserSet - Nested collections of users

=head1 SYNOPSIS

  my $us = Socialtext::UserSet->new;
  # include user-set 5 into user-set 6 with a member role
  $us->add_role(5,6,$member->role_id);
  ok $us->connected(5,6);
  ok $us->has_role(5,6,$member->role_id);

=head1 DESCRIPTION

Maintains a graph of memberships and its transitive closure to give a
fast-lookup table for role resolution.

A user-set is an abstraction for users, groups, workspaces and accounts.  With
the exception of users, user-sets can be nested in other user-sets with an
explicit role.  A user-set cannot be nested into itself.

A user is included in other user-sets using the user's ID number. We number
all other user-set containers with IDs that don't overlap with users.

=head1 FUNCTIONS

=over 4

=item user_set_id_partition ($ids)

Given an arrayref of user_set_ids, return the partitioned set, mapped into user, group, workspace and account IDs.

  my ($users,$groups,$wses,$accts) = user_set_id_partition($ids);

=cut

sub user_set_id_partition {
    my $ids = shift;
    my ($users,$groups,$wses,$accts) = part {
        # each id range is 0x10000000 wide (28 bits over)
        $_ >> 28 & 0xf
    } @$ids;

    return [ map { $_ - USER_OFFSET  } @{ $users  || [] } ],
           [ map { $_ - GROUP_OFFSET } @{ $groups || [] } ],
           [ map { $_ - WKSP_OFFSET  } @{ $wses   || [] } ],
           [ map { $_ - ACCT_OFFSET  } @{ $accts  || [] } ];
}

=back

=head1 METHODS

For the C<_object_role> variants below, the C<$y> parameter is replaced by
C<$self->owner_id>.

=over 4

=item add_role ($x,$y[,$role_id])

=item add_object_role ($x,[,$role_id])

Add this edge to the graph. Default C<$role_id> is 'member'.

Throws an exception if an edge is already present.

=cut

_object_role_method 'add_object_role';
around 'add_role' => \&_modify_wrapper;
sub add_role {
    my ($self, $dbh, $x, $y, $role_id) = @_;
    confess "can't add things to users ($x to $y)" if ($y <= USER_END);

    $role_id ||= 'member';
    _resolve_role(\$role_id);

    $self->_insert($dbh, $x, $y, $role_id);
}

=item remove_role ($x,$y)

=item remove_object_role ($x)

Remove this edge from the graph. 

Throws an exception if this edge doesn't exist.

=cut

around 'remove_role' => \&_modify_wrapper;
_object_role_method 'remove_object_role';
sub remove_role {
    my ($self, $dbh, $x, $y) = @_;
    $self->_delete($dbh, $x, $y);
}

=item update_role ($x,$y,$role_id)

=item update_object_role ($x,$role_id)

Update the role_id attached to this edge.  All paths containing this edge that need updating will also get updated.

Throws an exception if the edge doesn't exist.

=cut

around 'update_role' => \&_modify_wrapper;
_object_role_method 'update_object_role';
sub update_role {
    my ($self, $dbh, $x, $y, $role_id) = @_;
    die "role_id is required" unless $role_id;
    confess "can't add things to users ($x to $y)" if ($y <= USER_END);

    $self->_delete($dbh, $x, $y);
    $self->_insert($dbh, $x, $y, $role_id);
}

=item remove_set ($n,%opts)

Removes all edges/roles involving node $n. Calls the C<purge_user_set()>
stored procedure to remove references to this user set (as if an C<ON DELETE
CASCADE> trigger was taking effect).

If the C<< roles_only => 1 >> option is present, only roles are purged;
the C<purge_user_set()> stored procedure is B<not> called.

=cut

around 'remove_set' => \&_modify_wrapper;
sub remove_set {
    my ($self, $dbh, $n, %opts) = @_;

    my $rows = $dbh->do(q{
        DELETE FROM user_set_include
        WHERE from_set_id = $1 OR into_set_id = $1
    }, {}, $n);
    confess "node $n doesn't exist" unless $rows>0;

    if ($opts{roles_only}) {
        $dbh->do(q{
            DELETE FROM user_set_path
            WHERE user_set_path_id IN (
                SELECT user_set_path_id
                  FROM user_set_path_component
                 WHERE user_set_id = ?
            )
        }, {}, $n);
    }
    else {
        $dbh->do(q{SELECT purge_user_set($1)}, {}, $n);
    }
    return;
}

=item connected ($x,$y)

=item object_connected ($x)

Asks "is $x connected to $y through at least one path?" which is the same
question as "is $x contained somehow in $y?"

=cut

around 'connected' => \&_query_wrapper;
_object_role_method 'object_connected';
sub connected {
    my $self = shift;
    return $self->_connected('user_set_path',@_);
}

=item directly_connected ($x,$y)

=item object_directly_connected ($x)

Asks "is $x directly connected to $y?" which is the same question as "is $x
directly contained in $y"

=cut

around 'directly_connected' => \&_query_wrapper;
_object_role_method 'object_directly_connected';
sub directly_connected {
    my $self = shift;
    return $self->_connected('user_set_include',@_);
}

sub _connected {
    confess "requires x and y parameters" unless (@_ >= 5);
    my ($self, $table, $dbh, $x, $y) = @_;

    my ($has_direct_role) = $dbh->selectrow_array(q{
        SELECT 1
        FROM }.$table.q{
        WHERE from_set_id = $1 AND into_set_id = $2
        LIMIT 1
    }, {}, $x, $y);
    return $has_direct_role ? 1 : 0;
}

=item has_role ($x,$y,$role_id)

Asks "is $x connected to $y where the effective role_id is $role_id?"

=cut

around 'has_role' => \&_query_wrapper;
sub has_role {
    my $self = shift;
    return $self->_has_role('user_set_path',@_);
}

=item has_direct_role ($x,$y,$role_id)

=item has_direct_object_role ($x,$role_id)

Asks "is $x connected to $y where the immediate/direct role_id is $role_id?"

=cut

around 'has_direct_role' => \&_query_wrapper;
_object_role_method 'has_direct_object_role';
sub has_direct_role {
    my $self = shift;
    return $self->_has_role('user_set_include',@_);
}

sub _has_role {
    confess "requires x and y parameters" unless (@_ >= 5);
    my ($self, $table, $dbh, $x, $y, $role_id) = @_;
    confess "role_id is required" unless $role_id;

    _resolve_role(\$role_id);

    my ($has_direct_role) = $dbh->selectrow_array(q{
        SELECT 1
        FROM }.$table.q{
        WHERE from_set_id = $1 AND into_set_id = $2 AND role_id = $3
        LIMIT 1
    }, {}, $x, $y, $role_id);
    return $has_direct_role ? 1 : undef;
}

=item has_plugin ($n,$plugin)

=item object_has_plugin ($plugin)

Asks "does $n have OR is $n included in a set that has $plugin enabled?"

=cut

around 'has_plugin' => \&_query_wrapper;
_object_owner_method 'object_has_plugin';
sub has_plugin {
    my ($self, $dbh, $n, $plugin) = @_;
    if (@_ == 3) {
        $plugin = $n;
        $n = $self->owner_id;
    }
    confess "plugin is required" unless $plugin;
    my ($has_plugin) = $dbh->selectrow_array(q{
        SELECT 1
        FROM user_set_plugin_tc
        WHERE user_set_id = $1 AND plugin = $2
        LIMIT 1
    }, {}, $n, $plugin);
    return $has_plugin ? 1 : undef;
}

=item roles ($x,$y)

=item object_roles ($x)

Get the list of distinct, possibly indirect role_ids for $x in $y.  Returns an
empty list if none.

=cut

around 'roles' => \&_query_wrapper;
_object_role_method 'object_roles';
sub roles {
    my ($self, $dbh, $x, $y) = @_;
    my $roles = $dbh->selectcol_arrayref(q{
        SELECT DISTINCT role_id
        FROM user_set_path
        WHERE from_set_id = $1 AND into_set_id = $2
        ORDER BY role_id ASC
    }, {}, $x, $y);
    return @{$roles || []};
}

=item direct_role ($x,$y)

=item direct_object_role ($x)

Get the direct role_id for $x in $y.  Returns undef if none.

=cut

around 'direct_role' => \&_query_wrapper;
_object_role_method 'direct_object_role';
sub direct_role {
    my ($self, $dbh, $x, $y) = @_;
    my ($role) = $dbh->selectrow_array(q{
        SELECT role_id
        FROM user_set_include
        WHERE from_set_id = $1 AND into_set_id = $2
    }, {}, $x, $y);
    return $role;
}

=item AggregateSQL(into => 'groups'|'workspaces'|'accounts', ...)

=item AggregateSQL(from => 'users'|'groups'|'workspaces', ...)

Generates SQL C<LEFT JOIN> query segments for counting some user_set in
relation to some other user_set.  See UserSet-query.t for options.

Returns a C<($col, $query)> pair, where $col is a string that identifies the
aggregation result for use as an item in a select statement (perhaps by
appending " AS foo" to label it) and $query is a query fragment of the form
C<LEFT JOIN (...) bar USING (user_set_id)>.

A C<from> or C<into> parameter is mandatory. Specifying from accounts (which
can't be included in anything) and into users (which can't contain anything)
will throw exceptions.

To change the column in the USING clause, pass in C<< using => 'my_id' >>.

To specify the sub-select alias, pass in C<< alias => 'q' >>.

To use a different aggregate function, use C<< agg => 'array_accum' >>.

To limit the result to direct relationships only, use C<< direct => 1 >>.

Example for C<< from => 'users' >>

        LEFT JOIN (
            SELECT into_set_id AS user_set_id,
                   COUNT(DISTINCT from_set_id) AS agg
              FROM user_set_path
             WHERE from_set_id <= x'10000000'::int
             GROUP BY user_set_id
        ) from_users_count USING (user_set_id)

=cut

my %plural_to_filter = (
    accounts => PG_ACCT_FILTER,
    groups => PG_GROUP_FILTER,
    users => PG_USER_FILTER,
    workspaces => PG_WKSP_FILTER,
    all => ' IS NOT NULL',
);

sub _aggregate_sql_normalizer {
    my $ignore = shift;
    my %p = @_;
    $p{direct} ||= 0;
    $p{agg} ||= 'COUNT';
    $p{using} ||= 'user_set_id';
    $p{alias} ||= '';
    return join("\t", map {$_=>$p{$_}} keys %p);
}

memoize 'AggregateSQL', NORMALIZER => '_aggregate_sql_normalizer';
sub AggregateSQL {
    my ($class,%p) = @_;

    my $query;

    my $alias = $p{alias};
    my $table = $p{direct} ? 'user_set_include' : 'user_set_path';
    my $agg = $p{agg} || 'COUNT';
    my $using = $p{using} || 'user_set_id';
    my ($this,$that);

    if (my $into = $p{into}) {
        $alias ||= "into_${into}_".lc $agg;
        die "can't query into users" if $into eq 'users';
        my $filter = $plural_to_filter{$into};
        die "no such filter $into" unless $filter;

        $query = qq{
            LEFT JOIN (
                SELECT from_set_id AS $using,
                       $agg(DISTINCT into_set_id) AS agg
                  FROM $table
                 WHERE into_set_id $filter
                 GROUP BY $using
            ) $alias USING ($using)
        };
    }
    elsif (my $from = $p{from}) {
        $alias ||= "from_${from}_".lc $agg;
        die "can't query from accounts" if $from eq 'accounts';
        my $filter = $plural_to_filter{$from};
        die "no such filter $from" unless $filter;

        $query = qq{
            LEFT JOIN (
                SELECT into_set_id AS $using,
                       $agg(DISTINCT from_set_id) AS agg
                  FROM $table
                 WHERE from_set_id $filter
                 GROUP BY $using
            ) $alias USING ($using)
        };
    }
    else {
        die "need to supply 'from' or 'into' relationship";
    }

    my $column = ($agg eq 'COUNT') ? "COALESCE($alias.agg,0)" : "$alias.agg";
    return ($column,$query);
}

=item RoleViewSQL(into => ..., from => ..., ...)

Generates a sub-select "view" for the named user sets.  Set names are
"users","groups","workspaces", and "accounts".  From accounts and into users
makes no sense and will throw an exception.

Passing in C<< from => 'users' >> will make the from_alias default to
C<user_id>, since user_set_ids will be equivalent to user_ids.  This is
convenient for joining.

To specify the sub-select alias, pass in C<< alias => 'q' >>.

To use a different from or into column alias, pass in C<< from_alias =>
'group_set_id' >>.

To limit the result to direct relationships only, use C<< direct => 1 >>.
Otherwise, both direct and indirect roles will be returned.

To aggregate all roles for a relationship into an array, pass in 
C<< mux_roles => 1 >>.  The roles will be unique and sorted ascending by ID.

To omit the roles, and just return the distinct relationships, pass in
C<< omit_roles => 1 >>.  Cannot be combined with mux_roles.

To exclude paths that contain an account (e.g. an all-users-workspace
pattern), pass in C<< exclude_acct_paths => 1 >>.  Shouldn't be combined with
C<< direct => 1 >>.

=cut

sub _role_view_sql_normalizer {
    my $ignore = shift;
    my %p = @_;
    $p{direct} ||= 0;
    $p{mux_roles} ||= 0;
    $p{omit_roles} ||= 0;
    $p{exclude_acct_paths} ||= 0;
    return join("\t", map {$_=>$p{$_}} keys %p);
}

memoize 'RoleViewSQL', NORMALIZER => '_role_view_sql_normalizer';
sub RoleViewSQL {
    my ($class,%p) = @_;
    my $from = delete $p{from} or die "must supply from";
    my $into = delete $p{into} or die "must supply into";
    my $from_alias = delete $p{from_alias};
    my $into_alias = delete $p{into_alias};
    my $table = (delete $p{direct}) ? 'user_set_include' : 'user_set_path';
    my $alias = (delete $p{alias}) || "${from}_${into}_roles";
    my $mux_roles = (delete $p{mux_roles}) || 0;
    my $omit_roles = (delete $p{omit_roles}) || 0;
    my $exclude_acct_paths = (delete $p{exclude_acct_paths}) || 0;

    die "users makes no sense as 'into'" if $into eq 'users';
    die "accounts makes no sense as 'from'" if $from eq 'accounts';
    die "unrecognized RoleViewSQL option: ".(keys %p)[0]
        if keys %p;
    die "can't omit and mux roles" if ($mux_roles && $omit_roles);

    my @filter;

    if (!$from_alias and !$into_alias and $from eq 'users') {
        $from_alias = 'user_id';
        $into_alias = 'user_set_id';
    }

    $from_alias ||= 'from_set_id';
    if ($plural_to_filter{$from}) {
        push @filter, 'from_set_id'.$plural_to_filter{$from};
    }

    $into_alias ||= 'into_set_id';
    if ($plural_to_filter{$into}) {
        push @filter, 'into_set_id'.$plural_to_filter{$into};
    }

    if ($exclude_acct_paths && $table eq 'user_set_path') {
        push @filter, qq{
            NOT EXISTS (
                SELECT 1
                  FROM user_set_path_component uspc
                 WHERE uspc.user_set_path_id = user_set_path.user_set_path_id
                   AND uspc.user_set_id }.PG_ACCT_FILTER.q{
            )};
    }

    my $filter = join(' AND ',@filter);
    if ($mux_roles) {
        my $group = 'from_set_id, into_set_id';
        if (@filter == 1 && $filter[0] =~ /^into/) {
            $group = 'into_set_id, from_set_id';
        }
        return qq{
            (
                SELECT
                    from_set_id AS $from_alias,
                    into_set_id AS $into_alias,
                    uniq(sort(array_accum(role_id)::int[])) AS role_ids
                  FROM $table
                 WHERE $filter
                 GROUP BY $group
            ) $alias
        };
    }
    else {
        return qq{
            (
                SELECT DISTINCT
                    from_set_id AS $from_alias,
                    into_set_id AS $into_alias
                  FROM $table
                 WHERE $filter
            ) $alias
        } if $omit_roles;

        return qq{
            (
                SELECT DISTINCT
                    from_set_id AS $from_alias,
                    into_set_id AS $into_alias,
                    role_id
                  FROM $table
                 WHERE $filter
            ) $alias
        };
    }
}

=back

=cut

###################################################

# used in a migration:
sub _create_insert_temp {
    my ($self, $dbh, $bulk) = @_;
    sql_ensure_temp(to_copy => q{
        new_start int,
        new_end int,
        new_vlist int[]
    });
}

sub _insert {
    my ($self, $dbh, $x, $y, $role_id, $bulk) = @_;

    my $t = time_scope('uset_insert');

    if ($bulk) {
        $dbh->do("TRUNCATE to_copy");
    }
    else {
        $self->_create_insert_temp($dbh);
    }

    my $prep_method = $bulk ? 'prepare_cached' : 'prepare';

    $dbh->do(q{
        INSERT INTO user_set_include
        (from_set_id,into_set_id,role_id) VALUES ($1,$2,$3)
    }, {}, $x, $y, $role_id);

    # Create the union of
    # 1) a path for (x,y)
    # 2) paths that start with y; prepend (x,y) to these paths
    # 3) paths that end with x; append (x,y) to these paths
    # 4) pairs of paths joined by (x,y); paths that can be merged
    #
    # There should be no duplicated vertices in the vertex list for each path.
    # The exception is for "reflexive" paths in which case we allow for one
    # and only one duplicate. This has the effect of "pruning" the maintenance
    # table to reduce the number of redundant paths that were generated.
    # This is implemented as the outer WHERE clause in the query below.

    my $compute_sth = $dbh->$prep_method(q{
        INSERT INTO to_copy
        SELECT DISTINCT * FROM (
            SELECT DISTINCT
                $1::int AS new_start,
                $2::int AS new_end,
                $5::int[] AS new_vlist

            UNION ALL

            SELECT DISTINCT
                $1::integer AS new_start,
                into_set_id AS new_end,
                $3::int[] + vlist AS new_vlist
            FROM user_set_path
            WHERE from_set_id = $2::integer

            UNION ALL

            SELECT DISTINCT
                from_set_id AS new_start,
                $2::integer AS new_end,
                vlist + $4::int[] AS new_vlist
            FROM user_set_path
            WHERE into_set_id = $1::integer

            UNION ALL

            SELECT DISTINCT
                before.from_set_id AS new_start,
                after.into_set_id AS new_end,
                before.vlist + after.vlist AS new_vlist
            FROM user_set_path before, user_set_path after
            WHERE before.into_set_id = $1 AND after.from_set_id = $2
        ) new_paths
        WHERE (
            new_start = new_end AND
            icount(new_vlist) - 1  = icount(uniq(sort(new_vlist)))
        )
        OR (
            icount(new_vlist) = icount(uniq(sort(new_vlist)))
        )
    }, {});
    $compute_sth->execute($x, $y, "{$x}", "{$y}", "{$x,$y}");

    my $finalize_sth = $dbh->$prep_method(q{
        INSERT INTO user_set_path
        SELECT
            nextval('user_set_path_id_seq') AS user_set_path_id,
            new_start AS from_set_id,
            new_end AS into_set_id,
            usi.role_id AS role_id,
            new_vlist AS vlist
        FROM to_copy cpy
        JOIN user_set_include usi ON (
            usi.into_set_id = cpy.new_end AND
            usi.from_set_id = cpy.new_vlist[icount(cpy.new_vlist)-1]
        )
    });
    $finalize_sth->execute();

    return;
}

sub _delete {
    my ($self, $dbh, $x, $y) = @_;

    my $rows = $dbh->do(q{
        DELETE FROM user_set_include
        WHERE from_set_id = $1 AND into_set_id = $2
    }, {}, $x, $y);

    die "edge $x,$y does not exist" unless $rows>0;

    # delete paths that contain this edge
    $dbh->do(q{
        DELETE FROM user_set_path
        WHERE user_set_path_id IN (
            SELECT user_set_path_id
              FROM user_set_path_component c1
              JOIN user_set_path_component c2 USING (user_set_path_id)
             WHERE c1.user_set_id = $1
               AND c2.user_set_id = $2
        )
        AND vlist[idx(vlist,$1)+1] = $2
    }, {}, $x,$y);

    return $rows+0;
}

sub _modify_wrapper {
    my $code = shift;
    my $self = shift;
    my @args = @_;
    return sql_txn {
        my $t = time_scope('uset_update');
        my $dbh = get_dbh();
        local $dbh->{RaiseError} = 1;
        local $dbh->{TraceLevel} = ($self->trace) ? 3 : $dbh->{TraceLevel};
        $dbh->do(q{
            LOCK user_set_include,user_set_path IN SHARE ROW EXCLUSIVE MODE
        });
        $self->$code($dbh, @args);
    };
}

sub _query_wrapper {
    my $code = shift;
    my $self = shift;

    my $t = time_scope('uset_query');

    my $dbh = get_dbh();
    local $dbh->{RaiseError} = 1;
    local $dbh->{TraceLevel} = ($self->trace) ? 3 : $dbh->{TraceLevel};
    return $self->$code($dbh, @_);
}

sub _object_role_method ($) {
    my $func = shift;
    (my $call = $func) =~ s/object_//;
    __PACKAGE__->meta->add_method(
        $func => Moose::Meta::Method->wrap(
            sub {
                my ($self, $obj, $role_id) = @_;
                _resolve_role(\$role_id);
                die "must have owner_id" unless $self->owner_id;
                $self->$call($obj->user_set_id => $self->owner_id, $role_id);
            },
            name         => $func,
            package_name => __PACKAGE__
        )
    );
}

sub _object_owner_method ($) {
    my $func = shift;
    (my $call = $func) =~ s/object_//;
    __PACKAGE__->meta->add_method(
        $func => Moose::Meta::Method->wrap(
            sub {
                my ($self) = @_;
                die "must have owner_id" unless $self->owner_id;
                $self->$call($self->owner_id);
            },
            name         => $func,
            package_name => __PACKAGE__
        )
    );
}

sub _resolve_role {
    my $role = shift;
    if (blessed($$role)) {
        $$role = $$role->role_id;
    }
    elsif (defined $$role and $$role =~ /\D/) {
        $$role = Socialtext::Role->new(name => $$role)->role_id;
    }
}

__PACKAGE__->meta->make_immutable();
1;
