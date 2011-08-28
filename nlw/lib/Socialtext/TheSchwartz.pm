package Socialtext::TheSchwartz;
# @COPYRIGHT@
use Moose;
use Socialtext::SQL ('sql_txn'); # call $dbh-> methods in this class.
use Try::Tiny;

sub run_in_txn (&$);
BEGIN {
    # Override run_in_txn so that nested savepoints work correctly. Has to be
    # done at BEGIN-time before TheSchwartz::Moosified is loaded.
    no warnings 'redefine';
    require TheSchwartz::Moosified::Utils;
    *TheSchwartz::Moosified::Utils::run_in_txn = \&run_in_txn;
}
use TheSchwartz::Moosified;

use Carp qw/croak/;
use List::MoreUtils qw/any/;
use namespace::clean -except => 'meta';

extends qw/TheSchwartz::Moosified/;

has '+verbose' => ( default => ($ENV{ST_JOBS_VERBOSE} ? 1 : 0) );
has '+error_length' => ( default => 0 ); # unlimited errors logged
has '+prioritize' => ( default => 1 );

# make sure to call get_dbh() every time, basically
override 'databases' => sub { return [ Socialtext::SQL::get_dbh() ] };

around 'list_jobs' => sub {
    my $orig = shift;
    my $self = shift;
    my $args = (@_==1) ? shift : {@_};
    return $self->$orig($args);
};

# TheSchwartz will remove one job type for each job it fetches b/c of some
# mySQL limitation.  Since we're Pg only, disable this.
override 'temporarily_remove_ability' => sub {};

sub run_in_txn (&$) {
    my ($code, $dbh) = @_;
    local $Socialtext::SQL::_dbh = $dbh;
    local $dbh->{RaiseError} = 1;
    return Socialtext::SQL::sql_txn(\&$code);
}

around 'insert' => sub {
    my $code = shift;
    my $self = shift;

    my $job;
    if (ref($_[0]) && $_[0]->isa('TheSchwartz::Moosified::Job')) {
        $job = shift;
    }
    else {
        my $job_class = shift;
        croak "Invalid job class: $job_class" unless $job_class =~ m/::/;
        my $args = shift;
        my $opts = delete $args->{job} || {};

        $job = TheSchwartz::Moosified::Job->new(
            %$opts,
            funcname => $job_class,
            arg => $args,
        );
    }

    return $self->$code($job);
};

sub Unlimit_list_jobs {
    $TheSchwartz::Moosified::FIND_JOB_BATCH_SIZE = 0x7FFFFFFF;
}
sub Limit_list_jobs {
    my $class = shift;
    $TheSchwartz::Moosified::FIND_JOB_BATCH_SIZE = shift;
}

sub stat_jobs {
    my $self = shift;
    my $fold = shift;
    $fold = 1 unless defined $fold;
    
    my $now = time;
    my @results = map {
        $self->_stat_jobs_per_dbh($_, $now)
    } @{$self->databases};

    return @results unless $fold;

    my %stats;

    for my $r (@results) {
        for my $name (keys %{$r->{stats}}) {
            $stats{$name} ||= {};
            while (my ($stat, $value) = each %{$r->{stats}{$name}}) {
                $stats{$name}{$stat} += $value;
            }
        }
    }

    return \%stats;
}

