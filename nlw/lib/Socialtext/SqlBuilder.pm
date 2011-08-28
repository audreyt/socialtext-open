package Socialtext::SqlBuilder;
use Moose::Role;
use Moose::Util ();
use Socialtext::SQL qw(:exec :time);
use Socialtext::SQL::Builder qw(sql_abstract);
use List::MoreUtils qw(all);
use Carp qw/croak cluck/;
use namespace::clean -except => 'meta';

requires 'Builds_sql_for';

sub _short_sql_builds_for {
    my $class = shift;
    my $short = $class->Builds_sql_for;
    $short =~ s/^.+:://;
    return $short;
}

sub _get_for_meta {
    my $class = shift;
    Moose::Util::find_meta($class->Builds_sql_for);
}

sub _CoerceBindings {
    my $class         = shift;
    my $bindings_aref = shift;
    map {
        if (UNIVERSAL::isa($_, 'DateTime')) {
            $_ = sql_format_timestamptz($_);
        }
    } @{$bindings_aref};
}

sub Table {
    my $class = shift;
    $class->_get_for_meta->table;
}

sub Sql_columns {
    my $class = shift;
    $class->_get_for_meta->get_all_column_attributes();
}

sub Sql_unique_key_columns {
    my $class = shift;
    $class->_get_for_meta->get_unique_key_attributes();
}

sub Sql_pkey_columns {
    my $class = shift;
    $class->_get_for_meta->get_primary_key_attributes();
}

sub Sql_non_pkey_columns {
    my $class = shift;
    my @cols  = grep { !$_->primary_key() } $class->Sql_columns();
    return @cols;
}

sub FilterValidColumns {
    my $class = shift;
    my $proto = shift;
    my %valid =
        map  { $_ => $proto->{$_} }
        grep { exists $proto->{$_} }
        map  { $_->name }
        $class->Sql_columns;
    return \%valid;
}

sub FilterPrimaryKeyColumns {
    my $class = shift;
    my $proto = shift;
    my %valid =
        map  { $_ => $proto->{$_} }
        grep { exists $proto->{$_} }
        map  { $_->name }
        $class->Sql_pkey_columns;
    return \%valid;
}

sub FilterNonPrimaryKeyColumns {
    my $class = shift;
    my $proto = shift;
    my %valid =
        map  { $_ => $proto->{$_} }
        grep { exists $proto->{$_} }
        map  { $_->name }
        $class->Sql_non_pkey_columns;
    return \%valid;
}

sub IdentifiesUniqueRecord {
    my $class = shift;
    my $where = shift;

    foreach my $keyset ($class->Sql_unique_key_columns) {
        my $have_all_attrs = all { exists $where->{ $_->name } } @$keyset;
        return 1 if ($have_all_attrs);
    }
    return 0;
}

sub SqlExec {
    my $class     = shift;
    my $sa_method = shift;
    # rest of args passed to $sa_method

    my ($sql, @bindings) = sql_abstract()->$sa_method(@_);
    $class->_CoerceBindings(\@bindings);
    local $Socialtext::SQL::Level = $Socialtext::SQL::Level+1;
    return sql_execute($sql, @bindings);
}

sub SqlSelect {
    my $class = shift;
    my $opts  = shift;

    my $table = $class->Table();
    $table = \"$table $opts->{join}" if $opts->{join};

    local $Socialtext::SQL::Level = $Socialtext::SQL::Level+1;
    return $class->SqlExec('select' =>
        $table, $opts->{columns} || '*',
        $opts->{where}, $opts->{order}, $opts->{limit}, $opts->{offset}
    );
}

sub SqlSelectOneRecord {
    my $class = shift;
    my $opts  = shift;

    my $where = $opts->{where};
    unless ($class->IdentifiesUniqueRecord($where)) {
        croak "Cannot accurately identify unique record to retrieve; aborting";
    }
    local $Socialtext::SQL::Level = $Socialtext::SQL::Level+1;
    return $class->SqlSelect($opts);
}

