package Socialtext::Group;
# @COPYRIGHT@
use unmocked 'Moose';

has 'group_id' => (is => 'rw', isa => 'Int', required => 1);

use unmocked 'constant', is_plugin_enabled => 1;

my %Groups;

sub GetGroup {
    my $class = shift;
    return $class->new(@_);
}

1;
