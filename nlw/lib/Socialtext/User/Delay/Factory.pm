package Socialtext::User::Delay::Factory;
# @COPYRIGHT@

use strict;
use warnings;

use base qw(Socialtext::User::Factory);

use Class::Field qw(const field);
use Time::HiRes qw(sleep);
use Socialtext::Log qw(st_log);

const 'driver_name' => 'Delay';
field 'driver_key', -init => '$self->driver_name . ":" . $self->driver_id';
field 'driver_id', -init => '0.10';

sub new {
    my ($class, $delay) = @_;
    my $self  = { driver_id => $delay };
    bless $self, $class;
}

sub _do_delay {
    my $self  = shift;
    my $delay = $self->driver_id;
    sleep( $delay );
}

sub Count {
    my $self = shift;
    st_log->debug( "ST::User::Delay::Factory->Count()" );
    $self->_do_delay();
    return 0;
}

sub GetUser {
    my $self = shift;
    my $key  = shift;
    my $val  = shift;
    st_log->debug( "ST::User::Delay::Factory->GetUser($key => $val)" );
    $self->_do_delay();
    return;
}

sub Search {
    my $self = shift;
    my $term = shift;
    st_log->debug( "ST::User::Delay::Factory->Search($term)" );
    $self->_do_delay();
    return;
}

1;

=head1 NAME

Socialtext::User::Delay::Factory - User factory that adds time delays

=head1 SYNOPSIS

  # add the "Delay" factory to your list of user_factories
  st-config set user_factories "Delay;Default"

=head1 DESCRIPTION

C<Socialtext::User::Delay::Factory> provides a dummy User factory that adds a
time delay to all user instantiation/search requests.

B<This should NOT be used in a production environment.>

It is, however, useful for helping do some latency and timing tests, by adding
a small delay (0.10s) to user requests.

=head1 METHODS

=over

=item B<Socialtext::User::Delay::Factory-E<gt>new()>

Creates a new Delay user factory.

=item B<driver_name()>

Returns the name of the driver this Factory implements, "Delay".

=item B<driver_key()>

Returns the unique ID of the driver instance used by this Factory.  This
Factory has only B<one> instance, so this is the same as L</driver_name()>.

=item B<Socialtext::User::Delay::Factory-E<gt>Count()>

Causes a delay and logs a debug entry to F<nlw.log>.

=item B<GetUser($key, $val)>

Causes a delay and logs a debug entry to F<nlw.log>.

=item B<Socialtext::User::Delay::Factory-E<gt>Search($term)>

Causes a delay and logs a debug entry to F<nlw.log>.

=back

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Socialtext, Inc., All Rights Reserved.

=cut
