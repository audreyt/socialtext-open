package Socialtext::MockBase;
# @COPYRIGHT@
use strict;
use warnings;
use unmocked 'Carp', qw/confess/;

sub new {
    my $class = shift;
    confess "Expected an even number of args" if @_ % 2;
    my $self = { @_ };
    bless $self, $class;
    return $self;
}

1;
