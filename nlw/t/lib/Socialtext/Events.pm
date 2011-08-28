package Socialtext::Events;
# @COPYRIGHT@
use strict;
use warnings;
use unmocked 'Exporter';
use unmocked 'Exporter::Heavy';
use unmocked 'Test::More';
use base 'Exporter';
use base 'Socialtext::MockBase';
our @EXPORT_OK = qw/clear_events event_ok is_event_count/;

our @Events;
our @GetArgs;

sub Get { 
    my $class = shift; 
    push @GetArgs, [@_];
    return pop @Events;
}

sub Record { push @Events, $_[1] }

sub event_ok {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my %expected = @_;
    my $event = shift @Events;

    foreach my $key (keys %expected) {
        if (ref($event->{$key})) {
            is_deeply $event->{$key}, $expected{$key}, "event key '$key'";
        }
        else {
            is $event->{$key}, $expected{$key}, "event key '$key'";
        }
    }
}

sub is_event_count {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is scalar(@Events), $_[0], 'event count';
}

sub clear_get_args {
    #warn "clearing Get args";
    @GetArgs = ();
}

sub clear_events {
    @Events  = ();
    @GetArgs = ();
}

1;
