#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::More tests => 91;
use Test::Socialtext::Fatal;
use mocked 'Socialtext::Page';
use mocked 'Socialtext::SQL', qw/:test/;
use mocked 'Socialtext::User';
use ok 'Socialtext::Pages';

my $COMMON_SELECT = <<EOSQL;
    SELECT fake AS fake, columns AS columns
    FROM page 
        JOIN "Workspace" USING (workspace_id) 
EOSQL

By_seconds_limit: {
    Regular: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'page_id'}],
            },
        );
        Socialtext::Pages->By_seconds_limit(
            seconds => 88,
            where => 'cows fly',
            count => 20,
            tag => 'foo',
            workspace_id => 9,
        );
        sql_ok(
            name => 'by_seconds_limit',
            sql => <<EOT,
$COMMON_SELECT
        JOIN page_tag USING (page_id, workspace_id) 
    WHERE NOT deleted
      AND page.workspace_id = ? 
      AND last_edit_time > 'now'::timestamptz - ?::interval 
      AND LOWER(page_tag.tag) = LOWER(?) ORDER BY page.last_edit_time DESC, page.name asc LIMIT ?
EOT
            args => [9,'88 seconds','foo', 20],
        );
        ok_no_more_sql();
    }

    Workspace_id_list: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'page_id'}],
            },
        );
        Socialtext::Pages->By_seconds_limit(
            since => '2008-01-01 01:01:01',
            where => 'cows fly',
            count => 20,
            tag => 'foo',
            workspace_ids => [1,2,3],
        );
        sql_ok(
            name => 'by_seconds_limit',
            sql => <<EOT,
$COMMON_SELECT
        JOIN page_tag USING (page_id, workspace_id) 
    WHERE NOT deleted
      AND page.workspace_id IN (?,?,?)
      AND last_edit_time > ?::timestamptz
      AND LOWER(page_tag.tag) = LOWER(?) ORDER BY page.last_edit_time DESC, page.name asc LIMIT ?
EOT
            args => [1,2,3,'2008-01-01 01:01:01','foo', 20],
        );
        ok_no_more_sql();
    }

    Since: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'page_id'}],
            },
        );
        Socialtext::Pages->By_seconds_limit(
            since => '2008-01-01',
            where => 'cows fly',
            count => 20,
            tag => 'foo',
            workspace_id => 9,
        );
        sql_ok(
            name => 'by_since_limit',
            sql => <<EOT,
$COMMON_SELECT
        JOIN page_tag USING (page_id, workspace_id) 
    WHERE NOT deleted
      AND page.workspace_id = ? 
      AND last_edit_time > ?::timestamptz
      AND LOWER(page_tag.tag) = LOWER(?) ORDER BY page.last_edit_time DESC, page.name asc LIMIT ?
EOT
            args => [9,'2008-01-01','foo', 20],
        );
        ok_no_more_sql();
    }

    Neither_seconds_nor_since: {
        like exception {
            Socialtext::Pages->By_seconds_limit(
                where => 'cows fly',
                count => 20,
                tag => 'foo',
                workspace_id => 9,
            );
        }, qr/seconds or count parameter is required/;
        ok_no_more_sql();
    }

    Limit: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'page_id'}],
            },
        );
        Socialtext::Pages->By_seconds_limit(
            seconds => 88,
            where => 'cows fly',
            limit => 20,
            tag => 'foo',
            workspace_id => 9,
        );
        sql_ok(
            name => 'by_seconds_limit',
            sql => <<EOT,
$COMMON_SELECT
        JOIN page_tag USING (page_id, workspace_id) 
    WHERE NOT deleted 
      AND page.workspace_id = ? 
      AND last_edit_time > 'now'::timestamptz - ?::interval 
      AND LOWER(page_tag.tag) = LOWER(?) ORDER BY page.last_edit_time DESC, page.name asc LIMIT ?
EOT
            args => [9,'88 seconds','foo', 20],
        );
        ok_no_more_sql();
    }

    Category: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'page_id'}],
            },
        );
        Socialtext::Pages->By_seconds_limit(
            seconds => 88,
            where => 'cows fly',
            count => 20,
            category => 'foo',
            workspace_id => 9,
        );
        sql_ok(
            name => 'by_seconds_limit',
            sql => <<EOT,
$COMMON_SELECT
        JOIN page_tag USING (page_id, workspace_id) 
    WHERE NOT deleted 
      AND page.workspace_id = ? 
      AND last_edit_time > 'now'::timestamptz - ?::interval 
      AND LOWER(page_tag.tag) = LOWER(?) ORDER BY page.last_edit_time DESC, page.name asc LIMIT ?
EOT
            args => [9,'88 seconds','foo',20],
        );
        ok_no_more_sql();
    }
}

