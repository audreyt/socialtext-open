package Socialtext::Job::Upgrade::CleanupReportsEditActions;
# @COPYRIGHT@
use Moose;
use Socialtext::Reports::DB ();
use Socialtext::SQL qw/sql_execute with_local_dbh/;
use Socialtext::Timer qw/time_scope/;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

has 'reports_dbh' => (is => 'ro', isa => 'Object', lazy_build => 1);
sub _build_reports_dbh { Socialtext::Reports::DB::get_dbh() }

sub do_work {
    my $self = shift;

    $self->delete_bad_new_page_actions();
    for my $page (@{ $self->wabu_pages_with_multiple_new_page_actions }) {
        $self->wabu_fix_page_stats($page);
    }
    for my $page (@{ $self->nlw_pages_with_multiple_new_page_actions }) {
        $self->nlw_fix_page_stats($page);
    }
    $self->completed();
}

around [
    qw/delete_bad_new_page_actions 
        wabu_pages_with_multiple_new_page_actions
        wabu_fix_page_stats 
        nlw_pages_with_multiple_new_page_actions
        nlw_fix_page_stats/
    ] => sub {
    my $orig = shift;
    my $self = shift;
    my @args = @_;
    no warnings 'redefine';
    local *Socialtext::SQL::get_dbh = sub {
        my $dbh = $self->reports_dbh;
        $dbh->{AutoCommit} = 1;
        return $dbh;
    };
    with_local_dbh(sub { $orig->($self, @args) });
};

sub wabu_pages_with_multiple_new_page_actions {
    my $self       = shift;
    my $t          = time_scope "wabu-find-incorrect-pages";

    # Look for pages created more than once
    my $sth = sql_execute(<<EOT, $self->arg->{account_id});
SELECT * FROM (
      SELECT workspace, page_id, SUM(tally) AS new_tally
        FROM workspace_actions_by_user     
       WHERE action = 'new_page' 
         AND account_id = ?
     GROUP BY workspace, page_id
  ) AS X
  WHERE new_tally > 1;
EOT
    return $sth->fetchall_arrayref({});
}

sub wabu_find_first_edit {
    my $self       = shift;
    my $page       = shift;
    my $t          = time_scope "wabu-find-first-edit";
    my $sth = sql_execute(<<EOT,
SELECT * FROM workspace_actions_by_user
 WHERE action = 'new_page'
   AND account_id = ?
   AND workspace = ?
   AND page_id = ?
 ORDER BY period_start asc
 LIMIT 1
EOT
        $self->arg->{account_id}, $page->{workspace}, $page->{page_id},
    );
    my $rows = $sth->fetchall_arrayref({});
    return $rows->[0];
}

sub wabu_fix_page_stats {
    my $self       = shift;
    my $page       = shift;
    my $t          = time_scope "wabu-fix-page-stats";

    my $row = $self->wabu_find_first_edit($page);

    # There may be multiple counts for the very first new_page,
    # so turn all but one into edit_page records. If the tally was 
    # one, we end up with a row with a tally of 0 which will be ignored.
    my $sth = sql_execute(<<EOT,
UPDATE workspace_actions_by_user
    SET tally = tally - 1, action = 'edit_page'
  WHERE period_start = ?
    AND account_id = ?
    AND workspace = ?
    AND username = ?
    AND page_id = ?
    AND action = 'new_page'
EOT
        $row->{period_start}, $row->{account_id}, $row->{workspace},
        $row->{username}, $row->{page_id},
    );

    # Now fix all new_page rows to be edit_page
    $sth = sql_execute(<<EOT,
UPDATE workspace_actions_by_user
    SET action = 'edit_page'
  WHERE workspace = ? AND page_id = ? AND action = 'new_page'
EOT
        $row->{workspace}, $row->{page_id},
    );

    # Now finally insert the new_page back, at the right time.
    $sth = sql_execute(<<EOT,
INSERT INTO workspace_actions_by_user
    (period_start, account_id, workspace, username, page_id, action, tally)
    VALUES (?,?,?,?,?,'new_page',1)
EOT
        $row->{period_start}, $row->{account_id}, $row->{workspace},
        $row->{username}, $row->{page_id},
    );
}

