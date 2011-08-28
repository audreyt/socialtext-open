# @COPYRIGHT@
package Socialtext::Encode;
use strict;
use warnings;
use base 'Exporter';

use Encode;
use Encode::Guess;
use Socialtext::Validate qw[validate SCALAR_TYPE];
use Carp qw/carp croak/;

our @GUESSES = qw( cp1252 );

our @EXPORT_OK = qw(ensure_is_utf8 ensure_ref_is_utf8);

sub is_valid_utf8 {
    my $copy = shift;
    Encode::_utf8_on($copy); # XXX darnit!  is there a less-ugly way to do this?
    return Encode::is_utf8($copy, 1);
}

sub noisy_decode {
    my %args = validate @_, {
        input => SCALAR_TYPE,
        blame => SCALAR_TYPE,
    };
    return guess_decode($args{input}, $args{blame}, 'noisy');
}

sub ensure_is_utf8 ($) {
    my $bytes = shift;
    return Encode::is_utf8($bytes)
           ? $bytes
           : Encode::decode_utf8($bytes);
}

sub ensure_ref_is_utf8 ($) {
    my $ref = shift;
    return if Encode::is_utf8($$ref);
    $$ref = Encode::decode_utf8($$ref);
    return $ref;
}

sub guess_decode {
    my $bytes = shift;
    my $blame = shift || join (':',caller);
    my $noisy = shift || 0;

    # it's "probably" utf8
    if (is_valid_utf8($bytes)) {
        return Encode::decode_utf8($bytes);
    }
    else {
        carp "$blame: doesn't seem to be valid utf-8" if $noisy;
        my $guess = Encode::Guess::guess_encoding($bytes, @GUESSES);

        unless (ref($guess)) {
            if ($guess =~ /^(\S+) or /) {
                my $best_guess = $1;
                carp "$blame: Treating as $best_guess" if $noisy;
                return Encode::decode($best_guess,$bytes);
            }
            else {
                carp "$blame: non decodable bytes:". 
                    join('',map {sprintf '%02x',$_} unpack('C*',$bytes));
                croak "$blame: bad string encoding: $guess";
            }
        }
        carp "$blame: Treating as " . $guess->name if $noisy;
        return $guess->decode($bytes);
    }
}

1;