All_active: {
    Regular: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'page_id'}],
            },
        );
        Socialtext::Pages->All_active(
            hub => 'hub',
            count => 20,
            workspace_id => 9,
            offset => 15,
        );
        sql_ok(
            name => 'all_active',
            sql => <<EOT,
$COMMON_SELECT
    WHERE NOT deleted 
      AND page.workspace_id = ? 
    LIMIT ?
    OFFSET ?
EOT
            args => [9,20,15],
        );
        ok_no_more_sql();
    }
    No_workspace_filter: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'page_id'}],
            },
        );
        Socialtext::Pages->All_active(
            hub => 'hub',
            count => 20,
        );
        sql_ok(
            name => 'all_active',
            sql => <<EOT,
$COMMON_SELECT
    WHERE NOT deleted 
    LIMIT ?
EOT
            args => [20],
        );
        ok_no_more_sql();
    }
    NoWorkspace: {
        # Workspace 0 exists, but it should never have pages.
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [],
            },
        );
        Socialtext::Pages->All_active(
            count => 20,
            workspace_id => 0,
        );
        sql_ok(
            name => 'all_active',
            sql => <<EOT,
$COMMON_SELECT
    WHERE NOT deleted 
      AND page.workspace_id = ? 
    LIMIT ?
EOT
            args => [0,20],
        );
        ok_no_more_sql();
    }

    Orphaned: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'page_id'}],
            },
        );
        Socialtext::Pages->All_active(
            hub => 'hub',
            count => 20,
            workspace_id => 9,
            orphaned => 1,
        );
        sql_ok(
            name => 'all_active orphans only',
            sql => <<EOT,
$COMMON_SELECT
    WHERE NOT deleted 
      AND page.workspace_id = ?
      AND not exists (select 1 from page_link where page_link.to_page_id = page.page_id and page_link.to_workspace_id = page.workspace_id)
    LIMIT ?
EOT
            args => [9,20],
        );
        ok_no_more_sql();

    }

    No_workspace_filter: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'page_id'}],
            },
        );
        Socialtext::Pages->All_active(
            hub => 'hub',
            count => 20,
        );
        sql_ok(
            name => 'all_active',
            sql => <<EOT,
$COMMON_SELECT
    WHERE NOT deleted 
    LIMIT ?
EOT
            args => [20],
        );
        ok_no_more_sql();
    }
    NoWorkspace: {
        # Workspace 0 exists, but it should never have pages.
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [],
            },
        );
        Socialtext::Pages->All_active(
            count => 20,
            workspace_id => 0,
        );
        sql_ok(
            name => 'all_active',
            sql => <<EOT,
$COMMON_SELECT
    WHERE NOT deleted 
      AND page.workspace_id = ? 
    LIMIT ?
EOT
            args => [0,20],
        );
        ok_no_more_sql();
    }
    NoLimit: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'page_id'}],
            },
        );
        Socialtext::Pages->All_active(
            hub => 'hub',
            workspace_id => 9,
        );
        sql_ok(
            name => 'all_active',
            sql => <<EOT,
$COMMON_SELECT
    WHERE NOT deleted 
      AND page.workspace_id = ? 
    LIMIT ?
EOT
            args => [9,500],
        );
        ok_no_more_sql();
    }
    Unlimited: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'page_id'}],
            },
        );
        Socialtext::Pages->All_active(
            hub => 'hub',
            count => -1,
            workspace_id => 9,
        );
        sql_ok(
            name => 'all_active',
            sql => <<EOT,
$COMMON_SELECT
    WHERE NOT deleted 
      AND page.workspace_id = ? 
EOT
            args => [9],
        );
        ok_no_more_sql();
    }
    DeepOffset: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'page_id'}],
            },
        );
        Socialtext::Pages->All_active(
            hub => 'hub',
            count => 100,
            workspace_id => 9,
            offset => 765,
        );
        sql_ok(
            name => 'all_active',
            sql => <<EOT,
$COMMON_SELECT
    WHERE NOT deleted 
      AND page.workspace_id = ? 
    LIMIT ?
    OFFSET ? 
EOT
            args => [9,100,765],
        );
        ok_no_more_sql();
    }
    DeepOffsetUnlimited: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'page_id'}],
            },
        );
        Socialtext::Pages->All_active(
            hub => 'hub',
            count => -1,
            workspace_id => 9,
            offset => 765,
        );
        sql_ok(
            name => 'all_active',
            sql => <<EOT,
$COMMON_SELECT
    WHERE NOT deleted 
      AND page.workspace_id = ? 
    OFFSET ? 
EOT
            args => [9,765],
        );
        ok_no_more_sql();
    }
}

