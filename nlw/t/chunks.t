#!perl
# @COPYRIGHT@
# This is just a test to make sure Test::Base works under NLW test
# framework.

use strict;
use warnings;

use Test::Socialtext tests => 8;

filters('upper');

run {
    my $block = shift;
    is($block->abc, $block->xyz, $block->name);
    like($block->abc, qr{^I WANT TO}, 'Data is sane');
    unlike( $block->abc, qr/[a-z]/, 'Test abc is all upper' );
    unlike( $block->xyz, qr/[a-z]/, 'Test xyz is all upper' );
};

sub Test::Base::Filter::upper {
    my $class = shift;
    return uc(shift);
}

__DATA__



=== Test One
--- abc 
I want to bite your neck.
--- xyz
I Want To Bite Your Neck.



=== Test Two
--- xyz
I WaNt To BuY NeW YoRk!
--- abc
i wAnT tO bUy nEw yOrK!


