# @COPYRIGHT@
package Socialtext::Registry;
use strict;
use warnings;

use base 'Socialtext::Base';

use Carp ();
use Class::Field qw( const field );

sub class_id { 'registry' }
const lookup_class => 'Socialtext::Lookup';

field 'lookup';
field 'temp_lookup';
field 'current_class_id';

my %LookupCache;

sub add {
    my $self = shift;
    my ( $key, $value ) = @_;
    return $self->_add(@_)
        unless $key eq 'preference'
        and @_ == 2;
    return $self->_add( $key, $value->id, object => $value );
}

sub append {
    my ( $self, $key, $value ) = @_;

    my $class_id = $self->current_class_id;

    Carp::confess( "key given to Socialtext::Registry->add was undef" )
        unless defined $key;

    Carp::confess( "cannot call Socialtext::Registry->add when Socialtext::Registry->current_class_id is not defined" )
        unless defined $class_id;

    push @{ $self->temp_lookup->{$key}{$value} }, $class_id;

    push @{ $self->temp_lookup->{add_order}{$class_id}{$key} }, $value;
}

sub load {
    my $self = shift;
    my $lookup = $self->_update->lookup;
    $self->lookup( bless $lookup, $self->lookup_class );
    return $self->lookup;
}

# Was Socialtext::Registry->add, left as a separate method for clarity
sub _add {
    my $self  = shift;
    my $key   = shift;
    my $value = shift;

    my $class_id = $self->current_class_id;

    Carp::confess( "key given to Socialtext::Registry->add was undef" )
        unless defined $key;

    Carp::confess( "cannot call Socialtext::Registry->add when Socialtext::Registry->current_class_id is not defined" )
        unless defined $class_id;

    $self->temp_lookup->{$key}{$value} = [ $class_id, @_ ];
    push @{ $self->temp_lookup->{add_order}{$class_id}{$key} }, $value;
}

sub _load_class {
    my $self = shift;
    my $class_name = shift;
    unless ( $class_name->can('new') ) {
        eval "require $class_name";
        die "require $class_name failed: $@" if $@;
    }
    $class_name->new( hub => $self->hub );
}

sub _not_a_plugin {
    my $self = shift;
    my $class_name = shift;
    die <<END;

Error:
$class_name is not a plugin class.
END
}

sub _plugin_redefined {
    my $self = shift;
    my ( $class_id, $class_name, $prev_name ) = @_;
    die <<END if $class_name eq $prev_name;

Error:
Plugin class $class_name defined twice.
END
    die <<END;

Error:
Can't use two plugins with the same class id.
$prev_name and $class_name both have a class id of '$class_id'.
END
}

sub _set_class_info {
    my $self = shift;
    my $object     = shift;
    my $lookup     = $self->temp_lookup;
    my $class_name = ref $object;
    my $class_id   = $object->class_id
        or die "No class_id for $class_name\n";
    if ( my $prev_name = $lookup->{classes}{$class_id} ) {
        $self->_plugin_redefined( $class_id, $class_name, $prev_name );
    }
    $lookup->{classes}{$class_id} = $class_name;
    push @{ $lookup->{plugins} }, {
        id    => $class_id,
        title => $object->class_title,
        pref_scope => $object->pref_scope,
    };
    return $class_id;
}

sub _update {
    my $self = shift;
    my @plugin_classes = $self->hub->plugin_classes;

    if ( exists $LookupCache{"@plugin_classes"} ) {
        my %cached_lookup = %{ $LookupCache{"@plugin_classes"} };
        $self->temp_lookup( \%cached_lookup );
    }
    else {
        $self->temp_lookup( {} );

        for my $class_name (@plugin_classes) {
            my $object = $self->_load_class($class_name);
            $self->_not_a_plugin($class_name)
                unless $object->can('register');
            my $class_id = $self->_set_class_info($object);
            $self->current_class_id($class_id);
            $object->register($self);
        }
        my %cached_lookup = %{ $self->temp_lookup };
        $LookupCache{"@plugin_classes"} = \%cached_lookup;
    }

    $self->lookup( $self->temp_lookup );

    return $self;
}


######################################################################
package Socialtext::Lookup;

use base 'Socialtext::Base';
use Class::Field qw( field );

field action          => {};
field add_order       => {};
field classes         => {};
field plugins         => [];
field preference      => {};
field preload         => {};
field tool            => {};
field wafl            => {};

1;

__END__

=head1 NAME

Socialtext::Registry - NLW Registry 

=head1 SYNOPSIS

The Registry contains information about L<Socialtext::Plugin> classes
and the functions they have registered to perform.

=head1 DESCRIPTION

An L<Socialtext::Plugin> associates one or more named pieces of desired
functionality with an instance of NLW. The Registry provides a
dictionary from name to the class that satisfies the functionality.

=head1 METHODS

=over 4

=item add

Adds information to the Registry via register() in L<Socialtext::Plugin>.
See L<Socialtext::Plugin> for information on what may be added and how.

=item load

Make the Registry available to the current request so all functionality
is available. This is called near the beginning of a session.

=back

=head1 AUTHOR

Brian Ingerson <INGY@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2004. Brian Ingerson. All rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
