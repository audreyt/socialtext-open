package Socialtext::SQL;
# @COPYRIGHT@
use warnings;
use strict;
use DateTime::Format::Pg;
use DBI;
use DBD::Pg;
use Scalar::Util qw/blessed/;
use Carp qw/confess carp croak cluck/;
use List::MoreUtils qw/any/;
use Try::Tiny;
use Guard;

use Socialtext::Date;
use Socialtext::AppConfig;
use Socialtext::Timer qw/time_scope/;

use base 'Exporter';

=head1 NAME

Socialtext::SQL - wrapper interface around SQL methods

=head1 SYNOPSIS

  use Socialtext::SQL qw/:exec :txn/;

  # Regular, auto-commit style:
  my $sth = sql_execute( $SQL, @BIND );
   
  # DIY commit:
  sql_begin_work();
  eval { sql_execute( $SQL, @BIND ) };
  if ($@) {
      sql_roll_back();
  }
  else {
      sql_commit();
  }

=head1 DESCRIPTION

Provides methods with extra error checking and connections to the database.

=cut

our @EXPORT_OK = qw(
    get_dbh disconnect_dbh invalidate_dbh with_local_dbh
    sql_execute sql_execute_array sql_selectrow sql_singlevalue
    sql_singleblob sql_saveblob
    sql_commit sql_begin_work sql_rollback sql_in_transaction
    sql_txn
    sql_parse_timestamptz sql_format_timestamptz sql_timestamptz_now
    sql_ensure_temp
);
our %EXPORT_TAGS = (
    'exec' => [qw(sql_execute sql_execute_array
                  sql_selectrow sql_singlevalue
                  sql_singleblob sql_saveblob)],
    'time' => [qw(sql_parse_timestamptz sql_format_timestamptz 
                  sql_timestamptz_now)],
    'txn'  => [qw(sql_txn sql_commit sql_begin_work
                  sql_rollback sql_in_transaction)],
);

# Feel free to access these globals directly
our $DEBUG = 0;
our $TRACE_SQL = 0;
our $PROFILE_SQL = 0;
our $COUNT_SQL = 0;
our $Level = 2;

use constant NEWEST_FIRST => 'newest';
use constant OLDEST_FIRST => 'oldest';

# ⚠  Don't access these globals directly; use get_dbh(). They're only globals
# ⚠  (and not lexically scoped via "my") so that with_local_dbh() can work.
# ⚠  Code in this module is not an exception! It should use get_dbh too.
our $_dbh;
our $_needs_ping;

=head1 Connection

=head2 get_dbh()

Returns a raw C<DBI> handle to the database.  The connection will be cached.

When forking a new process be sure to, C<disconnect_dbh()> first.

=cut

sub get_dbh {
    if ($_dbh && !$_needs_ping) {
        warn "Returning cached connection" if $DEBUG;
        return $_dbh
    }
    my $t = time_scope 'get_dbh';
    if (!$_dbh) {
        warn "No connection" if $DEBUG;
        _connect_dbh();
    }
    elsif ($_needs_ping && !$_dbh->ping()) {
        warn "dbh ping failed\n";
        disconnect_dbh();
        _connect_dbh();
    }
    return $_dbh;
}

sub _connect_dbh {
    my $t = time_scope 'connect_dbh';
    my %params = Socialtext::AppConfig->db_connect_params();
    cluck "Creating a new DBH $params{db_name}" if $DEBUG;
    my $dsn = "dbi:Pg:database=$params{db_name}";
    $dsn .= ";host=$params{host}" if $params{host};
    $dsn .= ";port=$params{port}" if $params{port};

    $_dbh = DBI->connect($dsn, $params{user}, $params{password} // "",  {
            AutoCommit => 1,
            pg_enable_utf8 => 1,
            pg_prepare_now => 1,
            PrintError => 0,
            RaiseError => 1,
        });

    die "Could not connect to database with dsn: $dsn: $!\n" unless $_dbh;

    $_dbh->do("SET client_min_messages TO 'WARNING'");
    $_dbh->{'private_Socialtext::SQL'} = {
        txn_stack => [],
        temps => {},
    };

    _count_sql("Connected DBH", []) if $COUNT_SQL;
    $_needs_ping = 0;
}