By_tag: {
    Regular: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'page_id'}],
            },
        );
        Socialtext::Pages->By_tag(
            workspace_id => 9,
            limit => 33,
            tag => 'foo',
        );
        sql_ok(
            name => 'by_tag',
            sql => <<EOT,
$COMMON_SELECT
        JOIN page_tag USING (page_id, workspace_id) 
    WHERE NOT deleted 
      AND page.workspace_id = ? 
      AND LOWER(page_tag.tag) = LOWER(?) ORDER BY page.last_edit_time DESC, page.name asc LIMIT ?
EOT
            args => [9,'foo',33],
        );
        ok_no_more_sql();
    }

    Paged: {
        Socialtext::Pages->By_tag(
            workspace_id => 9,
            limit => 20,
            offset => 40,
            tag => 'foo',
        );
        sql_ok(
            name => 'by_tag',
            sql => <<EOT,
$COMMON_SELECT
        JOIN page_tag USING (page_id, workspace_id) 
    WHERE NOT deleted 
      AND page.workspace_id = ? 
      AND LOWER(page_tag.tag) = LOWER(?) ORDER BY page.last_edit_time DESC, page.name asc
    LIMIT ?
    OFFSET ?
EOT
            args => [9,'foo',20,40],
        );
        ok_no_more_sql();
    }

    Ordered_by_creator: {
        Socialtext::Pages->By_tag(
            workspace_id => 9,
            limit => 20,
            offset => 40,
            tag => 'foo',
            order_by => 'creator_id DESC',
        );
        sql_ok(
            name => 'by_tag',
            sql => <<EOT,
$COMMON_SELECT
        JOIN page_tag USING (page_id, workspace_id) 
        JOIN users ON (page.creator_id = users.user_id)
    WHERE NOT deleted 
      AND page.workspace_id = ? 
      AND LOWER(page_tag.tag) = LOWER(?) 
    ORDER BY LOWER(users.display_name) DESC, page.name asc
    LIMIT ?
    OFFSET ?
EOT
            args => [9,'foo',20,40],
        );
        ok_no_more_sql();
    }

    Ordered_by_last_editor: {
        Socialtext::Pages->By_tag(
            workspace_id => 9,
            limit => 20,
            offset => 40,
            tag => 'foo',
            order_by => 'last_editor_id DESC',
        );
        sql_ok(
            name => 'by_tag',
            sql => <<EOT,
$COMMON_SELECT
        JOIN page_tag USING (page_id, workspace_id) 
        JOIN users ON (page.last_editor_id = users.user_id)
    WHERE NOT deleted 
      AND page.workspace_id = ? 
      AND LOWER(page_tag.tag) = LOWER(?) 
    ORDER BY LOWER(users.display_name) DESC, page.name asc
    LIMIT ?
    OFFSET ?
EOT
            args => [9,'foo',20,40],
        );
        ok_no_more_sql();
    }

}

By_id: {
    single_page: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'monkey'}],
            },
        );
        Socialtext::Pages->By_id(
            workspace_id => 9,
            page_id => 'monkey',
        );
        sql_ok(
            name => 'by_id',
            sql => <<EOT,
$COMMON_SELECT
    WHERE NOT deleted 
      AND page.workspace_id = ? 
      AND page_id = ?
EOT
            args => [9,'monkey'],
        );
        ok_no_more_sql();
    }

    several_pages: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 9, page_id => 'monkey'}],
            },
        );
        Socialtext::Pages->By_id(
            workspace_id => 9,
            page_id => ['monkey', 'ape', 'chimp'],
        );
        sql_ok(
            name => 'by_id',
            sql => <<EOT,
$COMMON_SELECT
    WHERE NOT deleted 
      AND page.workspace_id = ? 
      AND page_id IN (?,?,?)
EOT
            args => [9,'monkey', 'ape', 'chimp'],
        );
        ok_no_more_sql();
    }

    single_page_deleted_ok: {
        local @Socialtext::SQL::RETURN_VALUES = (
            {
                return => [{workspace_id => 10, page_id => 'orangutang'}],
            },
        );
        Socialtext::Pages->By_id(
            workspace_id => 10,
            page_id => 'orangutang',
            deleted_ok => 1,
        );
        sql_ok(
            name => 'by_id',
            sql => <<EOT,
$COMMON_SELECT
    WHERE 1=1
      AND page.workspace_id = ? 
      AND page_id = ?
EOT
            args => [10,'orangutang'],
        );
        ok_no_more_sql();
    }

}

Not_in_any_workspaces: {
    # We should only be going to the database if we're in some workspaces.
    local @Socialtext::SQL::RETURN_VALUES = ( sub { die "bad sql" } );
    my $pages = Socialtext::Pages->By_seconds_limit(
        seconds => 88,
        where => 'cows fly',
        count => 20,
        tag => 'foo',
        workspace_ids => [],
    );
    is_deeply $pages, [], 'no pages in no workspaces';
}

