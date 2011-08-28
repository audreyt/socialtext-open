package Socialtext::CRUDFactory;
# @COPYRIGHT@
use Moose::Role;
use List::Util qw(first);
use Socialtext::Timer;
use namespace::clean -except => 'meta';

with qw(Socialtext::SqlBuilder);

requires 'Builds_sql_for'; # copied from SqlBuilder
requires 'SetDefaultValues';

requires 'EmitCreateEvent';
requires 'EmitUpdateEvent';
requires 'EmitDeleteEvent';

requires 'RecordCreateLogEntry';
requires 'RecordUpdateLogEntry';
requires 'RecordDeleteLogEntry';

sub Get {
    my ($self, %p) = @_;

    # Only concern ourselves with valid Db Columns
    my $where = $self->FilterValidColumns( \%p );

    # Fetch the record from the DB
    my $sth = $self->SqlSelectOneRecord( { where => $where } );
    my $row = $sth->fetchrow_hashref();
    return unless $row;

    # Create an instance of the object based on the row we got back
    my $class = $self->Builds_sql_for();
    return $class->new($row);
}

sub PostChangeHook {
    my $self = shift;
    my $action = shift;
    my $instance = shift;

    return if $action eq 'update';

    if ($self->Builds_sql_for =~ /^Socialtext::User.+Role$/) {
        # work, group, acct
        # index that user, unless it's just a membership role/attr change
        Socialtext::JobCreator->index_person($instance->user_id);
    }
    elsif ($self->Builds_sql_for =~ /^Socialtext::Group.+Role$/) {
        my $user_ids = $instance->group->user_ids;
        Socialtext::JobCreator->index_person($_) for @$user_ids;
    }
}

sub CreateRecord {
    my ($self, $proto) = @_;

    # Only concern ourselves with valid Db Columns
    my $valid = $self->FilterValidColumns( $proto );

    # SANITY CHECK: need all required attributes
    my $missing =
        first { not defined $valid->{$_} }
        map   { $_->name }
        grep  { $_->is_required }
        $self->Sql_columns;
    if ($missing) {
        my $short_name = $self->_short_builds_sql_for();
        die "need a $missing attribute to create a $short_name";
    }

    # INSERT the new record into the DB
    $self->SqlInsert( $valid );
    $self->EmitCreateEvent( $valid );
}

sub Create {
    my ($self, $proto) = @_;
    my $timer = Socialtext::Timer->new();

    $self->SetDefaultValues($proto);
    $self->CreateRecord($proto);

    my $instance = $self->Get(%{$proto});
    $self->PostChangeHook('create' => $instance);
    $self->RecordCreateLogEntry($instance, $timer);
    return $instance;
}

sub UpdateRecord {
    my ($self, $proto) = @_;

    # Only concern ourselves with valid Db Columns
    my $valid = $self->FilterValidColumns($proto);

    # Update is done against the Primary Key
    my $pkey = $self->FilterPrimaryKeyColumns($valid);

    # Don't allow for Primary Key fields to be updated
    my $values = $self->FilterNonPrimaryKeyColumns($valid);

    # If there's nothing to update, *don't*.
    return unless %{$values};

    # UPDATE the record in the DB
    my $sth = $self->SqlUpdateOneRecord( {
        values => $values,
        where  => $pkey,
    } );

    my $did_update = ($sth && $sth->rows) ? 1 : 0;
    $self->EmitUpdateEvent( $proto ) if $did_update;
    return $did_update;
}

sub Update {
    my ($self, $instance, $proto) = @_;
    my $timer = Socialtext::Timer->new();

    # Update the record in the DB
    my $pkey        = $instance->primary_key();
    my $updates_ref = {
        %{$proto},
        %{$pkey},
    };
    my $did_update  = $self->UpdateRecord($updates_ref);

    if ($did_update) {
        # merge the updates back into the instance, skipping primary key
        # columns (which *aren't* updateable)
        my $to_merge = $self->FilterNonPrimaryKeyColumns($updates_ref);

        foreach my $attr (keys %{$to_merge}) {
            $instance->meta->find_attribute_by_name($attr)->set_value(
                $instance, $to_merge->{$attr},
            );
        }
        $self->PostChangeHook('update' => $instance);
        $self->RecordUpdateLogEntry($instance, $timer);
    }
    return $instance;
}

sub DeleteRecord {
    my ($self, $proto) = @_;

    # Only concern ourselves with valid Db Columns
    my $where = $self->FilterValidColumns($proto);

    # DELETE the record in the DB
    my $sth = $self->SqlDeleteOneRecord($where);

    my $did_delete = $sth->rows();
    $self->EmitDeleteEvent( $proto ) if $did_delete;
    return $did_delete;
}

sub Delete {
    my ($self, $instance) = @_;
    my $timer = Socialtext::Timer->new();
    my $did_delete = $self->DeleteRecord($instance->primary_key());
    if ($did_delete) {
        $self->PostChangeHook('delete' => $instance);
        $self->RecordDeleteLogEntry($instance, $timer);
    }
    return $did_delete;
}

