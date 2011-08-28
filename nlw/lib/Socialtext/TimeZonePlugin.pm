# @COPYRIGHT@
package Socialtext::TimeZonePlugin;
use strict;
use warnings;
use base 'Socialtext::Plugin';

use Class::Field qw( const );
use Time::Local ();

use DateTime;

use Socialtext::Date;
use Socialtext::Date::l10n;
use Socialtext::l10n qw(loc __);

const class_id => 'timezone';
const pref_scope => 'global';
const class_title => __('class.timezone');
const dcDATE => 1;
const dcTIME => 2;
const dcDATETIME => 3;

const zones => {
    '-1200'   => __('tz.-1200-west'),
    '-1100'   => __('tz.-1100'),
    '-1000'   => __('tz.-1000'),
    '-0900'   => __('tz.-0900'),
    '-0800'   => __('tz.-0800'),
    '-0700'   => __('tz.-0700'),
    '-0600'   => __('tz.-0600'),
    '-0500'   => __('tz.-0500'),
    '-0400'   => __('tz.-0400'),
    '-0330'   => __('tz.-0330'),
    '-0300'   => __('tz.-0300'),
    '-0200'   => __('tz.-0200'),
    '-0100'   => __('tz.-0100'),
    '+0000'   => __('tz.+0000'),
    '+0100'   => __('tz.+0100'),
    '+0200'   => __('tz.+0200'),
    '+0300'   => __('tz.+0300'),
    '+0330'   => __('tz.+0330'),
    '+0400'   => __('tz.+0400'),
    '+0500'   => __('tz.+0500'),
    '+0530'   => __('tz.+0530'),
    '+0600'   => __('tz.+0600'),
    '+0700'   => __('tz.+0700'),
    '+0800'   => __('tz.+0800'),
    '+0900'   => __('tz.+0900'),
    '+0930'   => __('tz.+0930'),
    '+1000'   => __('tz.+1000'),
    '+1100'   => __('tz.+1100'),
    '+1200id' => __('tz.+1200-east'),
    '+1200nz' => __('tz.+1200'),
};

sub register {
    my $self     = shift;
    my $registry = shift;
    $registry->add( preference => $self->timezone );
    $registry->add( preference => $self->dst );
    $registry->add( preference => $self->date_display_format );
    $registry->add( preference => $self->time_display_12_24 );
    $registry->add( preference => $self->time_display_seconds );
}

sub timezone {
    my $self   = shift;
    my $locale = $self->hub->best_locale;
    my $p      = $self->new_preference('timezone');
    $p->query( __('config.time-zone?') );
    $p->type('pulldown');
    my $zones = $self->zones;
    my $choices = [ map { $_ => $zones->{$_} } sort keys %$zones ];
    $p->choices($choices);
    $p->default( $self->_default_timezone($locale) );
    return $p;
}

sub _default_timezone {
    my $self = shift;
    my $locale = shift;
    if ( $locale eq 'ja' ) {
        return '+0900';
    }
    else {
        return '-0800';
    }
}

sub dst {
    my $self = shift;
    my $p    = $self->new_preference('dst');

    $p->query( __('tz.dst?') );
    $p->type('pulldown');
    my $choices = [
        'on'      => __('tz.dst-yes'),
        'off'     => __('tz.dst-no'),
        'auto-us' => __('tz.auto-us'),
        'never'   => __('tz.dst-never'),
    ];
    $p->choices($choices);


    my $locale = $self->hub->best_locale;
    $p->default( $self->_default_dst($locale) );

    return $p;
}

sub _default_dst {
    my $self   = shift;
    my $locale = shift;

    # Only assume DST is "automatic" if the locale is English.
    if ( $locale and $locale eq 'en' ) {
        return 'auto-us';
    }
    else {
        return 'never';
    }
}

sub date_display_format {
    my $self   = shift;

    my $p = $self->new_dynamic_preference('date_display_format');
    $p->query( __('date.format?') );
    $p->type('pulldown');

    my $time = $self->_now;
    my $hub = $self->hub;
    $p->choices_callback(sub {
        my $p = shift;
        my $choices = [];
        my $locale = $p->hub->best_locale;
        my @formats = Socialtext::Date::l10n->get_all_format_date($locale);
        my $default_pattern = Socialtext::Date::l10n->get_date_format(
            $locale, 'default')->pattern;
        for (@formats) {
            if ( $_ eq 'default' ) {
                next;
            }
            my $format = Socialtext::Date::l10n->get_date_format($locale, $_);
            if ($format->pattern eq $default_pattern) {
                $p->default($_);
            }
            push @{$choices}, $_;
            push @{$choices},
            $self->_get_date( $time, $_, $locale );
        }
        return $choices;
    });

    return $p;
}