sub SqlInsert {
    my $class = shift;
    my $proto = shift;
    local $Socialtext::SQL::Level = $Socialtext::SQL::Level+1;

    return $class->SqlExec('insert' =>
        $class->Table, $proto
    );
}

sub SqlUpdate {
    my $class = shift;
    my $opts  = shift;
    local $Socialtext::SQL::Level = $Socialtext::SQL::Level+1;

    return $class->SqlExec('update' =>
        $class->Table, $opts->{values}, $opts->{where}
    );
}

sub SqlUpdateOneRecord {
    my $class = shift;
    my $opts  = shift;
    local $Socialtext::SQL::Level = $Socialtext::SQL::Level+1;

    my $where = $opts->{where};
    unless ($class->IdentifiesUniqueRecord($where)) {
        croak "Cannot accurately identify unique record to update; aborting";
    }
    return $class->SqlUpdate($opts);
}

sub SqlDelete {
    my $class = shift;
    my $where = shift;
    local $Socialtext::SQL::Level = $Socialtext::SQL::Level+1;

    return $class->SqlExec('delete' => $class->Table, $where);
}

sub SqlDeleteOneRecord {
    my $class = shift;
    my $where = shift;

    local $Socialtext::SQL::Level = $Socialtext::SQL::Level+1;
    unless ($class->IdentifiesUniqueRecord($where)) {
        croak "Cannot accurately identify unique record to delete; aborting";
    }
    return $class->SqlDelete($where);
}

no Moose::Role;
1;

=head1 NAME

Socialtext::SqlBuilder - Syntactic sugar to define CRUD Sql

=head1 SYNOPSIS

  package MyFactory;
  use Moose;
  use constant Builds_sql_for => 'MyClass';
  with qw(Socialtext::SqlBuilder);

  # filter to include only key/value pairs for valid columns
  $valid = MyFactory->FilterValidColumns( $data );

  # filter to include only key/value pairs for primary key columns
  $pkey = MyFactory->FilterPrimaryKeyColumns( $data );

  # filter to include only key/value pairs for NON primary key columns
  $non_pkey = MyFactory->FilterNonPrimaryKeyColumns( $data );

  unless (MyFactory->IdentifiesUniqueRecord( \%where )) {
      # hash-ref doesn't contain enough info to identify unique record
  }

  $sth = MyFactory->SqlSelect( {
      columns => [qw( user_id driver_key driver_unique_id )],
      where   => {
          first_name => 'john',
          last_name  => 'doe',
      },
      order   => 'user_id',
      limit   => 10,
      offset  => 0,
  } );

  $sth = MyFactory->SqlSelectOneRecord( {
      where => {
          user_id => 123,
      },
  } );

  $sth = MyFactory->SqlInsert( {
      user_id          => 123,
      driver_key       => 'Default',
      driver_unique_id => 123,
      email_address    => 'john.doe@example.com',
  } );

  $sth = MyFactory->SqlUpdate( {
      values => {
          primary_account_id => 2,
      },
      where  => {
          primary_account_id => 1,
      },
  } );

  $sth = MyFactory->SqlUpdateOneRecord( {
      values => {
          email_address => 'john.doe@example.com',
      },
      where  => {
          user_id => 123,
      },
  } );

  $sth = MyFactory->SqlDelete( {
      email_address => 'john.doe@example.com',
  } );

  $sth = MyFactory->SqlDeleteOneRecord( {
      user_id => 123,
  } );

=head1 DESCRIPTION

C<Socialtext::SqlBuilder> provides some additional syntactic sugar to
help make it easier to set up factory classes that need to build SQL to talk
to an underlying DB.

=head1 METHODS

=over

=item B<builds_sql_for $table_class>

Specifies that this class builds SQL for a DB table that is defined by the
specified C<$table_class>.

It is B<expected> that the provided C<$table_class> has been constructed using
C<Socialtext::Moose::SqlTable>.  This isn't checked for explicitly, but it is
expected.

=item B<$class-E<gt>FilterValidColumns( \%data )>