sub _stat_jobs_per_dbh {
    my $self = shift;
    my $dbh = shift;
    my $now = shift || time;

    my $sth = $dbh->prepare_cached(q{
        SELECT funcname,
            COALESCE(queued, 0) AS queued,
            COALESCE(delayed, 0) AS delayed,
            COALESCE(grabbed, 0) AS grabbed,
            COALESCE(latest, 0) AS latest,
            COALESCE(earliest, 0) AS earliest,
            COALESCE(latest_nodelay, 0) AS latest_nodelay,
            COALESCE(earliest_nodelay, 0) AS earliest_nodelay,
            COALESCE(num_ok, 0) AS num_ok,
            COALESCE(num_fail, 0) AS num_fail,
            COALESCE(last_ok, 0) AS last_ok,
            COALESCE(last_fail, 0) AS last_fail,
            COALESCE(recent_completions, 0) AS recent_completions
        FROM funcmap
        LEFT JOIN (
            SELECT funcid,
                COUNT(NULLIF(run_after > $1, 'f'::boolean)) AS delayed,
                COUNT(NULLIF(grabbed_until > $1, 'f'::boolean)) AS grabbed,
                MAX(insert_time) AS latest,
                MIN(insert_time) AS earliest,
                MAX(CASE WHEN run_after <= $1 THEN insert_time ELSE NULL END)
                    AS latest_nodelay,
                MIN(CASE WHEN run_after <= $1 THEN insert_time ELSE NULL END)
                    AS earliest_nodelay,
                COUNT(jobid) AS queued
            FROM job
            GROUP BY funcid
        ) s USING (funcid)
        LEFT JOIN (
            SELECT funcid,
                COUNT(NULLIF(status = 0, 'f'::boolean)) AS num_ok,
                COUNT(NULLIF(status <> 0, 'f'::boolean)) AS num_fail,
                MAX(
                    CASE WHEN status = 0 THEN completion_time
                         ELSE 0 END
                ) AS last_ok,
                MAX(
                    CASE WHEN status <> 0 THEN completion_time
                         ELSE 0 END
                ) AS last_fail,
                COUNT(
                    CASE WHEN (completion_time > $1 - 300) THEN 1 
                         ELSE NULL END
                ) AS recent_completions
            FROM exitstatus
            GROUP BY funcid
        ) e USING (funcid)
    });

    $sth->execute($now);

    my %stats;
    while (my $row = $sth->fetchrow_hashref()) {
        delete $row->{funcid};
        my $name = delete $row->{funcname};
        $stats{$name} = $row;
    }

    return { database => $dbh, stats => \%stats };
}

