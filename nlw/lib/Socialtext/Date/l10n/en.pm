# @COPYRIGHT@
package Socialtext::Date::l10n::en;
use strict;
use utf8;

use DateTime::Format::Strptime;
use DateTime::TimeZone;

my $date_format = {
    'default' => DateTime::Format::Strptime->new(
        pattern   => '%b %e, %Y',
        locale    => 'en',
    ),

    'mmm_d_yyyy' => DateTime::Format::Strptime->new(
        pattern   => '%b %e, %Y',
        locale    => 'en',
    ),

    'd_mmm_yy' => DateTime::Format::Strptime->new(
        pattern   => '%e-%b-%y',
        locale    => 'en',
    ),

    'yyyy_mm_dd' => DateTime::Format::Strptime->new(
        pattern   => '%Y-%m-%d',
        locale    => 'en',
    ),
};

my $date_to_year_key_map = {
    'mmm_d' => 'mmm_d_yyyy',
    'd_mmm' => 'd_mmm_yy',
    'mm_dd' => 'yyyy_mm_dd',
};

my $time_format = {
    'default' => DateTime::Format::Strptime->new(
        pattern   => '%l:%M%P',
        locale    => 'en',
    ),

    '12' => DateTime::Format::Strptime->new(
        pattern   => '%l:%M%P',
        locale    => 'en',
    ),

    '24' => DateTime::Format::Strptime->new(
        pattern   => '%H:%M',
        locale    => 'en',
    ),

};

my $time_sec_format = {
    'default' => DateTime::Format::Strptime->new(
        pattern   => '%l:%M:%S%P',
        locale    => 'en',
    ),

    '12' => DateTime::Format::Strptime->new(
        pattern   => '%l:%M:%S%P',
        locale    => 'en',
    ),

    '24' => DateTime::Format::Strptime->new(
        pattern   => '%H:%M:%S',
        locale    => 'en',
    ),
};

sub get_date_format_keys {
    my $self = shift;

    return keys %$date_format;
}

sub get_time_format_keys {
    my $self = shift;

    return keys %$time_format;
}

sub get_date_format {
    my $self = shift;
    my $key  = shift;

    my $df = $date_format->{$key};
    if (! defined $df){
       return $date_format->{'default'};
    }
    return $df;
}

sub get_date_to_year_key_map {
    my $self = shift;
    my $key = shift;

    my $newkey = $date_to_year_key_map->{$key};
    if (! defined $newkey){
        return $key;
    }
    return $newkey;
}

sub get_time_format {
    my $self = shift;
    my $key  = shift;

    my $df = $time_format->{$key};
    if (! defined $df){
       return $time_format->{'default'};
    }
    return $df;
}

sub get_time_sec_format {
    my $self = shift;
    my $key  = shift;

    my $df = $time_sec_format->{$key};
    if (! defined $df){
       return $time_sec_format->{'default'};
    }
    return $df;
}

1;

__END__

=head1 NAME

Socialtext::Date::l10n::en - Date formatting for English language

=head1 SYNOPSIS

    use Socialtext::Date::l10n;
    my $date = Socialtext::Date::l10n->get_formated_date(
        $time, $format, 'en'
    );

=head1 DESCRIPTION

Internal module used by L<Socialtext::Date::l10n>; no user-serviceable parts inside.

=cut
