#!perl
# @COPYRIGHT@
use warnings;
use strict;

use Test::More tests => 23;
use Test::Differences;
use Test::Socialtext::Fatal;
use Socialtext::UserSet;

sub squash ($) {
    my $s = shift;
    $s =~ s/[ \t]+/ /mg;
    return $s;
}

agg_basics: {
    my ($col,$query) = Socialtext::UserSet->AggregateSQL(
        from => 'users',
    );
    is $col, 'COALESCE(from_users_count.agg,0)';
    eq_or_diff squash($query), squash(q{
        LEFT JOIN (
            SELECT into_set_id AS user_set_id,
                   COUNT(DISTINCT from_set_id) AS agg
              FROM user_set_path
             WHERE from_set_id <= x'10000000'::int
             GROUP BY user_set_id
        ) from_users_count USING (user_set_id)
    });

    ($col,$query) = Socialtext::UserSet->AggregateSQL(
        into => 'workspaces',
    );
    is $col, 'COALESCE(into_workspaces_count.agg,0)';
    eq_or_diff squash($query), squash(q{
        LEFT JOIN (
            SELECT from_set_id AS user_set_id,
                   COUNT(DISTINCT into_set_id) AS agg
              FROM user_set_path
             WHERE into_set_id BETWEEN x'20000001'::int AND x'30000000'::int
             GROUP BY user_set_id
        ) into_workspaces_count USING (user_set_id)
    });
}

different_agg: {
    my ($col,$query) = Socialtext::UserSet->AggregateSQL(
        into => 'accounts',
        agg => 'array_accum'
    );
    is $col, 'into_accounts_array_accum.agg';
    eq_or_diff squash($query), squash(q{
        LEFT JOIN (
            SELECT from_set_id AS user_set_id,
                   array_accum(DISTINCT into_set_id) AS agg
              FROM user_set_path
             WHERE into_set_id > x'30000000'::int
             GROUP BY user_set_id
        ) into_accounts_array_accum USING (user_set_id)
    });

    ($col,$query) = Socialtext::UserSet->AggregateSQL(
        into => 'groups',
        agg => 'AVG'
    );
    is $col, 'into_groups_avg.agg';
    eq_or_diff squash($query), squash(q{
        LEFT JOIN (
            SELECT from_set_id AS user_set_id,
                   AVG(DISTINCT into_set_id) AS agg
              FROM user_set_path
             WHERE into_set_id BETWEEN x'10000001'::int AND x'20000000'::int
             GROUP BY user_set_id
        ) into_groups_avg USING (user_set_id)
    });
}

agg_using: {
    my ($col,$query) = Socialtext::UserSet->AggregateSQL(
        into => 'all',
        using => 'my_foo_id',
    );
    is $col, 'COALESCE(into_all_count.agg,0)';
    eq_or_diff squash($query), squash(q{
        LEFT JOIN (
            SELECT from_set_id AS my_foo_id,
                   COUNT(DISTINCT into_set_id) AS agg
              FROM user_set_path
             WHERE into_set_id IS NOT NULL
             GROUP BY my_foo_id
        ) into_all_count USING (my_foo_id)
    });
}

agg_direct_also_label: {
    my ($col,$query) = Socialtext::UserSet->AggregateSQL(
        into => 'workspaces',
        direct => 1,
    );
    is $col, 'COALESCE(into_workspaces_count.agg,0)';
    eq_or_diff squash($query), squash(q{
        LEFT JOIN (
            SELECT from_set_id AS user_set_id,
                   COUNT(DISTINCT into_set_id) AS agg
              FROM user_set_include
             WHERE into_set_id BETWEEN x'20000001'::int AND x'30000000'::int
             GROUP BY user_set_id
        ) into_workspaces_count USING (user_set_id)
    });

    ($col,$query) = Socialtext::UserSet->AggregateSQL(
        into => 'workspaces',
        alias => 'bleargh',
        direct => 1,
    );
    is $col, 'COALESCE(bleargh.agg,0)';
    eq_or_diff squash($query), squash(q{
        LEFT JOIN (
            SELECT from_set_id AS user_set_id,
                   COUNT(DISTINCT into_set_id) AS agg
              FROM user_set_include
             WHERE into_set_id BETWEEN x'20000001'::int AND x'30000000'::int
             GROUP BY user_set_id
        ) bleargh USING (user_set_id)
    });
}

