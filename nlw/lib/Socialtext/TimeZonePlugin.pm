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

    $self->_register_prefs($registry);
}


sub pref_names {
    return qw(
        timezone dst date_display_format
        time_display_12_24 time_display_seconds
    )
}

sub timezone_data {
    my $self = shift;

    my $zones = $self->zones;

    my $options = [
        map { +{setting => $_, display => $zones->{$_}} } sort keys %$zones
    ];

    return {
        title => loc('time.timezone'),
        default_setting => $self->_default_timezone,
        options => $options,
    };
}

sub timezone {
    my $self = shift;

    my $data = $self->timezone_data;
    my $p = $self->new_preference('timezone');

    $p->query($data->{title});
    $p->type('pulldown');
    $p->choices($self->_choices($data));
    $p->default($data->{default_setting});

    return $p;
}

sub dst_data {
    my $self = shift;

    my $default = $self->_default_dst;
    my $options = [
        {setting => 'on', display => __('tz.dst-yes')},
        {setting => 'off', display => __('tz.dst-no')},
        {setting => 'auto-us', display => __('tz.auto-us')},
        {setting => 'never', display => __('tz.dst-never')},
    ];

    return {
        title => loc('time.daylight-savings-summer'),
        default_setting => $self->_default_dst,
        options => $options,
    };
}

sub dst {
    my $self = shift;

    my $data = $self->dst_data;
    my $p = $self->new_preference('dst');

    $p->query($data->{title});
    $p->type('pulldown');
    $p->choices($self->_choices($data));
    $p->default($data->{default_setting});

    return $p;
}

sub date_display_format_data {
    my $self = shift;

    my $time = $self->_now;
    my $locale = $self->hub->best_locale;

    my @raw = Socialtext::Date::l10n->get_all_format_date($locale);
    my @options = ();
    for my $possible (@raw) {
        next if $possible eq 'default';
        my $display_time = $self->_get_date( $time, $possible, $locale );

        push @options, {
            setting => $possible,
            display => $display_time,
        };
    }

    return {
        title => loc('time.date-format'),
        default_setting => $self->_default_date_display_format,
        options => \@options,
    };
}

sub date_display_format {
    my $self   = shift;

    my $data = $self->date_display_format_data;

    my $p = $self->new_dynamic_preference('date_display_format');
    $p->query($data->{title});
    $p->type('pulldown');
    $p->choices_callback(sub {
        my $p = shift;

        $p->default($data->{default_setting});
        return $self->_choices($data);
    });

    return $p;
}

sub time_display_12_24_data {
    my $self = shift;

    my $time = $self->_now;
    my $locale = $self->hub->best_locale;

    my @raw = Socialtext::Date::l10n->get_all_format_time($locale);
    my @options = ();
    for my $possible (@raw) {
        next if $possible eq 'default';
        my $display_time = $self->_get_time( $time, $possible, $locale );

        push @options, {
            setting => $possible,
            display => $display_time,
        };
    }

    return {
        title => loc('time.time-format'),
        default => $self->_default_time_display_12_24,
        options => \@options,
    };
}

sub time_display_12_24 {
    my $self   = shift;

    my $data = $self->time_display_12_24_data;

    my $p = $self->new_dynamic_preference('time_display_12_24');
    $p->query($data->{title});
    $p->type('pulldown');
    $p->choices_callback( sub {
        my $p = shift;

        $p->default($data->{default_setting});
        return $self->_choices($data);
    });

    return $p;
}

sub time_display_seconds_data {
    my $self = shift;
    
    return {
        title => '',
        binary => 1,
        default_setting => 0,
        options => [
            {setting => '1', display => loc('time.include-seconds-in-time-format')},
            {setting => '0', display => loc('time.do-not-include-seconds')},
        ],
    };
}

sub time_display_seconds {
    my $self = shift;

    my $data = $self->time_display_seconds_data;

    my $p = $self->new_preference('time_display_seconds');
    $p->query($data->{options}[0]{display});
    $p->type('boolean');
    $p->default($data->{default_setting});

    return $p;
}

sub _default_timezone {
    my $self = shift;
    my $locale = shift || $self->hub->best_locale;

    if ( $locale eq 'ja' ) {
        return '+0900';
    }
    else {
        return '-0800';
    }
}

sub _default_dst {
    my $self   = shift;
    my $locale = shift || $self->hub->best_locale;

    # Only assume DST is "automatic" if the locale is English.
    if ( $locale and $locale eq 'en' ) {
        return 'auto-us';
    }
    else {
        return 'never';
    }
}

sub _default_date_display_format {
    my $self = shift;
    my $loc = shift || $self->hub->best_locale;

    my $d = Socialtext::Date::l10n->get_date_format($loc, 'default')->pattern;

    my ($format) = grep {
         $_ ne 'default' &&
             Socialtext::Date::l10n->get_date_format($loc, $_)->pattern eq $d
    } Socialtext::Date::l10n->get_all_format_date($loc);

    die "couldn't load a default date_display_format" unless $format;

    return $format;
}

sub _default_time_display_12_24 {
    my $self = shift;
    my $loc = shift || $self->hub->best_locale;

    my $d = Socialtext::Date::l10n->get_time_format($loc, 'default')->pattern;

    my ($format) = grep {
         $_ ne 'default' && 
             Socialtext::Date::l10n->get_time_format($loc, $_)->pattern eq $d
    } Socialtext::Date::l10n->get_all_format_time($loc);

    die "couldn't load a default time_display_12_24" unless $format;

    return $format;
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
