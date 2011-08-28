package Socialtext::Events::Reporter;
# @COPYRIGHT@
use Moose;
use Clone qw/clone/;
use Socialtext::Encode ();
use Socialtext::SQL qw/:exec :txn sql_format_timestamptz sql_ensure_temp/;
use Socialtext::JSON qw/decode_json/;
use Socialtext::User;
use Socialtext::Timer qw/time_scope/;
use Socialtext::WikiText::Parser::Messages;
use Socialtext::WikiText::Emitter::Messages::HTML;
use Socialtext::Formatter::LinkDictionary;
use Socialtext::UserSet qw/:const/;
use Socialtext::Signal::Topic;
use Socialtext::Permission qw/ST_READ_PERM/;
use Socialtext::Role ();
use Guard;
use Scalar::Util qw/blessed/;
use namespace::clean -except => 'meta';

has 'viewer' => (
    is => 'ro', isa => 'Socialtext::User',
    handles => {
        viewer_id => 'user_id',
    }
);

has 'link_dictionary' => (
    is => 'rw', isa => 'Socialtext::Formatter::LinkDictionary',
    lazy_build => 1,
);

has 'table' => (
    is => 'rw', isa => 'Str', default => 'event',
    init_arg => undef,
);

{
    my @field_list = (
        [at_utc => "at AT TIME ZONE 'UTC' || 'Z'"],
        (map { [$_=>$_] } qw(
            at event_class action actor_id
            tag_name context
            person_id signal_id group_id
        )),
        [page_id => 'page.page_id'],
        [page_name => 'page.name'],
        [page_type => 'page.page_type'],
        [page_workspace_name => 'w.name'],
        [page_workspace_title => 'w.title'],
        # signal_hash may be added dynamically
    );
    has 'field_list' => (
        is => 'rw', isa => 'ArrayRef',
        default => sub { clone \@field_list }, # copy it
        lazy => 1, auto_deref => 1,
        init_arg => undef,
    );
}

has $_ => (is => 'rw', isa => 'ArrayRef', default => sub {[]})
    for (qw(_condition_args _outer_condition_args));
has $_ => (is => 'rw', isa => 'ArrayRef', default => sub {['1=1']})
    for (qw(_conditions _outer_conditions));
has $_ => (is => 'rw', isa => 'Bool', default => undef, init_arg => undef)
    for (qw(_skip_visibility _skip_standard_opts _include_public_ws));

sub _build_link_dictionary { Socialtext::Formatter::LinkDictionary->new }

sub add_condition {
    my $self = shift;
    my $cond = shift;
    push @{$self->_conditions}, $cond;
    push @{$self->_condition_args}, @_;
}

sub prepend_condition {
    my $self = shift;
    my $cond = shift;
    unshift @{$self->_conditions}, $cond;
    unshift @{$self->_condition_args}, @_;
}

sub add_outer_condition {
    my $self = shift;
    my $cond = shift;
    push @{$self->_outer_conditions}, $cond;
    push @{$self->_outer_condition_args}, @_;
}

sub prepend_outer_condition {
    my $self = shift;
    my $cond = shift;
    unshift @{$self->_outer_conditions}, $cond;
    unshift @{$self->_outer_condition_args}, @_;
}

our @QueryOrder = qw(
    event_class
    action
    actor_id
    person_id
    page_workspace_id
    page_id
    tag_name
);

sub _best_full_name {
    my $p = shift;

    my $full_name;
    if ($p->{first_name} || $p->{last_name}) {
        $full_name = "$p->{first_name} $p->{last_name}";
    }
    elsif ($p->{email}) {
        ($full_name = $p->{email}) =~ s/@.*$//;
    }
    elsif ($p->{name}) {
        ($full_name = $p->{name}) =~ s/@.*$//;
    }
    return $full_name;
}

{
    my $cache;
    sub cache {
        return $cache ||= Socialtext::Cache->cache('EventsReporter');
    }
}

sub _extract_person {
    my ($self, $row, $prefix) = @_;
    my $id = delete $row->{"${prefix}_id"};
    return unless $id;

    my $cache_key = "person:$id";
    if (my $hash = $self->cache->get($cache_key)) {
        $row->{$prefix} = $hash;
        return;
    }

    my $real_name;
    my $user = Socialtext::User->new(user_id => $id);
    my $avatar_is_visible = $user->avatar_is_visible || 0;
    if ($user) {
        $real_name = $user->guess_real_name();
    }

    my $profile_is_visible = $user->profile_is_visible_to($self->viewer) || 0;
    my $hidden = 1;
    require Socialtext::Pluggable::Adapter;
    my $adapter = Socialtext::Pluggable::Adapter->new;
    if ($adapter->plugin_exists('people')) {
        require Socialtext::People::Profile;
        my $profile = Socialtext::People::Profile->GetProfile($user,
            no_recurse => 1,
        );
        $hidden = $profile->is_hidden if $profile;
    }

    $row->{$prefix} = {
        id => $id,
        best_full_name => $real_name,
        uri => $self->link_dictionary->format_link(
            link => 'people_profile',
            user_id => $id,
        ),
        hidden => $hidden,
        avatar_is_visible => $avatar_is_visible,
        profile_is_visible => $profile_is_visible,
    };
    $self->cache->set($cache_key, $row->{$prefix});
}

sub _extract_page {
    my $self = shift;
    my $row = shift;

    my $link_dictionary = $self->link_dictionary;

    my $page = {
        id => delete $row->{page_id} || undef,
        name => delete $row->{page_name} || undef,
        type => delete $row->{page_type} || undef,
        workspace_name => delete $row->{page_workspace_name} || undef,
        workspace_title => delete $row->{page_workspace_title} || undef,
    };

    if ($page->{workspace_name}) {
        $page->{workspace_uri} = $link_dictionary->format_link(
            link => 'interwiki',
            workspace => $page->{workspace_name},
        );

        if ($page->{id}) {
            $page->{uri} = $link_dictionary->format_link(
                link => 'interwiki',
                workspace => $page->{workspace_name},
                page_uri => $page->{id},
            );
        }
    }

    $row->{page} = $page if ($row->{event_class} eq 'page');
}