sub nlw_pages_with_multiple_new_page_actions {
    my $self       = shift;
    my $t          = time_scope "nlw-find-incorrect-pages";

    # Look for pages created more than once
    my $sth = sql_execute(<<EOT, $self->arg->{account_id});
SELECT * FROM (
      SELECT workspace, page_id, SUM(tally) AS new_tally
        FROM nlw_log_actions
       WHERE action = 'CREATE' 
         AND object = 'PAGE'
         AND account_id = ?
     GROUP BY workspace, page_id
  ) AS X
  WHERE new_tally > 1;
EOT
    return $sth->fetchall_arrayref({});
}

sub nlw_find_first_edit {
    my $self       = shift;
    my $page       = shift;
    my $t          = time_scope "nlw-find-first-edit";
    my $sth = sql_execute(<<EOT,
SELECT * FROM nlw_log_actions 
 WHERE action = 'CREATE'
   AND object = 'PAGE'
   AND account_id = ?
   AND workspace = ?
   AND page_id = ?
 ORDER BY period_start asc
 LIMIT 1
EOT
        $self->arg->{account_id}, $page->{workspace}, $page->{page_id},
    );
    my $rows = $sth->fetchall_arrayref({});
    return $rows->[0];
}

sub nlw_fix_page_stats {
    my $self       = shift;
    my $page       = shift;
    my $t          = time_scope "nlw-fix-page-stats";

    my $row = $self->nlw_find_first_edit($page);

    # There may be multiple counts for the very first new_page,
    # so turn all but one into edit_page records. If the tally was 
    # one, we end up with a row with a tally of 0 which will be ignored.
    my $sth = sql_execute(<<EOT,
UPDATE nlw_log_actions 
    SET tally = tally - 1, action = 'EDIT'
  WHERE period_start = ?
    AND account_id = ?
    AND workspace = ?
    AND username = ?
    AND page_id = ?
    AND action = 'CREATE' 
    AND object = 'PAGE'
EOT
        $row->{period_start}, $row->{account_id}, $row->{workspace},
        $row->{username}, $row->{page_id},
    );

    # Now fix all new_page rows to be edit_page
    $sth = sql_execute(<<EOT,
UPDATE nlw_log_actions 
    SET action = 'EDIT', object='PAGE'
  WHERE workspace = ? AND page_id = ? AND action = 'CREATE' and object = 'PAGE'
EOT
        $row->{workspace}, $row->{page_id},
    );

    # Now finally insert the new_page back, at the right time.
    $sth = sql_execute(<<EOT,
INSERT INTO nlw_log_actions 
    (period_start, account_id, workspace, username, page_id, action, object, tally)
    VALUES (?,?,?,?,?,'CREATE','PAGE',1)
EOT
        $row->{period_start}, $row->{account_id}, $row->{workspace},
        $row->{username}, $row->{page_id},
    );
}

sub delete_bad_new_page_actions {
    my $self       = shift;
    my $account_id = $self->arg->{account_id};
    my $t          = time_scope "clean-untitled-$account_id";

    sql_execute(<<EOT, $account_id);
DELETE FROM workspace_actions_by_user
    WHERE action = 'new_page'
      AND account_id = ?
      AND (page_id = 'untitled_page' OR page_id = '')
EOT

    sql_execute(<<EOT, $account_id);
DELETE FROM nlw_log_actions
    WHERE account_id = ?
      AND page_id = 'untitled_page'
EOT
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::Upgrade::CleanupReportsEditActions - Clean crufty reports data

=head1 SYNOPSIS

    use Socialtext::Migration::Utils qw/create_job_for_each_account/;
    create_job_for_each_account('CleanupReportsEditActions');
    exit 0;

=head1 DESCRIPTION

Schedule a job to be run by TheCeq which will clean crufty data from reports.

