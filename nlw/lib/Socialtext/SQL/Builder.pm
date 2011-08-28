package Socialtext::SQL::Builder;
# @COPYRIGHT@
use strict;
use base 'Exporter';
use Socialtext::SQL qw(:exec get_dbh);
use List::MoreUtils qw(any);
use Carp qw/croak cluck/;

our @EXPORT = ();
our @EXPORT_OK = qw(
    sql_nextval
    sql_update sql_insert sql_insert_many
    sql_abstract
);
our %EXPORT_TAGS = (
    'all' => \@EXPORT_OK,
);

=head1 NAME

Socialtext::SQL::Builder - code for generating common SQL statements

=head1 SYNOPSIS

  use Socialtext::SQL::Builder qw(:all)

  my %insert_or_update = (
      name => 'Carl',
      addr => 'foo@example.com',
  );

  $insert_or_update{id_field} = sql_nextval('some_sequence_name');

  # does a SQL "INSERT INTO tablename ..."
  sql_insert('tablename' => \%insert_or_update);

  $insert_or_update{name} = 'Steve';
  $insert_or_update{addr} = 'bar@example.com';

  # does a SQL "UPDATE tablename SET ... WHERE id_field = ?"
  sql_update('tablename' => \%insert_or_update, 'id_field');

=head1 DESCRIPTION

Provides convenience methods on top of what C<Socialtext::SQL> provides.

The generated SQL is specific to C<DBD::Pg>.

=head1 METHODS

=head2 sql_nextval($sequence)

Get the next value of the named sequence.

=cut

sub sql_nextval {
    return sql_singlevalue("SELECT nextval(?)", shift);
}

=head2 sql_update($table, $hashref, $pk_key)

Update the specified table with the provided hash of values.  C<$pk_key> is a
key into the hash of values that is to be used as a unique identifier in the
WHERE clause.

One "SET" statement will be generated for each key-value pair in the hashref
except for the C<$pk_key> field, which cannot be updated with this function.

B<Caution:> No validation is done on the table name or the keys in the hashref.

If your table has a composite key, you can pass the column names in as an
arrayref for your C<$pk_key> arg.

This method returns I<before> hitting the DB, if it determines that no actual
update to the DB would be performed.

=cut

sub sql_update {
    my $table = shift;
    my $p = shift;
    my $pk_key = shift;

    die "no table name" unless $table;
    die "invalid key name" unless $pk_key;
    die "nothing to update" unless ($p and %$p);

    my @where_keys = ( ref($pk_key) eq 'ARRAY' ) ? sort @$pk_key : ( $pk_key );
    my @where_values = (map {$p->{$_}} @where_keys);
    my $where_params = join(' AND ', map {"$_ = ?"} @where_keys);

    die "pk has missing value(s)"
        if any {!defined($_)} @where_values;

    my %keys_seen = map { $_ => 1 } @where_keys;

    my @set_keys = sort grep {!$keys_seen{$_}} keys %$p;
    my $set_params = join(', ', map {"$_ = ?"} @set_keys);
    return unless @set_keys;

    my $sql = "UPDATE $table SET $set_params WHERE $where_params";
    local $Socialtext::SQL::Level = $Socialtext::SQL::Level + 1;
    return sql_execute( $sql, (map {$p->{$_}} @set_keys), @where_values);
}

=head2 sql_insert ($table, $hashref)

Insert into the specified table using the provided hash of values.

B<Caution>: No validation is done on the keys or values of the hashref.

=cut

sub sql_insert {
    my $table = shift;
    my $cols = shift;
    my $opts = shift;

    die "no table name" unless $table;
    die "nothing to update" unless ($cols and %$cols);

    my @keys = sort keys %$cols;
    my $fields = join(',', @keys);
    my @bind = (map {$cols->{$_}} @keys);

    my $placeholders = '?,' x @keys;
    chop $placeholders;

    my $sql = "INSERT INTO $table ($fields)\n";
    if (my $safe = $opts->{safe}) {
        $sql .= "SELECT $placeholders\n";
        $sql .= "WHERE NOT EXISTS ( SELECT 1 FROM $table WHERE ";
        $sql .= join(' AND ', map { "$_ = ?" } @$safe);
        $sql .= " )\n";
        push @bind, map { $cols->{$_} } @$safe;
    }
    else {
        $sql .= "VALUES ($placeholders)";
    }

    local $Socialtext::SQL::Level = $Socialtext::SQL::Level + 1;
    my $sth;
    eval { $sth = sql_execute($sql, @bind) };
    if ($@) {
        croak $@;
    }
    return $sth;
}

=head2 sql_insert_many ($table, \@cols, \@values )

Insert into the specified table using the provided columns and values

B<Caution>: No validation is done on the columns or values.

=cut

sub sql_insert_many {
    my $table = shift;
    my $cols  = shift;
    my $rows  = shift;

    die "no table name" unless $table;
    die "no columns to update" unless $cols and @$cols;
    die "no data to update" unless $rows and @$rows;

    my $fields = join(',', @$cols);
    my $placeholders = '?,' x @$cols;
    chop $placeholders;

    my $sql = "INSERT INTO $table ($fields) VALUES ($placeholders)";
    local $Socialtext::SQL::Level = $Socialtext::SQL::Level + 1;
    my $sth;
    my $dbh = get_dbh();
    eval { 
        my $sth = $dbh->prepare($sql);
        for (@$rows) {
            $sth->execute(@$_)
                || die "execute failed: " . $sth->errstr . "\n";
        }
    };
    if ($@) {
        croak $@;
    }
    return $sth;
}

=head2 sql_abstract()

Returns an instance of C<SQL::Abstract::Limit> suitable for use with our
database.  See C<SQL::Abstract> for basic usage.

Provided in the spirit of TIMTOWTDI.

=cut

sub sql_abstract {
    require Socialtext::SQL::Abstract;
    return Socialtext::SQL::Abstract->new(
        logic => 'and',
        @_,
        limit_dialect => 'LimitOffset',
    );
}

1;
__END__
=head1 SEE ALSO

C<Socialtext::SQL>, C<DBD::Pg>, C<SQL::Abstract>, C<SQL::Abstract::Limit>

=head1 AUTHOR

Jeremy Stashewsky <stash@socialtext.com> & the Socialtext crew

=head1 COPYRIGHT

@COPYRIGHT@