=head2 disconnect_dbh

Forces the DBI connection to close.  Useful for scripts to avoid deadlocks.

=cut

sub disconnect_dbh {
    warn "Disconnecting dbh" if $DEBUG;
    if ($_dbh && !$_dbh->{AutoCommit}) {
        carp "WARNING: Transaction left dangling at disconnect";
        _dump_txn_stack($_dbh);
    }
    $_dbh->disconnect if $_dbh;
    undef $_dbh;
    undef $_needs_ping;
    return;
}

=head2 invalidate_dbh

Make the next call to C<get_dbh()> ping the database and rollback any
outstanding transaction(s).  If the ping fails, a reconnect will occur.  This
should be used before sleeping or entering a blocking-wait state (e.g. at
apache request boundaries)

=cut

sub invalidate_dbh {
    warn "Invalidating dbh" if $DEBUG;
    if ($_dbh && !$_dbh->{AutoCommit}) {
        carp "WARNING: Transaction left dangling at end of request, ".
             "rolling back";
        _dump_txn_stack($_dbh);
        $_dbh->rollback();
    }
    $_needs_ping = 1
}

=head2 with_local_dbh {}

Execute the code block with a separate db connection (get_dbh returns a
different handle from within this block of code).  If any handle exists prior
to calling this function, it will not be disconnected or invalidated.

=cut

sub with_local_dbh (&) {
    local $_dbh;
    local $_needs_ping;
    $_[0]->();
}

=head1 Transactions

Nested transactions are now supported through the use of postgres savepoints.

L<http://www.postgresql.org/docs/8.1/static/sql-savepoint.html>

Use C<sql_txn> unless you need to do something fancy; it's much less
error-prone than matching up begin/commit/rollback commands manually.

Both C<sql_txn> and C<sql_begin_work> are interoperable.  It's safe to use
C<sql_txn> between C<sql_begin_work> and C<sql_commit> calls.  3rd-party code
that starts transactions via C<< $dbh->begin_work >> is not supported.

=head2 sql_txn { run_stuff };

Run a block of code in a transaction (or use a savepoint if one's already
started).  If the code dies, the transaction (or savepoint) is rolled back.
Upon success, the transaction is committed (or the savepoint released).

It's safe to call C<sql_begin_work> and other transaction funcions from with
the code closure.

    sub foo {
        sql_begin_work();
        eval { ... };
        $@ ? sql_rollback() : sql_commit();
    }
    sub bar {
        sql_txn {
            foo();
        };
    }

The calling context (C<wantarray>) and calling parameters are preserved.  This
allows you to use this sub as a C<Moose> or C<Class::MOP> method wrapper:

    around 'baz' => \&sql_txn;
    sub baz {
        my $self = shift;
        #...
        die 'this will cause a rollback' if $failed;
        return 'woot';
    }

When not using Moose, remember to pass through any arguments you aren't
closing-over in the transaction block.

    sub my_wrapper {
        my $self = shift;
        my $x = shift;
        # do stuff outside of txn
        return sql_txn {
            my $y = shift;
            do_stuff($x,$y,@_);
        }, @_; # pass in @_ to make shift do the right thing
    }

=cut

sub sql_txn (&;@) {
    my ($code,@args) = @_;

    sql_begin_work([caller()]);
    my $commit = guard(\&sql_commit);

    return try { $code->(@args) }
    catch {
        my $e = $_;
        $commit->cancel;
        carp "sql_txn rollback..." if $DEBUG;
        my $e2;
        try { sql_rollback() } catch { $e2 = $_ };
        $e .= "\nand during rollback: $e2" if ($e2 && !blessed($e));
        die $e;
    };
}

=head2 sql_in_transaction()

Returns 0 if not in a transaction.  Returns the transaction "level" otherwise.
1 means a pure transaction, 2 and above indicate savepoints are in use.

=head2 sql_begin_work()

Starts a transaction or creates a savepoint. Using C<sql_txn> is recomended,
however.  Dies if a transaction/savepoint couldn't be started.

=head2 sql_commit()

Commit a transaction or release the most recent savepoint.  Dies on failure to
do so.