sub cancel_job {
    my $self = shift;
    my $args = @_==1 ? shift : {@_};

    die "must supply funcname and uniqkey"
        unless $args->{funcname} && $args->{uniqkey};

    for my $dbh (@{ $self->databases }) {
        my $unixtime = TheSchwartz::Moosified::Utils::sql_for_unixtime($dbh);

        my $funcid = $self->funcname_to_id($dbh, $args->{funcname});
        my $sth = $dbh->prepare(qq{
            SELECT jobid FROM job
            WHERE funcid = ?
              AND uniqkey = ? 
              AND grabbed_until <= $unixtime
        });
        $sth->execute($funcid, $args->{uniqkey});
        my ($jobid) = $sth->fetchrow_array;
        $sth->finish;

        $sth = $dbh->prepare(qq{
            UPDATE job
            SET grabbed_until = 2147483647
            WHERE jobid = ?
              AND grabbed_until <= $unixtime
        });
        $sth->execute($jobid);
        return unless $sth->rows == 1;

        TheSchwartz::Moosified::Utils::run_in_txn {
            $dbh->do("DELETE FROM job WHERE jobid = ?", {}, $jobid);
            $dbh->do("INSERT INTO exitstatus 
                      (jobid,funcid,status,completion_time,delete_after)
                      VALUES (?,?,0,$unixtime,$unixtime)", {}, $jobid,$funcid);
        } $dbh;
    }
}

sub clear_jobs {
    my $self = shift;
    for my $dbh (@{$self->databases || []}) {
        $dbh->do('DELETE FROM job');
    }
}

sub remove_job_type {
    my $self = shift;
    my $job_name = shift;

    for my $dbh (@{$self->databases || []}) {
        my $funcid = $self->funcname_to_id($dbh,$job_name);
        next unless $funcid;
        $dbh->do('DELETE FROM job WHERE funcid = ?',{},$funcid);
        $dbh->do('DELETE FROM funcmap WHERE funcid = ?',{},$funcid);
    }
    $self->funcmap_cache({});
}

sub move_jobs_by {
    my $self = shift;
    my $args = @_==1 ? shift : {@_};

    die "must supply funcname and uniqkey"
        unless $args->{funcname} && $args->{uniqkey};
    die "must supply a shift in seconds"
        unless $args->{seconds};

    for my $dbh (@{ $self->databases }) {
        my $unixtime = TheSchwartz::Moosified::Utils::sql_for_unixtime($dbh);

        my $funcid = $self->funcname_to_id($dbh, $args->{funcname});
        # change grabbed_until so it doesn't get accidentally grabbed
        # TODO: make this so it doesn't modify grabbed_until
        my $sth = $dbh->prepare(qq{
            UPDATE job
            SET run_after = run_after + ?,
                grabbed_until = grabbed_until - 1
            WHERE funcid = ?
              AND uniqkey = ? 
              AND grabbed_until <= $unixtime
        });
        $sth->execute($args->{seconds}, $funcid, $args->{uniqkey});
    }
}

sub bulk_insert {
    my $self = shift;
    my $protojob = shift;
    my $jobs = shift;
    my %opts = @_;
    my $dbh = Socialtext::SQL::get_dbh();

    my $funcid = $self->funcname_to_id($dbh, $protojob->funcname);
    die "can't use ref-args in bulk_insert" if any { ref $_->{arg} } @$jobs;
    die "can't use tabbed-args in bulk_insert" if any { $_->{arg} =~ /\t/ } @$jobs;

    my @cols = qw(
        funcid arg uniqkey insert_time run_after grabbed_until priority coalesce
    );
    my $cols = join(', ',@cols);
    my $now = time;
    $protojob->insert_time($now);
    $protojob->funcid($funcid);
    my @protorow = %{$protojob->as_hashref};

    my $table_job = $self->prefix . 'job';

    # if these INSERTs are too slow, try COPY IN to a temp table then INSERT
    # ... SELECT ... WHERE (doesnt_violate_constraints).
    my $sth = $dbh->prepare(
        "INSERT INTO $table_job ($cols) VALUES (?,?,?,?,?,?,?,?)");

    for my $job (@$jobs) {
        my $row = { @protorow, %$job, grabbed_until => 0 };
        $row->{run_after} ||= $now;
        try { sql_txn { $sth->execute(map { $row->{$_} } @cols) } }
        catch {
            die "Error during bulk-insert of " . $protojob->funcname
                . ": $_" unless $opts{ignore_errors};
        };
    }
}

sub job_handle {
    my $self = shift;
    my $jobid = shift;
    my $handle = TheSchwartz::Moosified::JobHandle->new(
        jobid => $jobid,
        client => $self,
        dbh => Socialtext::SQL::get_dbh(),
    );
}

sub job_count {
    my ($self, $funcname) = @_;

    my $count = 0;
    for my $dbh (@{ $self->databases }) {
        my $funcid = $self->funcname_to_id($dbh, $funcname);
        my $sth = $dbh->prepare(qq{
            SELECT count(*) FROM job
            WHERE funcid = ?
        });
        $sth->execute($funcid);
        $count += ${$sth->fetchrow_arrayref || [0]}[0];
    }
    return $count;
}

sub get_last_status {
    my ($self, $thing) = @_;
    my $jobid;
    if (ref($thing) && $thing->can('jobid')) {
        $jobid = $thing->jobid;
    }
    else {
        $jobid = $thing;
    }

    die "no jobid" unless $jobid;

    my $sth = Socialtext::SQL::sql_execute(q{
        SELECT 'status' AS col, status::text
        FROM exitstatus
        WHERE jobid = $1
        UNION ALL (
            SELECT 'error' AS col, message::text
            FROM error
            WHERE jobid = $1
            ORDER BY error_time DESC LIMIT 1
        )
    }, $jobid);
    my %status = map { $_->[0] => $_->[1] } @{$sth->fetchall_arrayref || []};
    return $status{status}, $status{error};
}

__PACKAGE__->meta->make_immutable;
1;