Minimal_by_filtered_name: {
    Regular: {
        Socialtext::Pages->Minimal_by_name(
            workspace_id     => 9,
            page_filter   => 'monk',
        );
        sql_ok(
            name => 'minimal_by_name',
            sql => <<EOT,
SELECT * FROM (
    SELECT page_id, 
           name, 
           last_edit_time AT TIME ZONE 'UTC' AS last_edit_time_utc, 
           page_type
        FROM page
        WHERE NOT deleted 
          AND workspace_id = ? 
          AND name ~* ?
        ORDER BY last_edit_time DESC
) AS X ORDER BY name
EOT
            args => [9,'\\mmonk'],
        );
        ok_no_more_sql();
    }

    Limited: {
        Socialtext::Pages->Minimal_by_name(
            workspace_id => 9,
            page_filter  => 'monk',
            limit        => 100,
        );
        sql_ok(
            name => 'minimal_by_name',
            sql => <<EOT,
SELECT * FROM (
    SELECT page_id, 
           name, 
           last_edit_time AT TIME ZONE 'UTC' AS last_edit_time_utc, 
           page_type
        FROM page
        WHERE NOT deleted 
          AND workspace_id = ? 
          AND name ~* ?
        ORDER BY last_edit_time DESC
        LIMIT ?
) AS X ORDER BY name
EOT
            args => [9,'\\mmonk', 100],
        );
        ok_no_more_sql();
    }
}


Count_of_recent_changes: {
    Socialtext::Pages->ChangedCount(
        workspace_id => 9,
        duration     => 100,
    );
    sql_ok(
        name => 'recent_changes_count',
        sql => <<EOT,
SELECT count(*) 
    FROM page 
    WHERE NOT deleted 
      AND workspace_id = ? 
      AND last_edit_time > ('now'::timestamptz - ?::interval)
EOT
        args => [9, '100 seconds'],
    );
    ok_no_more_sql();
}

Limit_by_type: {
    Socialtext::Pages->Minimal_by_name(
        workspace_id => 9,
        page_filter  => 'monk',
        type         => 'wiki',
    );
    sql_ok(
        name => 'minimal_by_name',
        sql => <<EOT,
SELECT * FROM (
SELECT page_id, 
       name, 
       last_edit_time AT TIME ZONE 'UTC' AS last_edit_time_utc, 
       page_type
    FROM page
    WHERE NOT deleted 
      AND workspace_id = ? 
      AND name ~* ?
      AND page_type = ?
    ORDER BY last_edit_time DESC
) AS X ORDER BY name
EOT
        args => [9,'\\mmonk', 'wiki'],
    );
    ok_no_more_sql();


    Socialtext::Pages->By_tag(
        workspace_id => 9,
        limit => 33,
        tag => 'foo',
        type => 'wiki',
    );
    sql_ok(
        name => 'by_tag',
        sql => <<EOT,
$COMMON_SELECT
    JOIN page_tag USING (page_id, workspace_id) 
WHERE NOT deleted 
  AND page.workspace_id = ? 
  AND LOWER(page_tag.tag) = LOWER(?) AND page.page_type = ? ORDER BY page.last_edit_time DESC, page.name asc LIMIT ?
EOT
        args => [9,'foo','wiki',33],
    );
    ok_no_more_sql();

    Socialtext::Pages->By_seconds_limit(
        seconds => 88,
        where => 'cows fly',
        count => 20,
        tag => 'foo',
        workspace_id => 9,
        type => 'spreadsheet',
    );
    sql_ok(
        name => 'by_seconds_limit',
        sql => <<EOT,
$COMMON_SELECT
    JOIN page_tag USING (page_id, workspace_id) 
WHERE NOT deleted
  AND page.workspace_id = ? 
  AND last_edit_time > 'now'::timestamptz - ?::interval 
  AND LOWER(page_tag.tag) = LOWER(?) AND page.page_type = ? ORDER BY page.last_edit_time DESC, page.name asc LIMIT ?
EOT
        args => [9,'88 seconds','foo', 'spreadsheet', 20],
    );
    ok_no_more_sql();

    Socialtext::Pages->All_active(
        hub => 'hub',
        count => -1,
        workspace_id => 9,
        offset => 765,
        type => 'wiki',
    );
    sql_ok(
        name => 'all_active',
        sql => <<EOT,
$COMMON_SELECT
WHERE NOT deleted 
  AND page.workspace_id = ? 
  AND page.page_type = ?
OFFSET ? 
EOT
        args => [9,'wiki',765],
    );
    ok_no_more_sql();
}

