package Test::Socialtext::SQL;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Exporter';
use Test::Builder;
use Test::Differences;
use Socialtext::SQL qw(get_dbh);

our @EXPORT = qw(
    db_columns_match_ok
    db_indices_match_ok
);
our @EXPORT_OK = qw(
    db_columns_match_ok
    get_columns_for_table
    db_indices_match_ok
    get_indices_for_table
);

our $Normalizer = sub { return shift };

sub db_columns_match_ok {
    my @tables = @_;
    my $original = shift @tables;
    my $expected = get_columns_for_table($original);

    local $Test::Builder::Level = $Test::Builder::Level+1;

    foreach my $table (@tables) {
        my $received = get_columns_for_table($table);
        eq_or_diff $expected, $received, "schema match: $original vs $table";
    }
}

sub get_columns_for_table {
    my $table = shift;

    my $dbh = get_dbh();
    my $sth = $dbh->column_info(undef, undef, $table, undef);

    my $columns;
    while (my $row = $sth->fetchrow_hashref) {
        my $name = $row->{COLUMN_NAME};
        $name = $Normalizer->($name);
        $columns->{$name} = _normalize_row($row);
    }

    return $columns;
}

sub db_indices_match_ok {
    my @tables = @_;
    my $original = shift @tables;
    my $expected = get_indices_for_table($original);

    local $Test::Builder::Level = $Test::Builder::Level+1;

    foreach my $table (@tables) {
        my $received = get_indices_for_table($table);
        eq_or_diff $expected, $received, "index match: $original vs $table";
    }
}

sub get_indices_for_table {
    my $table = shift;

    my $dbh = get_dbh();
    my $sth = $dbh->statistics_info(undef, undef, $table, undef, undef);

    my $indices;
    while (my $row = $sth->fetchrow_hashref) {
        my $name = $row->{INDEX_NAME};
        next unless $name;

        $name = $Normalizer->($name);
        $indices->{$name} = _normalize_row($row);
    }
    return $indices;
}

# Normalize a row of data by removing internal columns and ensuring
# that all "*_NAME" columns are normalized.
sub _normalize_row {
    my $row = shift;
    my %normalized;
    foreach my $key (keys %{$row}) {
        next if ($key =~ /^pg_/);
        next if ($key eq 'PAGES'); # pg 9.0

        my $val = $row->{$key};
        $val = $Normalizer->($val) if ($key =~ /_NAME/);
        $normalized{$key} = $val;
    }
    return \%normalized;
}

1;

=head1 NAME

Test::Socialtext::SQL - SQL tests

=head1 SYNOPSIS

  use Test::Socialtext::SQL;

  # Create a normalizer for table/index names.
  local $Test::Socialtext::SQL::Normalizer = sub {
      my $name = shift;
      $name =~ s/^recent_//;
      return $name;
  };

  # Test column/index matches between tables
  db_columns_match_ok(qw( signal recent_signal ));
  db_indices_match_ok(qw( signal recent_signal ));

=head1 DESCRIPTION

C<Test::Socialtext::SQL> provides some helper methods to check and verify that
the DB schema for tables matches (either column-wise, or index-wise).

You'll also want to over-ride the C<$Test::Socialtext::SQL::Normalizer>
subroutine to provide a subroutine to normalize the names of the
tables/indices so they match up with one another.  As we pull the info from Pg
about the tables/indices, the name-ish columns are run through this normalizer
function to create a normalized presentation of the schema (which are then
compared to one another for differences).

=cut
