package Apache;
# @COPYRIGHT@
use strict;
use warnings;

use mocked 'Apache::Request';
use mocked 'Apache::Constants';

sub new {
    my ($class, %opts) = @_;
    my $self = { %opts };
    bless $self, $class;
}

sub request {
    my $class = shift;
    return Apache::Request->new(@_);
}

1;
