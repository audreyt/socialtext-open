package Socialtext::Moose::SqlTable::Meta::Attribute::Trait::DbColumn;

use Moose::Role;

has 'primary_key' => (
    is  => 'ro',
    isa => 'Bool',
);

# primary_key implies is_required
around 'is_required' => sub {
    my $orig = shift;
    my $self = shift;
    my $is_required = $self->$orig(@_);
    return $is_required || $self->primary_key;
};

no Moose::Role;

package Moose::Meta::Attribute::Custom::Trait::DbColumn;
sub register_implementation { 'Socialtext::Moose::SqlTable::Meta::Attribute::Trait::DbColumn' };

1;

=head1 NAME

Socialtext::Moose::SqlTable::Meta::Attribute::Trait::DbColumn - DbColumn attribute trait

=head1 SYNOPSIS

  # check if an attribute is a Db Column
  $is_column = $attr->does('DbColumn');

  # check if an attribute is part of the primary key
  $is_pkey = $attr->primary_key();

=head1 DESCRIPTION

C<Socialtext::Moose::SqlTable::Meta::Attribute::Trait::DbColumn> provides a
C<Moose> attribute trait to assist in building classes that have an underlying
DB table.

Although the guts are implemented here, you'll want to refer to the
documentation in C<Socialtext::Moose::SqlTable> for the additional syntactic
sugar to help you define your table, the primary key, and alternate unique
keys.

=head1 METHODS

=over

=item B<$attr-E<gt>primary_key()>

Returns true if this attribute was flagged as being part of the primary key
for the underlying Db Table.

=item B<$attr-E<gt>is_required()>

Wrapped method; attributes that are marked as being part of the primary key
are also considered required fields.

=back

=head1 COPYRIGHT & LICENSE

Copyright (C) 2009 Socialtext, Inc., All Rights Reserved.

=head1 SEE ALSO

L<Socialtext::Moose::SqlTable>.

=cut
