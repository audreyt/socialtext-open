package Test::WWW::Selenium;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Exporter';
use unmocked 'Test::More';

our @EXPORT_OK = '$SEL';

our $SEL; # singleton

sub new {
    my ($class, %opts) = @_;
    if ($SEL) {
        $SEL->{args} = \%opts;
        return $SEL;
    }
    $SEL = { args => \%opts };
    bless $SEL, $class;
    return $SEL;
}

sub set_return_value {
    my ($self, $name, $return) = @_;
    push @{$self->{return}{$name}}, $return;
}

sub method_args_ok {
    my ($self, $name, $expected) = @_;
#    warn Data::Dumper::Dumper $self;
    unless (defined $self->{$name}) {
        die "$name is not defined!";
    }
    unless (ref($self->{$name}) eq 'ARRAY') {
        die "$name is a $self->{$name}";
    }
    my $actual = shift @{$self->{$name}};
    if ($expected and $expected ne '*') {
        is_deeply $actual, $expected;
    }
}

sub empty_ok {
    my $self = shift;
    my $ignore_extra = shift;

    my %skip = map { $_ => 1 } qw/return args browser_start_command/;
    for my $k (keys %$self) {
        next if $skip{$k};
        next if ref($self->{$k}) eq 'ARRAY' and @{$self->{$k}} == 0;
        if ($ignore_extra) {
            delete $self->{$k};
        }
        else {
            my $args = delete $self->{$k};
            if (ref($args) eq 'ARRAY') {
                $args = join(', ', @$args);
            }
            ok 0, "extra call to $k - ($args)";
        }
    }
    $self->{return} = {};
}

our $AUTOLOAD;
sub AUTOLOAD {
    my $name = $AUTOLOAD;
    $name =~ s/.+:://;
    return if $name eq 'DESTROY';

    my ($self, $opt1, $opt2) = @_;
    if ($opt2) {
        push @{$self->{$name}}, [$opt1, $opt2];
    }
    else {
        push @{$self->{$name}}, $opt1;
    }

    if ($self->{return}{$name}) {
        return shift @{$self->{return}{$name}};
    }
    return;
}


1;
