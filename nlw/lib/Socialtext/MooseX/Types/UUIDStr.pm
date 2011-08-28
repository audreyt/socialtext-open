package Socialtext::MooseX::Types::UUIDStr;
use warnings;
use strict;
use Moose::Util::TypeConstraints;

subtype 'Str.UUID'
    => as 'Str'
    # e.g. dfd6fd31-e518-41ca-ad5a-6e06bc46f1dd
    => where { /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i }
    => message { "invalid UUID" };

no Moose::Util::TypeConstraints;
1;

__END__

=head1 NAME

Socialtext::MooseX::Types::UUIDStr - type constraint for UUIDs

=head1 SYNOPSIS

  package MyPackage;
  use Moose;
  use Socialtext::MooseX::Types::UUIDStr;

  has 'when' => (
    is => 'rw', isa => 'Str.UUID'
  );

=head1 DESCRIPTION

Type-checks for well-formed hex-with-dashes UUID strings.

=head1 TYPES / COERCIONS

=head2 Str.UUID

Coercions provided: none

=head1 AUTHOR

Socialtext, Inc.,  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2011 Socialtext, Inc.,  All Rights Reserved.

=cut