=head2 sql_rollback()

Rollback a transaction or to the most recent savepoint. Dies on failure to do
so.

=cut

sub sql_in_transaction {
    my $dbh = get_dbh();
    return 0 if $dbh->{AutoCommit};
    return scalar(@{$dbh->{'private_Socialtext::SQL'}{txn_stack}})||1;
}

my $savepoint = 0;
sub sql_begin_work {
    my $dbh = get_dbh();
    my $caller = shift || [caller];

    my $sp = 0;
    if ($dbh->{AutoCommit}) {
        carp "Beginning transaction" if $DEBUG;
    }
    else {
        $sp = "st_".$savepoint++;
        if ($DEBUG) {
            carp "Creating savepoint $sp, ".
                 "level ".(1+@{$dbh->{'private_Socialtext::SQL'}{txn_stack}});
        }
    }

    push @{$dbh->{'private_Socialtext::SQL'}{txn_stack}}, [$sp,@$caller];
    return $sp ? $dbh->pg_savepoint($sp) : $dbh->begin_work();
}

sub sql_commit {
    my $dbh = get_dbh();
    if ($dbh->{AutoCommit}) {
        carp "commit while outside of transaction";
        return;
    }

    my $rec = pop @{$dbh->{'private_Socialtext::SQL'}{txn_stack}};
    if ($rec->[0]) {
        carp "Releasing savepoint $rec->[0]" if $DEBUG;
        return $dbh->pg_release($rec->[0]);
    }
    else {
        carp "Committing transaction" if $DEBUG;
        return $dbh->commit();
    }
}

sub sql_rollback {
    my $dbh = get_dbh();
    if ($dbh->{AutoCommit}) {
        carp "rollback while outside of transaction";
        return;
    }

    my $rec = pop @{$dbh->{'private_Socialtext::SQL'}{txn_stack}};
    if ($rec->[0]) {
        carp "Rolling back to savepoint $rec->[0]" if $DEBUG;
        return $dbh->pg_rollback_to($rec->[0]);
    }
    else {
        carp "Rolling back transaction" if $DEBUG;
        return $dbh->rollback();
    }
}

sub _dump_txn_stack {
    my $dbh = shift;
    my @w = ("Transaction stack:\n");
    my $stack = $dbh->{'private_Socialtext::SQL'}{txn_stack};
    foreach my $caller (@$stack) {
        push @w, "\tat $caller->[2] line $caller->[3] ($caller->[1])\n";
    }
    warn join('',@w); # so as to just call 'warn' once
    @$stack = ();
}

=head1 Querying

=head2 sql_execute( $SQL, @BIND )

sql_execute() will wrap the execution in a begin/commit block
UNLESS the caller has already set up a transaction

Returns a statement handle.

=cut

sub sql_execute {
    my $statement = shift;
    # rest of @_ are bindings, prevent making copies
    my $bind = \@_;
    return try { _sql_execute($statement, 'execute', $bind) }
    catch {
        my $e = $_;
        my $msg = "Error during sql_execute():\n$statement\n";
        $msg .= _list_bindings($bind);
        confess "${msg}Error: $e";
    };
}

=head2 sql_execute_array( $SQL, @BIND )

Like sql_execute(), but pass in an array of array of bind values.

=cut

sub sql_execute_array {
    my $statement = shift;
    my $opts = shift;
    # rest of @_ are bindings, prevent making copies
    my $bind = \@_;

    my @status;
    $opts->{ArrayTupleStatus} = \@status;
    unshift @$bind, $opts;

    return try { _sql_execute($statement, 'execute_array', $bind) }
    catch {
        my $e = $_;
        my $msg = "Error during sql_execute():\n$statement\n";
        $msg .= _list_bindings($bind);
        my %dups;
        my @errors = map { $_->[1] }
                    grep { ref $_ and !$dups{$_->[1]}++ }
                         @status;
        my $err = join("\n", @errors);
        croak "${msg}\nErrors: $e\n$err\n";
    };
}

