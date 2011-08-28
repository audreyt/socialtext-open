package Socialtext::Headers;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::MockBase';
use unmocked 'Data::Dumper';
use unmocked 'Class::Field', 'field';
use unmocked 'Socialtext::HTTP', ':codes';

field 'status' => HTTP_200_OK;

our $REDIRECT;

sub redirect {
    my $self = shift;
    $REDIRECT = shift;
}

1;