sub _extract_tag {
    my $self = shift;
    my $row = shift;
    my $link_dictionary = $self->link_dictionary;

    if ($row->{tag_name}) {
        if (my $page = $row->{page}) {
            $row->{tag_uri} = $link_dictionary->format_link(
                link => 'category',
                workspace => $page->{workspace_name},
                category => $row->{tag_name},
            );
        }
        elsif ($row->{person}) {
            $row->{tag_uri} = $link_dictionary->format_link(
                link => 'people_tag',
                tag_name => $row->{tag_name},
            );
        }
    }
}

sub _expand_context {
    my $self = shift;
    my $row = shift;
    my $c = $row->{context};
    if ($c) {
        local $@;
        $c = Encode::encode_utf8(Socialtext::Encode::ensure_is_utf8($c));
        $c = eval { decode_json($c) };
        warn $@ if $@;
    }
    $c = defined($c) ? $c : {};
    $row->{context} = $c;
}

sub _extract_signal {
    my $self = shift;
    my $row = shift;
    return unless $row->{event_class} eq 'signal';

    my @topics_to_check;

    if (my $topics = $row->{context}{topics}) {
        push @topics_to_check, map {
            $_->{page_id} ? Socialtext::Signal::Topic::Page->new(%$_)
                          : ()
        } @$topics;
    }

    if ($row->{context}{in_reply_to}) {
        push @topics_to_check, @{
            Socialtext::Signal::Topic->Get_all_for_signal(
                signal_id => $row->{context}{in_reply_to}{signal_id}
            )
        };
    }

    for my $topic (@topics_to_check) {
        my $is_visible = 0;
        eval { $is_visible = $topic->is_visible_to($self->viewer) };
        next if $is_visible;
        no warnings 'exiting';
        next EVENT;
    }

    my $hash = delete $row->{signal_hash};

    my $link_dictionary = $self->link_dictionary;
    my $parser = Socialtext::WikiText::Parser::Messages->new(
       receiver => Socialtext::WikiText::Emitter::Messages::HTML->new(
           callbacks => {
               link_dictionary => $link_dictionary,
               viewer => $self->viewer,
           },
       )
    );
    $row->{context}{body} = $parser->parse($row->{context}{body});
    $row->{context}{hash} = $hash;
    $row->{context}{uri} = $link_dictionary->format_link(
        link => 'signal',
        signal_hash => $hash,
    );
}

sub _extract_group {
    my $self = shift;
    my $row = shift;
    return unless $row->{group_id};
    my $group_id = $row->{group_id};
    my $group = Socialtext::Group->GetGroup(group_id => $group_id);
    $row->{group} = {
        name => $group->display_name,
        id => $group_id,
        uri => $self->link_dictionary->format_link(
            link => 'group',
            group_id => $group_id,
        ),
    };

    if (my $ws_id = $row->{context}{workspace_id}) {
        my $wksp = Socialtext::Workspace->new(workspace_id => $ws_id);
        return unless $wksp;
        $row->{page} = {
            workspace_uri => $self->link_dictionary->format_link(
                link => 'interwiki',
                workspace => $wksp->name,
            ),
            workspace_title => $wksp->title,
        };
    }
}

sub decorate_event_set {
    my $self = shift;
    my $sth = shift;

    my $result = [];

    EVENT: while (my $row = $sth->fetchrow_hashref) {
        $self->_extract_person($row, 'actor');
        $self->_extract_person($row, 'person');
        $self->_extract_page($row);
        $self->_expand_context($row);
        $self->_extract_signal($row);
        $self->_extract_group($row);
        $self->_extract_tag($row);

        if ($row->{context}{creator_id}) {
            $self->_extract_person($row->{context}, 'creator');
        }

        delete $row->{person}
            if (!defined($row->{person}) and $row->{event_class} ne 'person');

        $row->{at} = delete $row->{at_utc};

        push @$result, $row;
    }

    return $result;
}

sub signal_vis_sql {
    my ($self, $bind_ref, $opts, $evt_table, $evt_field) = @_;

    my $direct = $opts->{direct} || 'both';

    # Used to support 'sent' and 'received' as paramaters here, but these
    # weren't getting covered by tests and the implementation was broken,
    # so just complain about the parameter rather than throwing an SQL
    # exception.
    die "Invalid direct parameter: $direct"
        unless ($direct eq 'both' or $direct eq 'none');

    my $dm_sql = 'FALSE';
    if ($direct ne 'none') {
        my $field = ($evt_field eq 'actor_id') ? 'person_id' : 'actor_id';
        $dm_sql = qq{
            -- the signal is direct
            ($evt_table.person_id = ? OR $evt_table.actor_id = ?)
            -- and the selected network contains the other user too
            AND EXISTS (
                SELECT 1 FROM user_sets_for_user us_p
                WHERE us_p.user_id = $evt_table.$field
                  AND us_p.user_set_id = a_path.user_set_id
            )
        };
        push @$bind_ref, ($self->viewer->user_id) x 2;
    }

    return qq{ AND (
        -- signal_vis_sql
        (
            -- the signal isn't direct and is to a network we're filtering for
            $evt_table.person_id IS NULL
            AND EXISTS (
                SELECT 1 FROM signal_user_set sua
                WHERE sua.signal_id = $evt_table.signal_id
                  AND sua.user_set_id IN
                    (SELECT user_set_id FROM t_displayable_sets)
            )
        )
        OR
        ($dm_sql)
        -- end signal_vis_sql
    )};
};

