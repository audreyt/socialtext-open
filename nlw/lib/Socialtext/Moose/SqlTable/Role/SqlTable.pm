package Socialtext::Moose::SqlTable::Role::SqlTable;

use Moose::Role;

sub primary_key {
    my $self = shift;
    my %pkey =
        map { $_->name => $_->get_value($self) }
        $self->meta->get_primary_key_attributes();
    return \%pkey;
}

no Moose::Role;
1;

=head1 NAME

Socialtext::Moose::SqlTable::Role::SqlTable - SqlTable Role

=head1 SYNOPSIS

  # get hash-ref containing primary key for this record
  $pkey = $record->primary_key();

=head1 DESCRIPTION

C<Socialtext::Moose::SqlTable::Role::SqlTable> implements a C<Moose> Role for
SqlTable objects; data objects that have an underlying Db Table.

=head1 METHODS

=over

=item B<primary_key()>

Returns a hash-ref containing the key/value pairs that represent the primary
key for this particular data record.

=back

=head1 COPYRIGHT & LICENSE

Copyright (C) 2009 Socialtext, Inc., All Rights Reserved.

=head1 SEE ALSO

L<Socialtext::Moose::SqlTable>.

=cut