sub _sql_execute {
    my ($statement, $exec_sub, $bind) = @_;
    my $t = time_scope 'sql_execute';

    my $dbh = get_dbh();

    my ($sth, $rv);
    if ($DEBUG or $TRACE_SQL) {
        my (undef, $file, $line) = caller($Level);
        warn "Preparing ($statement) "
            . _list_bindings($bind)
            . " from $file line $line\n";
    }
    if ($PROFILE_SQL && $statement =~ /^\W*SELECT/i) {
        local $dbh->{RaiseError} = 0;
        my (undef, $file, $line) = caller($Level);
        my $explain = "EXPLAIN ANALYZE $statement";
        my $esth = $dbh->prepare($explain);
        $esth->$exec_sub(@$bind);
        my $lines = $esth->fetchall_arrayref();
        warn "Profiling ($statement) "
            . _list_bindings($bind)
            . " from $file line $line\n"
            . join('', map { "$_->[0]\n" } @$lines);
    }

    _count_sql($statement, $bind) if $COUNT_SQL;
    $sth = $dbh->prepare($statement);
    $sth->$exec_sub(@$bind);
    return $sth;
}

sub _count_sql {
    my $sql = shift;
    my $bind = shift;
    $sql =~ s/\s+/ /smg;
    $sql =~ s/\n/ /smg;

    require Digest::SHA1;
    my $sql_file = '/tmp/sql-count';
    open(my $fh, ">>",$sql_file) or die "Can't open $sql_file: $!";
    print $fh Digest::SHA1::sha1_hex($sql), " $sql - ", join(',', @$bind), "\n";
    close $fh;
}

sub _list_bindings {
    my $bindings = shift;
    return 'bindings=('
         . join(',', map { defined $_ ? "'$_'" : 'NULL' } @$bindings)
         . ')';
}

=head2 sql_selectrow( $SQL, @BIND )

Wrapper around $sth->selectrow_array 

=cut

sub sql_selectrow {
    my ( $statement, @bindings ) = @_;
    my $t = time_scope 'sql_selectrow';
    my $dbh = get_dbh();
    return $dbh->selectrow_array($statement, undef, @bindings);
}

=head2 sql_singlevalue( $SQL, @BIND )

Wrapper around returning a single value from a query.

=cut

sub sql_singlevalue {
    my ( $statement, @bindings ) = @_;

    local $Level = $Level + 1;
    my $sth = sql_execute($statement, @bindings);
    my $value;
    $sth->bind_col(1, \$value);
    $sth->fetch();
    $sth->finish();
    $value =~ s/\s+$// if defined $value;
    return $value;
}

=head1 Blobs

Functions for working with large data blobs.  These are implemented as 'bytea'
columns in PostgreSQL (instead of LOBs).

=head2 $blob_ref = sql_singleblob( $SQL, @BIND )

=head2 $blob_ref = sql_singleblob( $blob_ref, $SQL, @BIND )

Retrieves a postgresql bytea column from the database as a scalar reference.
If the actual value is NULL, a reference to undef is returned;

In the first mode, a new anonymous scalar is created and the blob is loaded
into it.

In the second mode, a scalar reference is supplied as the first argument.  The
blob data will be loaded into that scalar.  For convenience, the same
reference is returned.

The first mode is Lazier, the second mode is slightly faster and has the
potential for some zero-copy aims via L<File::Map>.

=cut

sub sql_singleblob {
    my $blob_ref = shift;

    my $t = time_scope 'sql_singleblob';

    croak "undefined blob reference" unless defined($blob_ref);

    unless (ref($blob_ref)) {
        unshift @_, $blob_ref;
        # Make a new *writable* anonymous scalar reference:
        my $x;
        $blob_ref = \$x;
    }

    local $Level = $Level + 1;
    my $sth = sql_execute(@_);

    if ($sth->rows == 0) {
        $$blob_ref = undef;
        return $blob_ref;
    }

    $sth->bind_col(1, $blob_ref, {pg_type => DBD::Pg::PG_BYTEA()})
        or croak "sql_singleblob: can't bind blob output col: ".$sth->errstr;
    $sth->fetch();

    return $blob_ref;
}

=head2 sql_saveblob( $blob_ref, $UPDATE, @BIND )

Execute the given UPDATE or INSERT statement so the blob referred to by
C<$blob_ref> is SET.