Filters the provided hash-ref of C<\%data>, returning a hash-ref that contains
only those field/value pairs which are for columns in the Db Table we're
managing.

=item B<$class-E<gt>FilterPrimaryKeyColumns( \%data )>

Filters the provided hash-ref of C<\%data>, returning a hash-ref that contains
only those field/value pairs which are for columns that comprise the primary
key of the Db Table we're managing.

=item B<$class-E<gt>FilterNonPrimaryKeyColumns( \%data )>

Filters the provided hash-ref of C<\%data>, returning a hash-ref that contains
only those field/value pairs which are for columns that are B<NOT> part of the
primary key of the Db Table we're managing.

=item B<$class-E<gt>IdentifiesUniqueRecord(\%where)>

Checks to see if the provided C<\%where> clause is capable of identifying a
unique record in the DB.  Returns true if it is, false otherwise.

B<NOTE:> this isn't a highly stringent check; we check to make sure that the
WHERE clause contains enough columns to at least satisfy one of the unique
indices on the DB, but we B<aren't> expanding out the WHERE clause to make
sure that you're not passing in list of values to check against (e.g. "WHERE
foo IN (...)").

=item B<$class-E<gt>SqlSelect(\%opts)>

Issues a SQL C<SELECT> against the DB, and returns a DBI Statement Handle back
to the caller.

C<SqlSelect> accepts a number of options, which in turn are then passed
through to C<SQL::Abstract::Limit>:

=over

=item columns

Specifies the DB columns that are to be selected.  Defaults to "*" unless
specified.

=item where

Specifies the C<SQL::Abstract> WHERE clause.

=item order

Specifies any specific ordering you require on the results.

=item limit

Specifies a maximum limit on the number of results that are to be returned.

=item offset

Specifies the offset into the result set from which search results should be
retrieved.

=back

=item B<$class-E<gt>SqlSelectOneRecord(\%opts)>

Issues a SQL C<SELECT> against the DB (like C<SqlSelect()> above), with the
expectation that the provided WHERE clause contains enough information to
B<uniquely> identify a single record in the DB.

If the provided WHERE clause cannot identify a unique record, this method
throws an exception.

=item B<$class-E<gt>SqlInsert(\%proto)>

Issues a SQL C<INSERT> against the DB, using the field/value pairs defined in
the provided C<\%proto> hash-ref.  Returns a DBI Statement Handle back to the
caller.

=item B<$class-E<gt>SqlUpdate(\%opts)>

Issues a SQL C<UPDATE> against the DB, and returns a DBI Statement Handle back
to the caller.

The provided hash-ref of C<\%opts> may contain:

=over

=item values

A hash-ref of the new values that the record is to be updated to.

=item where

A hash-ref containing a WHERE clause, suitable for handing to
C<SQL::Abstract>.

=back

=item B<$class-E<gt>SqlUpdateOneRecord(\%opts)>

Issues a SQL C<UPDATE> against the DB (like C<SqlUpdate()> above), with the
expectation that the provided WHERE clause contains enough information to
B<uniquely> identify a single record in the DB.

If the provided WHERE clause cannot identify a unique record, this method
throws an exception.

=item B<$class-E<gt>SqlDelete(\%where)>

Issues a SQL C<DELETE> against the DB, and returns a DBI Statement Handle back
to the caller.  The provided hash-ref C<\%where> clause should be suitable for
handing to C<SQL::Abstract>.

=item B<$class-E<gt>SqlDeleteOneRecord(\%where)>

Issues a SQL C<DELETE> against the DB (like C<SqlDelete()> above), with the
expectation that the provided C<\%where> clause contains enough information to
B<uniquely> identify a single record in the DB.

If the provided WHERE clause cannot identify a unique record, this method
throws an exception.

=back

=head1 COPYRIGHT & LICENSE

Copyright (C) 2009 Socialtext, Inc., All Rights Reserved.

=head1 SEE ALSO

L<Socialtext::Moose::SqlTable>, L<SQL::Abstract>, L<SQL::Abstract::Limit>.

=cut
