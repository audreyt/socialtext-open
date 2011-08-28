package LWP::UserAgent;
# @COPYRIGHT@
use strict;
use warnings;
use HTTP::Response;

our $VERSION = 5.999;
our %RESULTS;
our %ARGS;

sub new {
    my ($class, %args) = @_;
    my $self = {};
    bless $self, $class;
    return $self;
}

sub agent {
    my ($self, $agent_string) = @_;
    return $self->{_agent} = $agent_string;
}

*head = \&get;
*post = \&get;
sub get {
    my ($self, $url, $args) = @_;
    $ARGS{$url} = $args;
    return HTTP::Response->new($RESULTS{$url} || 404);
}

sub default_headers { }

1;