The UPDATE statement must have the first placeholder be the blob column. For
example (using numbered placeholders, which is faster for DBD::Pg):

   UPDATE foo SET body = $1 WHERE foo_id = $2

Or, for INSERT

    INSERT INTO foo (foo_id,body) VALUES ($2,$1)

The C<$sth> is returned if you need to use RETURNING clauses.

=cut

sub sql_saveblob {
    my $dataref = shift;
    my $sql = shift;
    # my @bind = @_;

    my $t = time_scope 'sql_saveblob';

    croak "undefined blob reference"
        unless ($dataref and ref($dataref) eq 'SCALAR');

    my $dbh = get_dbh();
    my $sth = $dbh->prepare($sql);
    my $n = 1;
    $sth->bind_param($n++,$$dataref,{pg_type => DBD::Pg::PG_BYTEA()});
    $sth->bind_param($n++,$_) for @_;
    $sth->execute();
    croak "sql_saveblob: failed to insert/update any rows"
        unless $sth->rows >= 1;
    return $sth;
}

=head1 Utility

=head2 sql_parse_timestamptz()

Parses a timestamptz column into a DateTime object (technically it's a
DateTime::Format::Pg)

=cut

my $dt_fmt_pg = DateTime::Format::Pg->new;
sub sql_parse_timestamptz {
    my $value = shift;
    $value =~ s/(?<=\d)T(?=\d)/ /; # convert infix T to space
    $value =~ s/Z$/+0000/; # zulu = +0000
    my $dt = $dt_fmt_pg->parse_timestamptz($value);
    return $dt;
}

=head2 sql_format_timestamptz()

Converts a DateTime object into a timestamptz column format.

=cut

sub sql_format_timestamptz {
    my $dt = shift;
    my $fmt = $dt_fmt_pg->format_timestamptz($dt);
    if (!$dt->is_finite) {
        # work around a DateTime::Format::Pg bug
        $fmt =~ s/infinite$/infinity/g;
    }
    return $fmt;
}


=head2 sql_timestamptz_now()

Return the current time as a hires, formatted, timestamptz string.

=cut

sub sql_timestamptz_now {
    return sql_format_timestamptz(Socialtext::Date->now(hires=>1));
}

=head2 sql_ensure_temp($table, $defn, [@indexes])

Ensure that a temporary table is set up for this connection. The column
definitions are passed in as C<$defn>, and should be valid SQL for the
"inside" of a CREATE TABLE statement.  Basically:

  CREATE TEMPORARY TABLE $table ( $defn ) ON COMMIT PRESERVE ROWS;

If you need indexes applied, pass those CREATE INDEX statements in full as
subsequent parameters.

If the temp table already exists it's truncated and the indexes aren't
reapplied.

=cut

sub sql_ensure_temp {
    my ($table, $defn, @idx) = @_;
    if (any { $_=~/;/ } $table, $defn, @idx) {
        croak "temp table, its definition, and its indexes cannot contain ';'";
    }

    my $dbh = get_dbh();
    if ($dbh->state && $dbh->state !~ /^0[012]/) {
        carp "skipping creating temp table; in error state anyway ".$dbh->state;
        return;
    }

    my $needs_create = 0;

    try {
        sql_txn {
            local $dbh->{RaiseError} = 0;
            carp "TRUNCATE-ing $table" if ($PROFILE_SQL||$TRACE_SQL||$DEBUG);
            $dbh->do(qq{TRUNCATE $table});
            my $st = $dbh->state;
            carp "TRUNCATE status: $st" if $DEBUG;
            $needs_create = 1 if ($st eq '42P01'); # UNDEFINED TABLE
            die $dbh->errstr if $dbh->errstr;
        };
    }
    catch {
        die $_ unless $needs_create;
    };

    return unless $needs_create;
    sql_txn {
        carp "Creating temp '$table'" if ($PROFILE_SQL||$TRACE_SQL||$DEBUG);
        my $sql = qq{CREATE TEMPORARY TABLE $table ( $defn )
                     WITHOUT OIDS ON COMMIT PRESERVE ROWS};
        sql_execute($sql);
        for my $idx (@idx) {
            sql_execute($idx);
        }
    };
}

1;
