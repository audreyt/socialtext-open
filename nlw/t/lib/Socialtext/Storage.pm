package Socialtext::Storage;
# @COPYRIGHT@
use strict;
use warnings;

our %DATA;
our $ALLOW_NOT_PRELOADED = {};

sub new {
    my ($class, $id) = @_;
    return bless {
        id => $id,
        _preloaded => {},
    }, $class;
}

sub id { $_[0]{id} }

sub preload {
    my $self = shift;
    $self->{_preloaded} = { map { $_ => 1 } @_ };
}

sub Search {
    my ($class, %terms) = @_;
    my ($id) = grep {
        my $s_id = $_;
        keys %terms == grep {
            exists $DATA{$s_id}{$_} and $DATA{$s_id}{$_} eq $terms{$_}
        } keys %terms
    } keys %DATA;
    return $class->new($id) if $id;
}

sub exists {
    my ($self, $key) = @_;
    return exists $DATA{$self->{id}}{$key};
}

sub get {
    my ($self, $key) = @_;

    # Socialtext::Storage works a lot better if all required values are 
    # preloaded using Socialtext::Storage::preload. This means that all the 
    # important key/value pairs are fetched in one statement instead of one 
    # per key. The unmocked Socialtext::Storage doesn't die here, so to get
    # around this check, just add the key to $ALLOW_NOT_PRELOADED, or fix the
    # code to preload the value.
    # unless ($self->{_preloaded}{$key} or $ALLOW_NOT_PRELOADED->{$key}) {
    #    croak "$key was not preloaded!";
    # }
    return $DATA{$self->{id}}{$key};
}

sub set {
    my ($self, $key, $value) = @_;
    return $DATA{$self->{id}}{$key} = $value;
}

sub remove {
    my ($self) = @_;
    $DATA{$self->{id}} = {};
}

sub purge { $_[0]->remove }

sub _data {
    my $self = shift;
    return $DATA{$self->{id}};
}

sub keys {
    my ($self) = @_;
    return keys %{ $DATA{$self->{id}} };
}

1;
