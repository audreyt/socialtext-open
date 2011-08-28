#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 2;
fixtures( 'db' );

use Socialtext::User;

my $singapore = join '', map { chr($_) } 26032, 21152, 22369;
my $pw = $singapore . '12345';

my $user = eval {
    Socialtext::User->create(
        username      => 'joebob',
        email_address => 'joebob@example.com',
        password      => $pw,
    );
};
is( $@, '', 'created a new user with a utf8 pw' );
ok( $user->password_is_correct($pw), 'utf8 password matches' )
