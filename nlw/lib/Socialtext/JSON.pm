package Socialtext::JSON;
use 5.12.0;
use warnings;
use JSON::XS qw();
use Encode ();

# Export our methods.
use base qw(Exporter);
our @EXPORT_OK = qw(
    encode_json decode_json decode_json_utf8
    json_bool json_true json_false
);
our @EXPORT = qw(
    encode_json decode_json
    json_bool json_true json_false
);

sub encode_json {
    state $encoder //= JSON::XS->new->ascii->allow_nonref;
    return $encoder->encode($_[0]);
}

# was "sub decode_json"; now is a pass-through
*decode_json = \&JSON::XS::decode_json;

sub decode_json_utf8 {
    # JSON::XS won't properly decode UTF-8 unless it's the raw bytes.  If a
    # string is marked with the utf8 flag, turning it off is a
    # cheap-and-cheerful way to do this. However, since we're doing it on
    # $_[0], it has the side-effect of changing the flag on the original
    # scalar.
    Encode::_utf8_off($_[0]) if Encode::is_utf8($_[0]);
    goto &JSON::XS::decode_json;
}

*json_true = \&JSON::XS::true;
*json_false = \&JSON::XS::false;

sub json_bool { $_[0] ? JSON::XS::true : JSON::XS::false }

1;

=head1 NAME

Socialtext::JSON - JSON en/decoding routines

=head1 SYNOPSIS

  use Socialtext::JSON;

  $utf8_encoded_json_text = encode_json( $perl_hash_or_arrayref );
  $perl_hash_or_arrayref  = decode_json( $utf8_encoded_json_text );

=head1 DESCRIPTION

C<Socialtext::JSON> provides a single point of entry for JSON en/decoding
routines.  JSON support in Perl has been notorious for having differing
implementations, and as a programmer there's always some sense of having to
use "the flavour of the month".

Thus, C<Socialtext::JSON>.  Use it, and if/when we ever decide we need to
change the way that we're handling JSON data, we've only got to do it in
B<one> place.

=head1 METHODS

The C<encode_json> and C<decode_json> functions are exported automatically.

=over

=item B<encode_json($anything)>

Converts the given Perl data structure to a UTF-8 encoded, binary string (that
is, the string contains octets only).  Croaks on error (e.g. if the parameter
contains objects).

=item B<decode_json($utf8_encoded_json_text)>

Opposite of C<encode_json()>; expects a UTF-8 encoded, binary string and ties
to parse that as UTF-8 encoded JSON text returning the resulting reference.
Croaks on error.  The utf8 flag should be turned off on the string.

=item B<decode_json_utf8($any_json_text)>

If the string has its utf8 flag on, this function forces the flag B<off> on
the original scalar.  This is in order to make JSON::XS happy when the flag
happens to be on.  Otherwise, this does the same thing as C<decode_json>.

=item B<json_true>

=item B<json_false>

Special tokens for true/false json literals. (e.g. C<< {"thingy":true} >>)

=item B<json_bool($val)>

Returns the json_true/json_false token based on the perl boolean value of
C<$val>.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008-2010 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
