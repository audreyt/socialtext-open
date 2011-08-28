# @COPYRIGHT@
package Socialtext::Indexes;
use strict;
use warnings;

use base 'Socialtext::Base';

use Class::Field qw( field );
use Socialtext::MLDBMAccess;

sub class_id { 'indexes' }
field index_class => '';

sub new_for_class {
    my $self = shift;
    $self = $self->new(hub => shift);
    $self->init;
    $self->index_class(shift);
    $self->assert_index;
}

sub read {
    my $self = shift;
    return
        Socialtext::MLDBMAccess::mldbm_access(
            $self->index_path($self->index_class),
            shift,
        ) || {};
}

sub add {
    my $self = shift;
    $self->update_delegate('add', @_);
};

sub delete {
    my $self = shift;
    $self->update_delegate('delete', @_);
};

sub update {
    my $self = shift;
    $self->update_delegate('update', @_);
};

sub update_delegate {
    my $self = shift;
    my $index_class = $self->index_class;
    my $index_method= 'index_' . shift;
    my $db_file = $self->index_path($self->index_class);
    my $db = Socialtext::MLDBMAccess::tied_hashref( filename => $db_file, writing => 1 );
    $self->hub->$index_class->$index_method($db, @_);
}

sub read_only_hash {
    my $self = shift;
    my $db_file = $self->index_path($self->index_class);
    return Socialtext::MLDBMAccess::tied_hashref( filename => $db_file );
}

sub assert_index {
    my $self = shift;
    my $index_class = $self->index_class;
    my $db_file = $self->index_path($index_class);

    if (not -f $db_file) {
        my $hash = $self->hub->$index_class->index_generate;
        my $db = Socialtext::MLDBMAccess::tied_hashref( filename => $db_file, writing => 1 );
        %$db = %$hash;
    }
    return $self;
}

sub index_path {
    my $self = shift;
    my $db_name = shift;
    $self->plugin_directory . '/' . $db_name . '.db';
}

1;

