package Apache::Cookie;
# @COPYRIGHT@
use strict;
use warnings;

our $DATA = {};

# keep track of cookies that have been created
my @cookies;
sub clear_cookies { @cookies = (); }
sub cookie_count  { return scalar @cookies; }
sub next_cookie   { return shift @cookies; }

sub new {
    my ($class, $req, %opts) = @_;
    my $self = { %opts };
    push @cookies, $self;
    bless $self, $class;
}

sub value {
    my $self = shift;
    return wantarray ? %{ $self->{value} } : $self->{value};
}

sub fetch {
    return $DATA;
}

sub bake { 1 };

1;
