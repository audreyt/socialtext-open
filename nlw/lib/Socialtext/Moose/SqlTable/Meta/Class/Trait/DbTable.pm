package Socialtext::Moose::SqlTable::Meta::Class::Trait::DbTable;

use Moose::Role;

has 'table' => (
    is  => 'rw', isa => 'Str',
);

has 'unique_keys' => (
    is  => 'rw', isa => 'ArrayRef[ArrayRef[Str]]',
    default => sub{[]}
);

sub get_primary_key_attributes {
    my $self = shift;
    my @pkey = grep { $_->primary_key } $self->get_all_column_attributes();
    return @pkey;
}

sub get_unique_key_attributes {
    my $self = shift;
    my @uniq;

    # first, the primary key
    my @pkey = $self->get_primary_key_attributes;
    push @uniq, \@pkey if @pkey;

    # then, any supplementary unique keys
    my $meta_uniq = $self->unique_keys();
    foreach my $key (@{$meta_uniq}) {
        my @attrs = map { $self->find_attribute_by_name($_) } @{$key};
        push @uniq, \@attrs;
    }

    return @uniq;
}

sub get_all_column_attributes {
    my $self = shift;
    my @cols = grep { $_->does('DbColumn') } $self->get_all_attributes();
    return @cols;
}

no Moose::Role;
1;

=head1 NAME

Socialtext::Moose::SqlTable::Meta::Class::Trait::DbTable - DbTable class trait

=head1 SYNOPSIS

  # get the name of the Db Table under
  $table = MyTable->meta->table();

  # get the list of all Db columns
  @column_attrs = MyTable->get_all_column_attributes();

  # get the attributes used to create the primary key
  @primary_key = MyTable->get_primary_key_attributes();

  # get a list of list-refs containing all the unique keys
  @unique_keys = MyTable->get_unique_key_attributes();
  foreach my $key (@unique_keys) {
      map { print $_->name . "\n" } @{$key};
  }

=head1 DESCRIPTION

C<Socialtext::Moose::SqlTable::Meta::Class::Trait::DbTable> provides a
C<Moose> class trait to assist in building classes that have an underlying DB
table.

Although the guts are implemented here, you'll want to refer to the
documentation in C<Socialtext::Moose::SqlTable> for the additional syntactic
sugar to help you define your table, the primary key, and alternate unique
keys.

=head1 METHODS

=over

=item B<$class-E<gt>meta-E<gt>table()>

Sets/queries the name of the underlying DB table.

C<Socialtext::Moose::SqlTable> provides C<has_table> sugar to make this easier
to define.

=item B<$class-E<gt>meta-E<gt>unique_keys()>

Sets/queries a list-ref of unique keys (each of which is a list-ref of
attribute names).

C<Socialtext::Moose::SqlTable> provides some C<has_unique_key> sugar to make
it easier to define unique keys; call that once for each additional unique key
you have on your table.

=item B<$class-E<gt>get_primary_key_attributes()>

Returns a list of attribute objects for all of the attributes that were marked
as contributing to the primary key.

=item B<$class-E<gt>get_unique_key_attributes()>

Returns a list of list-refs, each one containing a set of attribute objects
which define an alternate unique key on the table.

=item B<$class-E<gt>get_all_column_attributes()>

Returns a list of attribute objects for all of the attributes that were marked
as being Db Columns.

=back

=head1 COPYRIGHT & LICENSE

Copyright (C) 2009 Socialtext, Inc., All Rights Reserved.

=head1 SEE ALSO

L<Socialtext::Moose::SqlTable>.

=cut