sub visible_exists {
    my ($self, $plugin, $opts, $bind_ref, $evt_table, $evt_field) = @_;
    $evt_table ||= 'evt';
    $evt_field ||= 'actor_id';

    my $display_restriction = '';
    if ($opts->{account_id} or $opts->{group_id}) {
        $display_restriction = qq{AND a_path.user_set_id = ?};
        push @$bind_ref, $opts->{account_id}
            ? $opts->{account_id}+ACCT_OFFSET
            : $opts->{group_id}+GROUP_OFFSET;
    }
    else {
        $display_restriction = qq{AND EXISTS (
               SELECT 1 FROM t_displayable_sets tr
                WHERE tr.user_set_id = a_path.user_set_id)};
    }

    my $sql = qq{
    -- visible_exists $plugin $evt_table.$evt_field
    EXISTS (
        SELECT 1 FROM user_sets_for_user a_path
         WHERE a_path.user_id = $evt_table.$evt_field
           -- it's a set we want to display
           $display_restriction
           -- and that set can use this plugin
           AND EXISTS (
               SELECT 1 FROM user_set_plugin_tc plug
                WHERE plugin = '$plugin'
                  AND plug.user_set_id = a_path.user_set_id
           )
    };

    $sql .= $self->signal_vis_sql($bind_ref, $opts, $evt_table, $evt_field)
        if $plugin eq 'signals';

    $sql .= qq{)
    -- end visible_exists $plugin $evt_table.$evt_field\n};
    return $sql;
}

sub no_signals_are_visible {
    my $self = shift;
    my $opts = shift;
    {
        local $@;
        return 1 unless eval "require Socialtext::Signal; 1;";
    }
    return unless Socialtext::Signal->Can_shortcut_events({
        %$opts, viewer => $self->viewer
    });
    push @Socialtext::Rest::EventsBase::ADD_HEADERS,
        ('X-Events-Optimize' => 'signal-shortcut');
    return 1;
}

sub visibility_sql {
    my $self = shift;
    my $opts = shift;
    my @parts;
    my @bind;

    if (_options_include_class($opts, 'person') &&
        $self->viewer->can_use_plugin('people')
    ) {
        push @parts,
            "(evt.event_class <> 'person' OR (".
                $self->visible_exists('people',$opts,\@bind,'evt','actor_id').
                " AND ".
                $self->visible_exists('people',$opts,\@bind,'evt','person_id').
            '))';
    }
    else {
        push @parts, "(evt.event_class <> 'person')";
    }

    if (_options_include_class($opts, 'signal')
        and $self->viewer->can_use_plugin('signals') 
        and not $self->no_signals_are_visible($opts)
    ) {
        my $class_restriction = '';
        unless ($opts->{signals}) {
            # If we limit to signal-bearing events, then the signal must be
            # visible with the group_id/account_id filter; this addresses the
            # case where a hybrid edit/signal or comment/signal event sends
            # to somewhere other than the workspace (W)'s primary account (A);
            # when filtering to "group G's signals", we need to ignore that
            # event even if G has W as an associated workspace.
            $class_restriction = "evt.event_class <> 'signal' OR ";
        }
        push @parts, "( $class_restriction".
            $self->visible_exists('signals',$opts,\@bind).' )';

        # Like visibility
        unless ($self->viewer->can_use_plugin('like')) {
            push @parts, "(evt.action <> 'like'AND evt.action <> 'unlike')";
        }
    }
    else {
        push @parts, "(evt.event_class <> 'signal')";
    }

    if (_options_include_class($opts, 'widget')
        and $self->viewer->can_use_plugin('widgets') 
    ) {
        push @parts,
            "( evt.event_class <> 'widget' OR ".
                $self->visible_exists('widgets',$opts,\@bind).
            ')';
    }
    else {
        push @parts, "(evt.event_class <> 'widget')";
    }

    if (_options_include_class($opts, 'group')
        and $self->viewer->can_use_plugin('groups') 
    ) {
        my $i_am_connected_to_that_group = q{
            SELECT 1 FROM t_displayable_sets gtv
             WHERE gtv.user_set_id = evt.group_id + }.PG_GROUP_OFFSET;

        if ($opts->{account_id}) {
            # limit to groups in the selected account
            $i_am_connected_to_that_group .= q{
               AND EXISTS (
                 SELECT 1 FROM user_set_path acct_usp
                  WHERE acct_usp.from_set_id = gtv.user_set_id
                    AND acct_usp.into_set_id = ?
               )};
            push @bind, $opts->{account_id} + ACCT_OFFSET;
        }

        push @parts,
            "( evt.event_class <> 'group' OR EXISTS (".
                $i_am_connected_to_that_group."))";
    }
    else {
        push @parts, "(evt.event_class <> 'group')";
    }

    my $sql = "\n(\n".join(" AND ",@parts)."\n)\n";
    return $sql,@bind;
}

my $VISIBLE_WORKSPACES = q{
    SELECT into_set_id - }.PG_WKSP_OFFSET.q{ AS workspace_id
      FROM user_set_include_tc
     WHERE from_set_id = ? AND into_set_id }.PG_WKSP_FILTER;

my $PUBLIC_WORKSPACES = <<'EOSQL';
    SELECT workspace_id
    FROM "WorkspaceRolePermission" wrp
    JOIN "Role" r USING (role_id)
    JOIN "Permission" p USING (permission_id)
    WHERE r.name = 'guest' AND p.name = 'read'
EOSQL

sub _limit_ws_to_account {
    my $visible_ws = shift || $VISIBLE_WORKSPACES;
    return qq{
        SELECT workspace_id
        FROM ( $visible_ws ) visws
        WHERE workspace_id IN (
            SELECT workspace_id FROM "Workspace" WHERE account_id = ?
        )
    };
}

sub _limit_ws_to_group {
    my $visible_ws = shift || $VISIBLE_WORKSPACES;
    return qq{
        SELECT workspace_id
        FROM ( $visible_ws ) visgrp
        WHERE workspace_id + }.PG_WKSP_OFFSET .q{ IN (
            SELECT into_set_id
              FROM user_set_path usp
             WHERE usp.from_set_id = ?
               AND usp.into_set_id }.PG_WKSP_FILTER.q{
               AND NOT EXISTS ( -- WS isn't accessible to Group as AUW
                  SELECT 1
                    FROM user_set_path_component uspc
                   WHERE uspc.user_set_path_id = usp.user_set_path_id
                     AND uspc.user_set_id }.PG_ACCT_FILTER.q{
               )
        )
    };
}

