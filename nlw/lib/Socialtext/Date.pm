package Socialtext::Date;
# @COPYRIGHT@
use warnings;
use strict;
use base qw( DateTime );

use Encode;
use DateTime::Format::Strptime;
use DateTime::TimeZone;
use Time::HiRes ();

# for XXX-debugging:
sub yaml_dump {
    my $self = shift;
    return {
        iso8601 => $self->hires_iso8601,
        epoch   => $self->hires_epoch,
    };
}

sub parse {
    my ( $class, $format, $date ) = @_;

    my $module;
    if ( ref $format ) {
        $module = $format;
    }
    else {
	eval "require DateTime::Format::$format;";
	die $@ if $@;
    }

    my $dt = $module->parse_datetime($date) or return;
    bless $dt, $class;
}

sub strptime {
    my ( $class, $pattern, $date, $timezone ) = @_;
    Encode::_utf8_on($pattern);
    my $format = DateTime::Format::Strptime->new(
        pattern => $pattern,timezone => $timezone );
    $class->parse( $format, $date );
}

sub now {
    my ( $class, %opt ) = @_;
    my $self;
    if ($opt{hires}) {
        $self = $class->SUPER::from_epoch(epoch => Time::HiRes::time());
    }
    else {
        $self = $class->SUPER::now();
    }

    # Default timezone should be set from server pref.
    my $tz = $opt{timezone} || 'local';
    $self->set_time_zone($tz);

    $self;
}

sub from_epoch {
    my $class = shift;
    my %p = @_ == 1 ? ( epoch => $_[0] ) : @_;
    $class->SUPER::from_epoch(%p);
}

sub hires_iso8601 { $_[0]->strftime('%F %T.%6N%z') }

sub format {
    my ( $self, $format ) = @_;

    my $module;
    if ( ref $format ) {
        $module = $format;
    }
    else {
	eval "require DateTime::Format::$format;";
	die $@ if $@;
    }

    $module->format_datetime($self);
}

sub set_time_zone {
    my $self = shift;

    eval { $self->SUPER::set_time_zone(@_); };
    # Default timezone should be set from server pref.
    if ($@) {
        $self->SUPER::set_time_zone('UTC');
    }

    return $self;
}

1;

__END__

