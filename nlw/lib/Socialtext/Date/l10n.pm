# @COPYRIGHT@
package Socialtext::Date::l10n;
use strict;
use warnings;
use utf8;

use DateTime::Format::Strptime;
use DateTime::TimeZone;
use Socialtext::Date::l10n::en;

sub get_formated_date {
    my $self = shift;
    my ( $date, $key, $locale ) = @_;

    my $df = $self->get_date_format($locale, $key);
    return $df->format_datetime($date);
}


sub get_date_format {
    my $self   = shift;
    my $locale = shift;
    my $key    = shift;

    return $self->_delegate(get_date_format => $locale, $key);
}

sub get_date_to_year_key_map {
    my $self = shift;
    my ( $key, $locale ) = @_;

    return $self->_delegate(get_date_to_year_key_map => $locale, $key);
}

sub get_time_format {
    my $self   = shift;
    my $locale = shift;
    my $key    = shift;

    return $self->_delegate(get_time_format => $locale, $key);
}

sub get_formated_time {
    my $self = shift;
    my ( $time, $key, $locale ) = @_;

    my $df = $self->get_time_format($locale, $key);
    return $df->format_datetime($time);
}

sub get_formated_time_sec {
    my $self = shift;
    my ( $time, $key, $locale ) = @_;

    my $df = $self->_delegate(get_time_sec_format => $locale, $key);;
    return $df->format_datetime($time);
}

sub get_all_format_date {
    my $self = shift;
    my ($locale) = @_;

    return $self->_delegate(get_date_format_keys => $locale);;
}

sub get_all_format_time {
    my $self = shift;
    my ($locale) = @_;

    return $self->_delegate(get_time_format_keys => $locale);;
}

sub _delegate {
    my $self   = shift;
    my $method = shift;
    my $locale = shift;

    local $@;
    my $class = 'Socialtext::Date::l10n::' . $locale;
    $class = 'Socialtext::Date::l10n::en' unless eval { require "Socialtext/Date/l10n/$locale.pm" };
    return $class->$method(@_);
}

1;

