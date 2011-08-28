#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::More tests => 17;
use Socialtext::Validate qw':all :types';

my %in = (
    a  => 'sdf',
    b  => $^X,
    c  => 'https://foo.com',
    d  => 'http://foo.com',
    d2 => 'https://foo.com',
    e  => 'bob@foo.com',
    f  => 1,
    g  => '/tmp',
    h  => 5058223172,
    h2 => 0,
    i  => qr/foobar/,
    j  => 'foobar',
);
my %p = validate @{ [%in] }, {
    a  => SCALAR_TYPE,
    b  => FILE_TYPE,
    c  => SECURE_URI_TYPE,
    d  => URI_TYPE,
    d2 => URI_TYPE,
    e  => EMAIL_TYPE,
    f  => BOOLEAN_TYPE,
    g  => DIR_TYPE,
    h  => POSITIVE_INT_TYPE,
    h2 => NONNEGATIVE_INT_TYPE,
    i  => REGEX_TYPE,
    j  => REGEX_TYPE,
};

while ( my ( $k, $v ) = each %in ) {
    my @p = ( $k => $v );
    my %p = eval { validate( @p, { $k => $in{$k} } ) };
    ok !$@, "validate() succeeded for $v";
}

{
    my @p = ();
    my %p = validate( @p, { foo => SCALAR_TYPE( default => 'foo' ) } );
    is( $p{foo}, 'foo', 'can pass extra args to type subs' );
}

{
    my @p = ( file => '/etc' );
    eval { validate( @p, { file => FILE_TYPE } ) };
    like( $@, qr/is valid file path/, 'FILE_TYPE fails when file points to dir' );
}

{
    my @p = ( dir => '/etc/passwd' );
    eval { validate( @p, { dir => DIR_TYPE } ) };
    like( $@, qr/is valid directory path/, 'DIR_TYPE fails when dir points to file' );
}

{
    my @p = ( email => 'this.is.not.valid@' );
    eval { validate( @p, { email => EMAIL_TYPE } ) };
    like( $@, qr/is valid email address/,
          'EMAIL_TYPE failes with invalid email address' );
}

{
    my @p = ( regex => bless { foo => 'this is not a regex .*' }, 'Foo' );
    eval { validate( @p, { regex => REGEX_TYPE } ) };
    like( $@, qr/is a regex/,
          'REGEX_TYPE failes with a non-regex object' );
}