sub time_display_12_24 {
    my $self   = shift;
    my $p      = $self->new_dynamic_preference('time_display_12_24');
    $p->query(
        __('date.hour-format?') );

    my $time = $self->_now;
    $p->type('pulldown');
    $p->choices_callback( sub {
        my $p = shift;
        my $locale = $p->hub->best_locale;
        my @formats
            = Socialtext::Date::l10n->get_all_format_time($locale);
        my $default_pattern = Socialtext::Date::l10n->get_time_format(
            $locale, 'default')->pattern;
        my $choices = [];
        for (@formats) {
            if ( $_ eq 'default' ) {
                next;
            }
            my $fmt = Socialtext::Date::l10n->get_time_format($locale, $_);
            if ($fmt->pattern eq $default_pattern) {
                $p->default($_);
            }
            push @{$choices}, $_;
            push @{$choices}, $self->_get_time( $time, $_, $locale );
        }
        return $choices;
    });

    return $p;
}

sub time_display_seconds {
    my $self = shift;
    my $p    = $self->new_preference('time_display_seconds');
    $p->query( __('date.include-seconds?') );
    $p->type('boolean');
    $p->default(0);
    return $p;
}

sub _timezone_offset {
    my $self     = shift;
    my $datetime     = shift;
    my $timezone = $self->preferences->timezone->value;

    # XXX This must be checked for passing, before we use $2 or $3
    $timezone =~ /([-+])(\d\d)(\d\d)/;
    my $offset = ( ( $2 * 60 ) + $3 ) * 60;
    $offset *= -1 if $1 eq '-';
    return $offset;
}

sub _dst_offset {
    my $self = shift;
    my $datetime     = shift;
    my $dst = $self->preferences->dst->value;

    my $time = $datetime->epoch;
    my $isdst = ( localtime($time) )[8];

    my $offset =
          $dst eq 'on' ? 3600
        : ( $dst eq 'auto-us' and $isdst ) ? 3600
        : 0;

    return $offset;
}

sub date_local_epoch {
    my $self = shift;
    my $epoch = shift;

    my $locale = $self->hub->best_locale;

    return unless defined $epoch;

    # Make sure we have a valid time.
    $epoch =~ /^\d+$/
        or return $epoch;

    my ( $sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst) = gmtime($epoch);

    # XXX to be fixed. in timezone_seconds, adjust time for dst.
    # Now, the routine is deleted, so must adjust in this.
    my $datetime = DateTime->new(
        year      => $year+1900,
        month     => $month+1,
        day       => $mday,
        hour      => $hour,
        minute    => $min,
        second    => $sec,
        time_zone => 'UTC'
    );
    return $self->get_date_user($datetime);
}

