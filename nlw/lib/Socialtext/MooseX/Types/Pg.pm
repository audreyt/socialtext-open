package Socialtext::MooseX::Types::Pg;
# @COPYRIGHT@
use strict;
use warnings;
use Moose::Util::TypeConstraints;
use Socialtext::SQL qw(:time);
use namespace::clean -except => 'meta';

subtype 'Pg.DateTime'
    => as 'DateTime';

coerce 'Pg.DateTime'
    => from 'Str'
    => via { sql_parse_timestamptz($_) };

coerce 'Str'
    => from 'Pg.DateTime'
    => via { sql_format_timestamptz($_) };

coerce 'Pg.DateTime'
    => from 'Int'
    => via { DateTime->from_epoch(epoch => $_) };

coerce 'Int'
    => from 'Pg.DateTime'
    => via { $_->epoch() };

1;

=head1 NAME

Socialtext::MooseX::Types::Pg - Moose type definitions for PostgreSQL

=head1 SYNOPSIS

  package MyPackage;
  use Moose;
  use Socialtext::MooseX::Types::Pg;

  has 'when' => (
    is => 'rw', isa => 'Pg.DateTime', coerce => 1
  );

=head1 DESCRIPTION

C<Socialtext::MooseX::Types::Pg> provides a selection of Moose subtypes for
use in conjunction with PostgreSQL as your DB storage.

=head1 TYPES / COERCIONS

=head2 Pg.DateTime

A derived version of C<DateTime>, namespaced to make it obvious that we're
coercing to/from Pg.

Coercions provided:

=over

=item from Str

Converts the C<DateTime> object to a string, suitable for handing off to
PostgreSQL as a TimestampTZ.

=item from Int

Converts the C<DateTime> object to an integer (representing the "number of
seconds since the epoch").  Any sub-second resolution present in the
C<DateTime> object is lost as part of this coercion.

=item to Str

Converts a PostgreSQL TimestampTZ string into a C<DateTime> object.

=item to Int

Converts an integer (representing the "number of seconds since the epoch") to
a C<DateTime> object.

=back

=head1 AUTHOR

Socialtext, Inc.,  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc.,  All Rights Reserved.

=cut