my $FOLLOWED_PEOPLE_ONLY = <<'EOSQL';
(
   (actor_id IN (
        SELECT person_id2
        FROM person_watched_people__person
        WHERE person_id1=?))
   OR
   (person_id IN (
        SELECT person_id2
        FROM person_watched_people__person
        WHERE person_id1=?))
)
EOSQL

my $FOLLOWED_PEOPLE_ONLY_WITH_MY_SIGNALS = <<"EOSQL";
(
   $FOLLOWED_PEOPLE_ONLY
   OR (event_class = 'signal' AND actor_id = ?)
)
EOSQL

my $CONTRIBUTIONS = <<'EOSQL';
    (event_class = 'person' AND is_profile_contribution(action))
    OR
    (event_class = 'page' AND is_page_contribution(action))
    OR
    (event_class = 'signal')
EOSQL

sub _process_before_after {
    my $self = shift;
    my $opts = shift;
    if (my $b = $opts->{before}) {
        $self->add_condition('at < ?::timestamptz', $b);
    }
    if (my $a = $opts->{after}) {
        $self->add_condition('at > ?::timestamptz', $a);
    }
}

sub _process_field_conditions {
    my $self = shift;
    my $opts = shift;

    foreach my $eq_key (@QueryOrder) {
        next unless exists $opts->{$eq_key};

        my $arg = $opts->{$eq_key};
        if ((defined $arg) && (ref($arg) eq "ARRAY")) {
            my $placeholders = "(".join(",", map( "?", @$arg)).")";
            $self->add_condition("e.$eq_key IN $placeholders", @$arg);
        }
        elsif (defined $arg) {
            $self->add_condition("e.$eq_key = ?", $arg);
        }
        else {
            $self->add_condition("e.$eq_key IS NULL");
        }
    }

    foreach my $eq_key (@QueryOrder) {
        my $ne_key = "$eq_key!";
        next unless exists $opts->{$ne_key};

        my $arg = $opts->{$ne_key};
        if ((defined $arg) && (ref($arg) eq "ARRAY")) {
            my $placeholders = "(".join(",", map( "?", @$arg)).")";
            $self->add_condition("e.$eq_key NOT IN $placeholders", @$arg);
        }
        elsif (defined $arg) {
            # view events are no longer in the DB
            $self->add_condition("e.$eq_key <> ?", $arg)
                unless $arg eq 'view';
        }
        else {
            $self->add_condition("e.$eq_key IS NOT NULL");
        }
    }
}

sub _limit_and_offset {
    my $self = shift;
    my $opts = shift;

    my @args;

    my $limit = '';
    if (my $l = $opts->{limit} || $opts->{count}) {
        $limit = 'LIMIT ?';
        push @args, $l;
    }
    my $offset = '';
    if (my $o = $opts->{offset}) {
        $offset = 'OFFSET ?';
        push @args, $o;
    }

    my $statement = join(' ',$limit,$offset);
    return ($statement, @args);
}

sub _options_include_class {
    my $opts = shift;
    my $class = shift;

    return 1 unless $opts->{event_class};

    if (ref($opts->{event_class})) {
        return 1 if grep { $_ eq $class } @{$opts->{event_class}};
    }
    else {
        return 1 if $opts->{event_class} eq $class;
    }
    return 0;
}

sub _standard_ws_filter {
    my ($self, $opts) = @_;
    my $t = time_scope 'std_ws_filter';

    sql_ensure_temp(t_visible_ws => 'workspace_id int', 
        q{CREATE INDEX t_visible_ws_idx ON t_visible_ws (workspace_id)});

    my $visible_ws = q{
        SELECT user_set_id - }.PG_WKSP_OFFSET.q{ AS workspace_id
          FROM t_displayable_sets
    };
    if ($self->_include_public_ws) {
        $visible_ws .= ' UNION ALL '.$PUBLIC_WORKSPACES;
    }

    my @insert_bind = ();
    if ($opts->{account_id}) {
        $visible_ws = _limit_ws_to_account($visible_ws);
        push @insert_bind, $opts->{account_id};
    }
    elsif ($opts->{group_id}) {
        $visible_ws = _limit_ws_to_group($visible_ws);
        push @insert_bind, $opts->{group_id} + GROUP_OFFSET;
    }
    sql_execute("INSERT INTO t_visible_ws ".$visible_ws, @insert_bind);

    my $sig_sql = '';
    my @bind;
    # For "all events in group G" or "account A, ignore the visible_ws check
    # if the hybrid signal is specifically sent to the group/account.
    if (($opts->{group_id} || $opts->{account_id}) and
        ($opts->{activity} && $opts->{activity} eq 'all-combined'))
    {
        my $ve = $self->visible_exists('signals',$opts,\@bind,'e');
        $sig_sql .= " OR (signal_id IS NOT NULL AND $ve)";
    }

    $self->prepend_condition(qq{
        -- start "can_view_this_ws"
        page_workspace_id IS NULL OR EXISTS (
            SELECT 1 FROM t_visible_ws WHERE workspace_id = page_workspace_id
        ) $sig_sql
        -- end "can_view_this_ws"
    }, @bind);
}

