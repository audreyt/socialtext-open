# @COPYRIGHT@
package Test::Socialtext::Thrower;
use strict;
use warnings;

use base 'Socialtext::Plugin';

sub class_id { 'thrower' }

sub register
{
    my $registry = shift;

    $registry->add(action => 'throw1');
    $registry->add(action => 'throw2');
}

sub throw1
{
    die 'A simple exception';
}

sub throw2
{
    die { key1 => 'a ref as an exception' };
}

1;