sub date_local {
    my $self = shift;
    my $date = shift;
    my %opts = @_;

    my $locale = $self->hub->best_locale;

    return unless defined $date;

    # We seems to have some bad data in the system, so the best we can
    # do is just return the date as is, since trying to localize it
    # will probably just mangle it even worse-.
    $date =~ /(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/
        or return $date;

    my ( $year, $mon, $mday, $hour, $min, $sec ) = ( $1, $2, $3, $4, $5, $6 );

    # XXX to be fixed. in timezone_seconds, adjust time for dst.
    # Now, the routine is deleted, so must adjust in this.
    my $datetime = DateTime->new(
        year      => $year,
        month     => $mon,
        day       => $mday,
        hour      => $hour,
        minute    => $min,
        second    => $sec,
        time_zone => 'UTC'
    );
    return $opts{dateonly} ? $self->get_dateonly_user($datetime)
                           : $self->get_date_user($datetime);
}

sub time_local {
    my $self = shift;
    my $date = shift;

    my $locale = $self->hub->best_locale;

    return unless defined $date;

    # We seems to have some bad data in the system, so the best we can
    # do is just return the date as is, since trying to localize it
    # will probably just mangle it even worse-.
    $date =~ /(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/
        or return $date;

    my ( $year, $mon, $mday, $hour, $min, $sec ) = ( $1, $2, $3, $4, $5, $6 );

    # XXX to be fixed. in timezone_seconds, adjust time for dst.
    # Now, the routine is deleted, so must adjust in this.
    my $datetime = DateTime->new(
        year      => $year,
        month     => $mon,
        day       => $mday,
        hour      => $hour,
        minute    => $min,
        second    => $sec,
        time_zone => 'UTC'
    );
    return $self->get_time_user($datetime);
}

# Returns both date and time
sub get_date_user {
    my $self  = shift;
    my $time  = shift;

    $self->get_date(
        $time,
        $self->dcDATETIME,
    );
}

sub get_time_user {
    my $self  = shift;
    my $time  = shift;

    $self->get_date(
        $time,
        $self->dcTIME
    );
}

sub get_dateonly_user {
    my $self  = shift;
    my $time  = shift;

    $self->get_date(
        $time,
        $self->dcDATE
    );
}

# Time needs to be UTC
sub get_date {
    my $self       = shift;
    my $time       = shift;
    my $components = shift || $self->dcDATETIME;

    # We futz with the time object later on, so let's use our own
    $time = $time->clone();

    my $prefs = $self->preferences;

    my $date_display_format  = $prefs->date_display_format->value;
    my $time_display_12_24   = $prefs->time_display_12_24->value;
    my $time_display_seconds = $prefs->time_display_seconds->value;
    my $timezone = $prefs->timezone->value;

    my ( $d, $t );

    my $locale = $self->hub->best_locale;

    # $time->add is slow, so only do it once here
    my $offset = $self->_timezone_offset($time) + $self->_dst_offset($time);
    $time->add( seconds => $offset );

    if ($components & $self->dcDATE) {
        # When display year is not equal this year,
        # the formats skipped year must be added year (ref. %WithYear).
        my $now = $self->_now;
        if ($time->year != $now->year){
            $date_display_format = Socialtext::Date::l10n->get_date_to_year_key_map( $date_display_format, $locale );
        }

        $d = $self->_get_date( $time, $date_display_format, $locale );
    }

    if ($components & $self->dcTIME) {
        my $time_display_format = $time_display_12_24;
        if ($time_display_seconds) {
            $t = $self->_get_time_sec( $time, $time_display_format, $locale );
        }else {
            $t = $self->_get_time( $time, $time_display_format, $locale );
        }
    }

    if ($components == $self->dcDATETIME) {
        return "$d $t";
    }
    elsif ($components == $self->dcDATE) {
        return $d;
    }
    else {
        return $t;
    }
}

sub _get_date {
    my $self = shift;
    my ($time, $date_display_format, $locale) = @_;

    # DateTime parameter '%e' replace leading 0 to space. (when the value is single number)
    # Cut the space.
    my $date_str = Socialtext::Date::l10n->get_formated_date(
        $time,
        $date_display_format,
        $locale
    );
    $date_str =~ s/\s(\d[^\d]+)/$1/g;
    $date_str =~ s/\s(\s)/$1/g;

    return $date_str;
}

sub _get_time {
    my $self = shift;
    my ($time, $time_display_format, $locale) = @_;

    my $time_str = Socialtext::Date::l10n->get_formated_time(
        $time,
        $time_display_format,
        $locale
    );

    # DateTime parameter '%e' replace leading 0 to space. (when the value is single number)
    # Cut the space.
    $time_str =~ s/\s(\d[^\d])/$1/g;
    $time_str =~ s/\s(\s)/$1/g;

    return $time_str;
}

sub _get_time_sec {
    my $self = shift;
    my ($time, $time_display_format, $locale) = @_;

    my $time_str = Socialtext::Date::l10n->get_formated_time_sec(
        $time,
        $time_display_format,
        $locale
    );

    # DateTime parameter '%e' replace leading 0 to space. (when the value is single number)
    # Cut the space.
    $time_str =~ s/\s(\d[^\d])/$1/g;
    $time_str =~ s/\s(\s)/$1/g;

    return $time_str;
}

sub _now {
    my $self = shift;
    return Socialtext::Date->now( timezone => 'UTC' );
}

sub timezone_seconds {
    my $self     = shift;
    my $time     = shift || time;
    my $timezone = $self->preferences->timezone->value;

    # XXX This must be checked for passing, before we use $2 or $3
    $timezone =~ /([-+])(\d\d)(\d\d)/;
    my $offset = ( ( $2 * 60 ) + $3 ) * 60;
    $offset *= -1 if $1 eq '-';

    my $dst = $self->preferences->dst->value;

    my $isdst = ( localtime($time) )[8];

    $offset +=
          $dst eq 'on' ? 3600
        : ( $dst eq 'auto-us' and $isdst ) ? 3600
        : 0;

    return $offset;
}

1;
