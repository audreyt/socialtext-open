#@COPYRIGHT@
package Socialtext::SQL;
use strict;
use warnings;
use base 'Exporter';
use unmocked 'Test::More';
use unmocked 'Socialtext::Date';
use unmocked 'Data::Dumper';
use unmocked 'DateTime::Format::Pg';
use unmocked 'Guard';

use constant NEWEST_FIRST => 'newest';
use constant OLDEST_FIRST => 'oldest';

our @EXPORT_OK = qw(
    get_dbh disconnect_dbh invalidate_dbh
    sql_execute sql_execute_array sql_selectrow sql_singlevalue
    sql_commit sql_begin_work sql_rollback sql_in_transaction sql_txn
    sql_parse_timestamptz sql_format_timestamptz sql_timestamptz_now
    sql_ok sql_mock_result sql_mock_row_count ok_no_more_sql
    sql_ensure_temp
);
our %EXPORT_TAGS = (
    'exec' => [qw(sql_execute sql_execute_array sql_selectrow sql_singlevalue)],
    'time' => [qw(sql_parse_timestamptz sql_format_timestamptz)],
    'txn'  => [qw(sql_commit sql_begin_work
                  sql_rollback sql_in_transaction sql_txn)],

    'test' => [qw(sql_ok sql_mock_result sql_mock_row_count ok_no_more_sql)],
);

our @SQL;
our @RETURN_VALUES;
our $Level = 0;

sub sql_mock_result {
    push @RETURN_VALUES, {'return'=>[@_]};
}
sub sql_mock_row_count {
    push @RETURN_VALUES, {rows => shift, 'return' => []};
}

sub sql_execute_array { sql_execute(@_) }

sub sql_execute {
    my $sql = shift;
    #diag $sql;
    push @SQL, { sql => $sql, args => [@_] };
    
    my $sth_args = shift @RETURN_VALUES;
    if (ref($sth_args) and ref($sth_args) eq 'CODE') {
        return $sth_args->();
    }

    my $mock = mock_sth->new(%{ $sth_args || {} });
    return $mock;
}

sub disconnect_dbh { }
sub invalidate_dbh { }
my $Mock_in_transaction = 0;
sub sql_in_transaction { $Mock_in_transaction }
sub sql_begin_work { $Mock_in_transaction++ }
sub sql_commit { $Mock_in_transaction-- }
sub sql_rollback { $Mock_in_transaction-- }
sub sql_txn (&;) { 
    my $code = shift;
    $Mock_in_transaction++;
    Guard::scope_guard { $Mock_in_transaction-- };
    return $code->(@_);
}


sub sql_ensure_temp { }

sub sql_selectrow { 
    my $sth = sql_execute(@_);
    return $sth->fetchrow_array();
};

sub sql_singlevalue { 
    my $sth = sql_execute(@_);
    my ($val) = $sth->fetchrow_array();
    return $val;
};

sub sql_parse_timestamptz {
    my $value = shift;
    return DateTime::Format::Pg->parse_timestamptz($value);
}

sub sql_format_timestamptz {
    my $dt = shift;
    return DateTime::Format::Pg->format_timestamptz($dt);
}

sub sql_timestamptz_now {
    return sql_format_timestamptz(Socialtext::Date->now(hires=>1));
}

sub sql_ok {
    my %p = @_;

    # Booya - stash rocks - show test failures in the right file.
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $sql = shift @SQL;
    $p{name} = $p{name} ? "$p{name}: " : '';
    my $expected_sql = $p{sql};
    if ($expected_sql) {
        my $observed_sql = _normalize_sql($sql->{sql});
        if (ref($p{sql})) {
            like $observed_sql, $expected_sql, 
                 $p{name} . 'SQL matches';
        }
        else {
            is $observed_sql, _normalize_sql($expected_sql), 
               $p{name} . 'SQL matches exactly';
        }
    }

    if ($p{args}) {
        is_deeply $sql->{args}, $p{args}, $p{name} . 'SQL args match'
            or diag Dumper($sql->{args});
    }
}

sub _normalize_sql {
    my $sql = shift || '';
    $sql =~ s/-- .*$//mg; # strip out SQL comments
    $sql =~ s/\s+/ /sg;
    $sql =~ s/\s+$//;
    $sql =~ s/^\s+//;
    return $sql;
}

sub ok_no_more_sql {
    my $name = shift || "no more queries";
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is (scalar(@SQL), 0, $name) or do {
        diag "The following SQL statements were outstanding:";
        diag Dumper(\@SQL);
    };
    @SQL = ();
}

# DBH methods

sub get_dbh { 
    bless {}, __PACKAGE__;
}

sub prepare {
    my $dbh = shift;
    my $sql = shift;
    push @Socialtext::SQL::SQL, { sql => $sql, args => [] };

    my $sth_args = shift @RETURN_VALUES || {};
    return mock_sth->new(%$sth_args);
}

sub selectrow_array {
    my $dbh = shift;
    my $sql = shift;
    my $attr = shift;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@_);
    return $sth->fetchrow_array();
}

package mock_sth;
use strict;
use warnings;
use base 'Socialtext::MockBase';

sub finish {}

sub fetchall_arrayref {
    my $self = shift;
    return $self->{return} || [];
}

sub fetchrow_arrayref {
    my $self = shift;
    return shift @{$self->{return}};
}

sub fetchrow_array {
    my $self = shift;
    my $row = shift @{$self->{return}} || [];
    return @$row;
}

sub fetchrow_hashref {
    my $self = shift;
    return shift @{$self->{return}};
}

sub rows {
    my $self = shift;
    return $self->{rows} if exists $self->{rows};
    return scalar(@{$self->{return}});
}

sub execute {
    my $self = shift;
    $Socialtext::SQL::SQL[-1]{args} ||= [];
    push @{ $Socialtext::SQL::SQL[-1]{args} }, \@_;
}

sub bind_columns {
    my $self = shift;
}
sub fetch {
    my $self = shift;
}

sub bind_param {
    my $self = shift;
    my $p_num = shift;
    my $bind_value = shift;
    my $attr = shift;

    $Socialtext::SQL::SQL[-1]{args} ||= [];
    $Socialtext::SQL::SQL[-1]{args}[$p_num-1] = [$bind_value, $attr];
    return 1;
}

1;