view_basics: {
    my $query = Socialtext::UserSet->RoleViewSQL(
        into => 'workspaces',
        from => 'blah',
    );
    eq_or_diff squash($query), squash(q{
        (
            SELECT DISTINCT
                from_set_id AS from_set_id,
                into_set_id AS into_set_id,
                role_id
              FROM user_set_path
             WHERE into_set_id BETWEEN x'20000001'::int AND x'30000000'::int
        ) blah_workspaces_roles
    });

    $query = Socialtext::UserSet->RoleViewSQL(
        into => 'groups',
        from => 'users',
        direct => 1,
    );
    eq_or_diff squash($query), squash(q{
        (
            SELECT DISTINCT
                from_set_id AS user_id,
                into_set_id AS user_set_id,
                role_id
              FROM user_set_include
             WHERE from_set_id <= x'10000000'::int AND into_set_id BETWEEN x'10000001'::int AND x'20000000'::int
        ) users_groups_roles
    });

    $query = Socialtext::UserSet->RoleViewSQL(
        into => 'groups',
        from => 'users',
        direct => 1,
        alias => 'ugr',
    );
    eq_or_diff squash($query), squash(q{
        (
            SELECT DISTINCT
                from_set_id AS user_id,
                into_set_id AS user_set_id,
                role_id
              FROM user_set_include
             WHERE from_set_id <= x'10000000'::int AND into_set_id BETWEEN x'10000001'::int AND x'20000000'::int
        ) ugr
    });

    $query = Socialtext::UserSet->RoleViewSQL(
        into => 'accounts',
        from => 'where',
    );
    eq_or_diff squash($query), squash(q{
        (
            SELECT DISTINCT
                from_set_id AS from_set_id,
                into_set_id AS into_set_id,
                role_id
              FROM user_set_path
             WHERE into_set_id > x'30000000'::int
        ) where_accounts_roles
    });
}

mux_roles: {
    my $query = Socialtext::UserSet->RoleViewSQL(
        into => 'groups',
        from => 'users',
        mux_roles => 1,
    );
    eq_or_diff squash($query), squash(q{
        (
            SELECT
                from_set_id AS user_id,
                into_set_id AS user_set_id,
                uniq(sort(array_accum(role_id)::int[])) AS role_ids
              FROM user_set_path
             WHERE from_set_id <= x'10000000'::int AND into_set_id BETWEEN x'10000001'::int AND x'20000000'::int
             GROUP BY from_set_id, into_set_id
        ) users_groups_roles
    });

    $query = Socialtext::UserSet->RoleViewSQL(
        into => 'groups',
        from => 'container',
        from_alias => 'user_set_id',
        mux_roles => 1,
    );
    # note changed GROUP BY order
    eq_or_diff squash($query), squash(q{
        (
            SELECT
                from_set_id AS user_set_id,
                into_set_id AS into_set_id,
                uniq(sort(array_accum(role_id)::int[])) AS role_ids
              FROM user_set_path
             WHERE into_set_id BETWEEN x'10000001'::int AND x'20000000'::int
             GROUP BY into_set_id, from_set_id
        ) container_groups_roles
    });
}

omit_role: {
    like exception {
        Socialtext::UserSet->RoleViewSQL(
            into => 'groups',
            from => 'users',
            omit_roles => 1,
            mux_roles => 1,
        );
    }, qr/can't omit and mux roles/, "can't omit and mux roles";

    my $query = Socialtext::UserSet->RoleViewSQL(
        into => 'groups',
        from => 'users',
        omit_roles => 1,
    );
    eq_or_diff squash($query), squash(q{
        (
            SELECT DISTINCT
                from_set_id AS user_id,
                into_set_id AS user_set_id
              FROM user_set_path
             WHERE from_set_id <= x'10000000'::int AND into_set_id BETWEEN x'10000001'::int AND x'20000000'::int
        ) users_groups_roles
    });

    $query = Socialtext::UserSet->RoleViewSQL(
        into => 'groups',
        from => 'container',
        from_alias => 'user_set_id',
        omit_roles => 1,
    );
    eq_or_diff squash($query), squash(q{
        (
            SELECT DISTINCT
                from_set_id AS user_set_id,
                into_set_id AS into_set_id
              FROM user_set_path
             WHERE into_set_id BETWEEN x'10000001'::int AND x'20000000'::int
        ) container_groups_roles
    });
}