sub _build_standard_sql {
    my ($self, $opts) = @_;

    my $table = $self->table;

    $self->_process_before_after($opts);

    unless ($self->_skip_standard_opts) {
        if ($opts->{signals}) {
            $self->add_condition(q{signal_id IS NOT NULL});
        }
        else {
            $self->_standard_ws_filter($opts);
        }

        unless ($self->_skip_visibility) {
            $self->add_outer_condition($self->visibility_sql($opts));
        }

        if ($opts->{followed}) {
            if ($opts->{with_my_signals}) {
                $self->add_condition(
                    $FOLLOWED_PEOPLE_ONLY_WITH_MY_SIGNALS => ($self->viewer_id) x 3
                );
            }
            else {
                $self->add_condition(
                    $FOLLOWED_PEOPLE_ONLY => ($self->viewer_id) x 2
                );
            }
        }

        if ($opts->{group_id} and $table ne 'event_page_contrib') {
            $self->add_condition(
                "event_class <> 'group' OR group_id = ?", $opts->{group_id}
            );
        }

        if ($opts->{activity} and $opts->{activity} eq 'all-combined') {
            $self->add_condition('NOT is_ignorable_action(event_class,action)');
        }

        # filter for contributions-type events
        $self->add_condition($CONTRIBUTIONS)
            if $opts->{contributions};
    }

    $self->_process_field_conditions($opts);

    my ($limit_stmt, @limit_args) = $self->_limit_and_offset($opts);

    if ($table ne 'event_page_contrib') {
        # event_page_contrib doesn't have a hidden column
        $self->add_condition('NOT hidden');
        $self->add_outer_condition('NOT hidden');
    }

    # strange code indentation is for SQL alignment
    my $where = join("
          AND ",map {"($_)"} @{$self->_conditions});
    my $outer_where = join("
      AND ", map {"($_)"} @{$self->_outer_conditions});

    my @field_list = $self->field_list;
    my $signals_join = '';
    if ($table eq 'event') {
        $signals_join = <<EOSQL;
LEFT JOIN (
    SELECT signal_id, hash
    FROM signal
) outer_s USING (signal_id)
LEFT JOIN (
    SELECT signal_id, array_accum(liker_user_id) AS likers
    FROM user_like
    GROUP BY signal_id
) likes_s USING (signal_id)
EOSQL
        push @field_list, [ signal_hash => 'outer_s.hash' ];
        push @field_list, [ likers  => 'likes_s.likers' ];
    }

    my $fields = join(",\n\t", map { "$_->[1] AS $_->[0]" } @field_list);

    my $sql = <<EOSQL;
SELECT $fields
  FROM (
    SELECT evt.* FROM (
        SELECT e.*
        FROM $table e
        WHERE $where
        ORDER BY at DESC
    ) evt
    WHERE
    $outer_where
    $limit_stmt
) outer_e
LEFT JOIN page ON (outer_e.page_workspace_id = page.workspace_id AND
                   outer_e.page_id = page.page_id)
LEFT JOIN "Workspace" w ON (outer_e.page_workspace_id = w.workspace_id)
$signals_join
-- the JOINs above mess up the "ORDER BY at DESC".
-- Fortunately, the re-sort isn't too hideous after LIMIT-ing
ORDER BY outer_e.at DESC
EOSQL

    return $sql, [@{$self->_condition_args}, @{$self->_outer_condition_args}, @limit_args];
}

sub _get_events {
    my $self   = shift;
    my $opts = ref($_[0]) eq 'HASH' ? $_[0] : {@_};

    my $t = time_scope 'get_events';

    # Try to shortcut a pure signals query.
    # "just signal events or just signal actions or the magic signals flag":
    if (( !$opts->{event_class} &&
          $opts->{action} &&
          !ref($opts->{action}) &&
          $opts->{action} eq 'signal' ) or 
        ( $opts->{event_class} &&
          !ref($opts->{event_class}) &&
          $opts->{event_class} eq 'signal' ) or
        ( $opts->{signals} )
    ) {
        if (!$self->viewer->can_use_plugin('signals')) {
            push @Socialtext::Rest::EventsBase::ADD_HEADERS,
                ('X-Events-Optimize' => 'no-plugin-access');
            return [];
        }
        return [] if $self->no_signals_are_visible($opts);
    }

    if (my $ld_class = $opts->{link_dictionary}) {
        my $class = "Socialtext::Formatter::${ld_class}LinkDictionary";
        $self->link_dictionary($class->new);
    }

    my ($sql, $args) = $self->_build_standard_sql($opts);

    my $sth = sql_execute($sql, @$args);
    return $self->decorate_event_set($sth);
}

my %can_negate = map {$_=>1} qw(
    action tag_name actor_id person_id
);

sub _filter_opts {
    my $opts = shift;
    my @allowed = @_;

    my %filtered;
    # check for definedness; NULL values can't use an index so disallow them
    for my $k (@allowed) {
        $filtered{$k} = $opts->{$k} if defined $opts->{$k};
        next unless $can_negate{$k};
        $filtered{"$k!"} = $opts->{"$k!"} if defined $opts->{"$k!"};
    }

    return \%filtered;
}

sub _discovery_wrapper {
    my $code = shift;
    my $self = shift;
    my $opts = ref($_[0]) eq 'HASH' ? $_[0] : {@_};

    my $t = time_scope 'disco_rapper';
    sql_begin_work();
    my $viewer = $self->viewer;

    my @temps;

    my $read = ST_READ_PERM;
    my $read_id = $read->permission_id;

    # If the viewer can also view the group, but isn't in the group, pretend
    # that they're in it for the query.
    if (my $group = $opts->{group_id}) {
        $group = Socialtext::Group->GetGroup(group_id => $group)
            unless blessed($group);
        if ($group && !$group->has_user($viewer) &&
            $group->user_can(user=>$viewer, permission=>$read, ignore_badmin=>1))
        {
            push @temps, $group;
        }
    }

    # find all the workspaces in this account that are self-joinable by
    # account-users. *Iff* the viewer is an account-user, pretend to be in
    # those workspaces.
    if ($opts->{account_id}) {
        my $acct = Socialtext::Account->new(account_id => $opts->{account_id});
        if ($acct && $acct->has_user($viewer)) {
            my $account_user_id = Socialtext::Role->AccountUser->role_id;
            # find account-user readable workspaces in this account
            my $sth = sql_execute(q{
                SELECT workspace_id
                  FROM "WorkspaceRolePermission" wrp
                  JOIN "Workspace" w USING (workspace_id)
                 WHERE wrp.permission_id = $1
                   AND wrp.role_id = $2
                   AND w.account_id = $3
            }, $read_id, $account_user_id,$opts->{account_id});
            for my $row (@{$sth->fetchall_arrayref || []}) {
                my $ws = Socialtext::Workspace->new(workspace_id => $row->[0]);
                next if $ws->has_user($viewer);
                push @temps, $ws if $ws;
            }
        }
    }

    # find all the groups the actor is in and pretend to be in those too (*iff*
    # the viewer is connected to the actor through a group/account/workspace).
    if (my $actor = $opts->{actor_id}) {
        $actor = Socialtext::User->Resolve($actor) unless blessed($actor);
        my $authz = Socialtext::Authz->new;
        if ($authz->user_sets_share_an_account($viewer, $actor)) {
            # find all the discoverable groups for the actor, add the viewer
            # into ones that they aren't a member of.
            my $groups = $actor->groups();
            while (my $group = $groups->next) {
                next if $group->has_user($viewer);
                next unless $group->user_can(
                    user=>$viewer, permission=>$read, ignore_badmin=>1
                );
                push @temps, $group;
            }
        }
    }

    # If the viewer can also view the workspace, but isn't in the workspace,
    # pretend that they're in it for the query.
    if (my $ws = $opts->{page_workspace_id}) {
        $ws = Socialtext::Workspace->new(workspace_id => $ws)
            unless blessed($ws);
        if ($ws && !$ws->has_user($viewer) &&
            $ws->user_can(user=>$viewer, permission=>$read))
        {
            push @temps, $ws;
        }
    }

    my $user_set_ids = [ map { $_->user_set_id } @temps ];
    push @$user_set_ids, $self->viewer_id;

    $self->_setup_visible_sets($opts, $user_set_ids);

    scope_guard { sql_rollback() }; # nothing permanent should happen here
    return $code->($self,$opts);
}

sub _setup_visible_sets {
    my ($self, $opts, $sets) = @_;
    $sets ||= [$self->viewer_id];

    sql_ensure_temp(t_readable_sets => 'user_set_id int', 
        q{CREATE INDEX t_readable_sets_idx ON t_readable_sets (user_set_id)});

    sql_execute_array(q{INSERT INTO t_readable_sets VALUES (?)}, {},
        $sets);

    # expand transitive memberships
    sql_execute(q{
        INSERT INTO t_readable_sets
        SELECT DISTINCT into_set_id
          FROM user_set_path
          WHERE from_set_id IN (SELECT * FROM t_readable_sets)
    });

    # figure out which readable sets to display:
    sql_ensure_temp(t_displayable_sets => 'user_set_id int', 
        q{CREATE INDEX t_displayable_sets_idx ON t_displayable_sets (user_set_id)});

    # discovery wrapper makes these objects sometimes.
    my $group_id = blessed($opts->{group_id})
        ? $opts->{group_id}->group_id
        : $opts->{group_id};
    my $account_id = blessed($opts->{account_id})
        ? $opts->{account_id}->account_id
        : $opts->{account_id};
    my $workspace_id = blessed($opts->{page_workspace_id})
        ? $opts->{page_workspace_id}->workspace_id
        : $opts->{page_workspace_id};


    my ($acct_sql, $group_sql, $wksp_sql) =
        (PG_ACCT_FILTER, PG_GROUP_FILTER, PG_WKSP_FILTER);
    my @display_binds;

    if ($account_id) {
        $acct_sql  = '= ?';
        $group_sql = '= 0'; # i.e. no groups
        push @display_binds, $account_id + ACCT_OFFSET;
    }
    elsif ($group_id) {
        $acct_sql  = '= 0'; # i.e. no accounts
        $group_sql = '= ?';
        push @display_binds, $group_id + GROUP_OFFSET;
    }

    if ($workspace_id) {
        $wksp_sql = '= ?';
        push @display_binds, $workspace_id + WKSP_OFFSET;
    }

    sql_execute(qq{
        INSERT INTO t_displayable_sets
        SELECT user_set_id FROM t_readable_sets
        WHERE user_set_id $acct_sql
           OR user_set_id $group_sql
           OR user_set_id $wksp_sql
    }, @display_binds);

# uncomment for debugging
#     {
#         my $sth = sql_execute('SELECT * FROM t_readable_sets');
#         my @all = map { $_->[0] } @{ $sth->fetchall_arrayref || [] };
#         warn "readable sets: ".join(',',@all);
#         $sth = sql_execute('SELECT * FROM t_displayable_sets');
#         @all = map { $_->[0] } @{ $sth->fetchall_arrayref || [] };
#         warn "displayable sets: ".join(',',@all);
#     }
}

around 'get_events' => \&_discovery_wrapper;
sub get_events {
    my $self   = shift;
    my $opts = ref($_[0]) eq 'HASH' ? $_[0] : {@_};

    if ($opts->{event_class} && !(ref $opts->{event_class}) &&
        $opts->{event_class} eq 'page' && $opts->{contributions})
    {
        return $self->get_events_page_contribs($opts);
    }
    my $evs = $self->_get_events($opts);
    return wantarray ? @$evs : $evs;
}

# Switches the query generator to use the `event_page_contrib` table rather
# than the usual `event` table.  The usual non-page event visibility checks
# are also turned off; the query can only ever return page events with this
# table.
sub use_event_page_contrib {
    my $self = shift;

    $self->table('event_page_contrib');
    for my $field ($self->field_list) {
        my ($k,$defn) = @$field;
        if ($k eq 'event_class') {
            $defn = "'page'";
        }
        elsif ($k =~ /^(?:person_id|signal_id|group_id)$/) {
            $defn = "NULL";
        }
        $field->[1] = $defn;
    }
    $self->_skip_visibility(1);
}

around 'get_events_page_contribs' => \&_discovery_wrapper;
sub get_events_page_contribs {
    my $self = shift;
    my $opts = ref($_[0]) eq 'HASH' ? $_[0] : {@_};

    my $t = time_scope 'get_page_contribs';

    $self->use_event_page_contrib();
    my $filtered_opts = _filter_opts($opts, 
        qw(limit count offset before after action followed account_id group_id)
    );
    my ($sql, $args) = $self->_build_standard_sql($filtered_opts);

    my $sth = sql_execute($sql, @$args);
    my $result = $self->decorate_event_set($sth);

    return wantarray ? @$result : $result;
}

around 'get_events_activities' => \&_discovery_wrapper;
sub get_events_activities {
    my $self = shift;
    my $opts = ref($_[0]) eq 'HASH' ? $_[0] : {@_};

    my $t = time_scope 'get_activity';

    my $user = delete $opts->{actor_id}; # discovery hack
    $user = Socialtext::User->Resolve($user)
        unless blessed($user);

    # First we need to get the user id in case this was email or username used

    $self->_include_public_ws(1);

    my $user_ids;
    my @conditions;
    if (!$opts->{event_class}) {
        $opts->{event_class} = [qw(page person signal)];
    }

    my %classes;
    if (ref $opts->{event_class}) {
        %classes = map {$_ => 1} @{$opts->{event_class}};
    }
    else {
        $classes{$opts->{event_class}} = 1;
    }

    if ($classes{page}) {
        push @conditions, q{
            event_class = 'page'
            AND (is_page_contribution(action) OR action IN ('like', 'unlike'))
            AND actor_id = ?
        };
        $user_ids++;
    }

    if ($classes{person}) {
        push @conditions, q{
            -- target ix_event_person_contribs_actor
            (event_class = 'person' AND is_profile_contribution(action)
                AND actor_id = ?)
            OR
            -- target ix_event_person_contribs_person
            (event_class = 'person' AND is_profile_contribution(action)
                AND person_id = ?)
        };
        $user_ids += 2;
    }

    if ($classes{signal}) {
        # BUG? if signals=1 instead of "event_class = 'signal'" we want
        # "signal_id IS NOT NULL" here

        # from the user, mentioning the user or to the user (?!)
        push @conditions, $self->_mention_or_actor_sql;
        $user_ids += 5;
    }

    my $cond_sql = join(' OR ', map {"($_)"} @conditions);
    $self->add_condition($cond_sql, ($user->user_id) x $user_ids);
    my $evs = $self->_get_events(@_);

    return wantarray ? @$evs : $evs;
}

sub _mention_or_actor_sql {
    my $self = shift;
    # Bump user_ids by 5
    return q{
        (
            event_class = 'signal' AND (
                actor_id = ?
                OR EXISTS (
                    SELECT 1
                      FROM topic_signal_user tsu
                     WHERE tsu.signal_id = e.signal_id
                       AND tsu.user_id = ?
                )
                OR person_id = ?
                OR EXISTS (
                    SELECT 1
                      FROM signal root
                      JOIN signal reply
                        ON (root.signal_id = reply.in_reply_to_id)
                     WHERE reply.signal_id = e.signal_id
                       AND (
                        root.user_id = ?
                        OR EXISTS (
                            SELECT 1
                              FROM topic_signal_user tsu
                             WHERE tsu.signal_id = root.signal_id
                               AND tsu.user_id = ?
                        )
                    )
                )
            )
        )
    };
}

around 'get_events_group_activities' => \&_discovery_wrapper;
sub get_events_group_activities {
    my $self     = shift;
    my $opts     = ref($_[0]) eq 'HASH' ? $_[0] : {@_};
    my $t = time_scope 'get_gactivity';

    my $group = delete $opts->{group_id}; # discovery hack
    $group = Socialtext::Group->GetGroup(group_id => $group)
        unless blessed($group);
    my $group_id = $group->group_id;
    my $group_set_id = $group->user_set_id;

    unless ($opts->{after}) {
        my $created = $group->creation_datetime;
        my $cut_off = DateTime->now - DateTime::Duration->new(weeks => 4);
        $opts->{after} = sql_format_timestamptz($created)
            if ($created > $cut_off);
    }

    my @binds = ();
    my $sig_sql =
        $self->visible_exists('signals',{group_id => $group_id},\@binds,'e');

    $self->add_condition(q{
        -- events for group
        ( event_class = 'group' AND group_id = ? )
        OR (
            event_class = 'page'
            AND is_page_contribution(action)
            AND EXISTS ( -- the event's actor is in this group
                SELECT 1 FROM user_set_path
                 WHERE from_set_id = e.actor_id
                   AND into_set_id = ?
            )
            AND EXISTS ( -- the group is in the event's workspace(s)
                SELECT 1 FROM user_set_path usp
                 WHERE e.page_workspace_id = into_set_id - }.PG_WKSP_OFFSET.q{
                   AND from_set_id = ?
                   -- unless it's via an AUW
                   AND NOT EXISTS (
                      SELECT 1
                        FROM user_set_path_component uspc
                       WHERE uspc.user_set_path_id = usp.user_set_path_id
                         AND uspc.user_set_id }.PG_ACCT_FILTER.q{
                   )
            )
        )
        OR ( }.$sig_sql.q{ )
        -- end events for group
    }, $group_id, $group_set_id, $group_set_id, @binds);

    $self->_skip_standard_opts(1);
    my $evs = $self->_get_events($opts);

    return wantarray ? @$evs : $evs;
}

around 'get_events_workspace_activities' => \&_discovery_wrapper;
sub get_events_workspace_activities {
    my $self     = shift;
    my $opts     = ref($_[0]) eq 'HASH' ? $_[0] : {@_};

    my $t = time_scope 'get_wactivity';
    
    my $workspace = delete $opts->{page_workspace_id}; # discovery hack
    $workspace = Socialtext::Workspace->new(workspace_id => $workspace)
        unless blessed($workspace);

    $self->add_condition(q{
        (
            event_class = 'page'
            AND is_page_contribution(action)
            AND e.page_workspace_id = ?
            AND EXISTS (
                SELECT 1
                  FROM user_set_path
                 WHERE from_set_id = e.actor_id
                   AND into_set_id = ?
                 LIMIT 1
            )
        )
    }, $workspace->workspace_id, $workspace->user_set_id);

    $self->_skip_standard_opts(1);
    my $evs = $self->_get_events(@_);
    return wantarray ? @$evs : $evs;
}

sub _conversations_where {
    my $visible_ws = shift || $VISIBLE_WORKSPACES;
    return qq{(
        page_workspace_id IN (
            $visible_ws
        ) -- end page_workspace_id IN
        AND ( -- start convos clause
            -- it's my own action
            (e.actor_id = ?)
            OR
            -- it's in my watchlist
            EXISTS (
                SELECT 1
                FROM "Watchlist" wl
                WHERE e.page_workspace_id = wl.workspace_id
                  AND wl.user_id = ?
                  AND e.page_id = wl.page_text_id::text
            )
            OR
            -- i created it
            EXISTS (
                SELECT 1
                FROM page p
                WHERE p.workspace_id = e.page_workspace_id
                  AND p.page_id = e.page_id
                  AND p.creator_id = ?
            )
            OR
            -- they contributed to it after i did. targets the
            -- ix_epc_actor_page_at index.
            EXISTS (
                SELECT 1
                FROM event_page_contrib my_contribs
                WHERE my_contribs.actor_id = ?
                  AND my_contribs.page_workspace_id = e.page_workspace_id
                  AND my_contribs.page_id = e.page_id
                  AND my_contribs.at < e.at
            )
        ) -- end convos clause
    )};
}

sub _build_convos_sql {
    my $self = shift;
    my $opts = shift;

    my $user_id = $opts->{user_id};

    # filter the options to a subset of what's usually allowed
    my $filtered_opts = _filter_opts($opts, qw(
       action actor_id page_workspace_id page_id tag_name account_id group_id
       before after limit count offset
    ));

    my @bind;
    my @ws_bind;
    my $visible_ws = qq{
    $VISIBLE_WORKSPACES
    UNION ALL
    $PUBLIC_WORKSPACES
        AND workspace_id IN (
            SELECT page_workspace_id AS workspace_id
            FROM event_page_contrib has_contrib
            WHERE has_contrib.actor_id = ?
        )
    };
    push @ws_bind, ($user_id) x 2; # for $visible_ws

    if ($filtered_opts->{account_id}) {
        $visible_ws = _limit_ws_to_account($visible_ws);
        push @ws_bind, $filtered_opts->{account_id};
    }
    elsif ($filtered_opts->{group_id}) {
        $visible_ws = _limit_ws_to_group($visible_ws);
        push @ws_bind, $filtered_opts->{group_id} + GROUP_OFFSET;
    }
    push @bind, @ws_bind;

    my @where;
    push @where, _conversations_where($visible_ws);
    push @bind, ($user_id) x 4;

    $opts->{activity} ||= '';
    $opts->{action} ||= [];
    $opts->{action} = [ $opts->{action} ] unless ref $opts->{action};
    my %action = map { $_ => 1 } @{ $opts->{action} };

    my $show_signals;
    if ($opts->{activity} eq 'all-combined' or $action{signal}) {
        # from the user, mentioning the user or to the user (?!)
        push @where, $self->_mention_or_actor_sql;
        push @bind, ($user_id) x 5;
        $show_signals = 1;
    }
    my $conv_where = join(' OR ', @where);
    $self->prepend_condition($conv_where, @bind);

    my @classes;
    if ($action{signal}) {
        push @classes, 'signal';
        if (keys %action > 1) {
            # {bz: 4840} - We had not extended mention logic to "edit_save" and "comment" yet.
            # For now on "action=signal,edit_save,comment" we simply limit action to "signal" only.
            # push @classes, 'page';
        }
    }
    elsif (%action) {
        push @classes, 'page';
    }

    # If we are not showing signals, use the materialized "event_page_contrib"
    # table since it's much, much faster.
    if (("@classes" eq 'page') or (!@classes and !$show_signals)) {
        $self->use_event_page_contrib();
        $self->_skip_standard_opts(1);
    }
    else {
        if (@classes) {
           my $qs = join(',', ('?') x @classes);
           $self->add_outer_condition(
               "evt.event_class IN ($qs)", @classes
           );
        }

        # If we are showing page events off the main events table, make sure we
        # don't accidentally display the edit_start, edit_cancel, watch_add or
        # watch_delete events.
        if (!@classes or grep { $_ eq 'page' } @classes) {
            $self->add_outer_condition(
                "evt.action NOT IN ('edit_start', 'edit_cancel', 'watch_add', 'watch_delete')"
            );
        }
    }

    return $self->_build_standard_sql($filtered_opts);
}

sub get_events_conversations {
    my $self = shift;
    my $maybe_user = shift;
    my $opts = (@_==1) ? $_[0] : {@_};
    my $t = time_scope 'get_convos';

    # First we need to get the user id in case this was email or username used
    my $user = Socialtext::User->Resolve($maybe_user);
    my $user_id = $user->user_id;
    $opts->{user_id} = $user_id;

    $self->_setup_visible_sets($opts);
    my ($sql, $args) = $self->_build_convos_sql($opts);

    return [] unless $sql;

    my $sth = sql_execute($sql, @$args);
    my $result = $self->decorate_event_set($sth);
    return wantarray ? @$result : $result;
}

sub get_events_followed {
    my $self = shift;
    my $opts = (@_ == 1) ? $_[0] : {@_};
    my $t = time_scope 'get_followed_events';

    $opts->{followed} = 1;
    $opts->{contributions} = 1;
    die "no limit?!" unless $opts->{count};

    $self->_setup_visible_sets($opts);
    my ($followed_sql, $followed_args) = $self->_build_standard_sql($opts);

    my $sth = sql_execute($followed_sql, @$followed_args);
    my $result = $self->decorate_event_set($sth);
    return $result;
}

sub get_page_contention_events {
    my $self = shift;
    my $opts = (@_==1) ? shift : {@_};
    my $t = time_scope 'get_page_contention_events';
    
    $self->_skip_standard_opts(1);
    $self->_skip_visibility(1);
    $opts->{event_class} = 'page';
    $opts->{action} = [qw(edit_start edit_cancel)];
    $self->_setup_visible_sets($opts);
    my ($sql, $args) = $self->_build_standard_sql($opts);

    my $sth = sql_execute($sql, @$args);
    my $result = $self->decorate_event_set($sth);
    return $result;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;
