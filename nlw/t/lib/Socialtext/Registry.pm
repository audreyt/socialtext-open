package Socialtext::Registry;
# @COPYRIGHT@
use strict;
use warnings;

use unmocked qw(Class::Field field);
use unmocked qw(Data::Dumper);

field 'hub';

sub new { bless {}, $_[0] }
sub add {
    my ($self, $type, $name, $class) = @_;

    if ($type eq 'wafl') {
        $class ||= caller[0];
        $self->{$type}{$name} = sub {
            my $obj = $class->new;
            $obj->method($name);
            $obj->hub($self->hub);
            return $obj->html();
        };
    }
    elsif ($type eq 'action') {
        $class ||= caller[0];
        $self->{$type}{$name} = sub {
            return $self->hub->pluggable->$name
        };
    }
    else {
        die "Mocked Socialtext::Registry doesn't know how to create a $type";
    }
}
sub call {
    my ($self, $type, $name) = @_;
    my $sub = $self->{$type}{$name} || die "no $type named $name";
    return $sub->();
}

1;