sub Cursor {
    my $self_or_class = shift;
    my $sth           = shift;
    my $closure       = shift;
    my $target_class  = $self_or_class->Builds_sql_for();

    eval  "require $target_class";
    die $@ if $@;

    return Socialtext::MultiCursor->new(
        iterables => [ $sth->fetchall_arrayref( {} ) ],
        apply     => sub {
            my $row      = shift;
            my $instance = $target_class->new($row);
            return ( $closure ) ? $closure->($instance) : $instance;
        },
    );
}

no Moose::Role;
1;

=head1 NAME

Socialtext::CRUDFactory - Create, Retrieve, Update and Delete SQL-stored objects.

=head1 SYNOPSIS

  package MyFactory;
  use Moose;
  with qw(Socialtext::CRUDFactory);
  use constant Builds_sql_for => 'MyClass';
  ...

=head1 DESCRIPTION

C<Socialtext::CRUDFactory> provides a baseline Role for a Factory to create,
retrieve, update and delete objects that are stored in the SQL DB.  Database
access is via L<Socialtext::SQL>.

=head1 METHODS

=over

=item B<$class-E<gt>Get(PARAMS)>

Looks for an existing record in the underlying DB table matching the given
PARAMS, and returns an instantiated object representing that row, or C<undef>
if it can't find a match.

=item B<$class-E<gt>CreateRecord(\%proto)>

Create a new record in the underlying DB table based on the given C<\%proto>
hash-ref of data.

=item B<$class-E<gt>Create(\%proto)>

Creates a new record in the underlying DB table based on the given C<\%proto>
hash-ref of data, and returns back to the caller an object instance for the
resulting record.

=item B<$class-E<gt>UpdateRecord(\%proto)>

Updates an existing record in the DB, based on the information in the provided
C<\%proto> hash-ref.  Returns true if a record was updated in the DB,
returning false otherwise (e.g. if the update was effectively "no change").

The C<\%proto> hash-ref B<MUST> contain all of the data necessary to identify
the primary key for the record in the DB to update.

If you attempt to update a non-existing record, this method fails silently; no
exception is thrown, B<but> no data is updated/inserted in the DB (as it
didn't exist there in the first place.

=item B<$class-E<gt>Update($instance, \%proto)>

Updates the given C<$instance> object with the information provided in the
given C<\%proto> hash-ref, including the underlying DB store.

Returns the updated C<$instance> object back to the caller.

=item B<$class-E<gt>DeleteRecord(\%proto)>

Deletes the record in the DB, as defined by the given C<\%proto> hash-ref.

Returns true if a record was deleted, false otherwise.

=item B<$class-E<gt>Delete($instance)>

Deletes the given C<$instance> object from the DB.

Helper method which simply calls C<DeleteRecord()>.

=item B<$self_or_class-E<gt>Cursor($sth, \&coderef)>

Returns a C<Socialtext::MultiCursor> to iterate over all of the result records
in the given DBI C<$sth>, by turning each one of the result rows into an
actual I<instance> of the class that the Factory generating objects of (the
same one it C<Builds_sql_for>).

This method takes an optional C<\&coderef> that can be used to manipulate the
instantiated objects prior to them getting returned.

=back

=head1 REQUIREMENTS

In order to consume this role and create your own Object Factory,
implementations for the following methods are required:

=over

=item Builds_sql_for

Since this role extends the L<Socialtext::SqlBuilder> Role, it also requires
the Build_sql_for constant.  This constant should return the name of the
object that this factory works with.

=item EmitCreateEvent($proto)

Emits whatever Event is necessary to indicate that a new record was created in
the underlying DB store.

This method will be given a C<$proto> hash-ref containing all of the fields
that were stored in the DB.

=item EmitUpdateEvent($proto)

Emits whatever Event is necessary to indicate that a record was updated in the
underlying DB store.

This method will be given a C<$proto> hash-ref containing all of the fields
for the updated record.

=item EmitDeleteEvent($proto)

Emits whatever Event is necessary to indicate that a record was deleted in the
underlying DB store.

This method will be given a C<$proto> hash-ref containing all of the fields of
the deleted record, B<after> the record has been deleted.

=item RecordCreateLogEntry($instance, $timer)

Records whatever entry you feel is necessary to indicate that a new record was
created in the underlying DB store.

This method will be given an actual C<$instance> of the object that was
created, and a C<Socialtext::Timer> object.

=item RecordUpdateLogEntry($instance, $timer)

Records whatever entry you feel is necessary to indicate that a record was
updated in the underlying DB store.

This method will be given an actual C<$instance> of the object that was
updated, and a C<Socialtext::Timer> object.

=item RecordDeleteLogEntry($instance, $timer)

Records whatever entry you feel is necessary to indicate that a record was
deleted from the underlying DB store.

This method will be given the actual C<$instance> of the object that was
deleted, B<after> is has been deleted from the DB.

=back

=head1 AUTHOR

Socialtext, Inc.,  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc.,  All Rights Reserved.

=cut
