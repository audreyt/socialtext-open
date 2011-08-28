package Socialtext::Prefs::System;
use Moose;
use Socialtext::SQL qw(sql_singlevalue sql_execute);
use Socialtext::Date::l10n;
use Socialtext::AppConfig;
use List::Util qw(first);

with 'Socialtext::Prefs';

sub _get_blob {
    return sql_singlevalue(qq{
        SELECT value
          FROM "System"
         WHERE field = 'pref_blob'
    });
}

sub _get_inherited_prefs {
    my $self = shift;
    my $locale = Socialtext::AppConfig->locale;

    return +{
        timezone => {
            timezone => timezone($locale),
            dst => dst($locale),
            date_display_format => date_display_format($locale),
            time_display_12_24 => time_display_12_24($locale),
            time_display_seconds => time_display_seconds($locale),
        },
    };
}

sub _update_db {
    my $self = shift;
    my $blob = shift;

    sql_execute('DELETE FROM "System" WHERE field = ?', 'pref_blob');
    return unless $blob;

    sql_execute(
        'INSERT INTO "System" (field,value) VALUES (?,?)',
        'pref_blob', $blob
    );
}

sub _update_objects {
    my $self = shift;
    my $blob = shift;

    $self->_clear_all_prefs;
    $self->_clear_prefs;
}

sub timezone { # XXX: stolen from ST::TimeZonePlugin
    my $loc = shift;
    return $loc eq 'ja' ? '+0900' : '-0800';
}

sub dst { # XXX: stolen from ST::TimeZonePlugin
    my $loc = shift;
    return $loc eq 'en' ? 'auto-us' : 'never';
}

sub time_display_seconds { return '0' }

sub date_display_format {
    my $loc = shift;
    my $default = Socialtext::Date::l10n->get_date_format($loc, 'default');
    my @formats = grep { $_ ne 'default' }
        Socialtext::Date::l10n->get_all_format_date($loc);

    return first {
        Socialtext::Date::l10n->get_date_format($loc, $_)->pattern
            eq $default->pattern;
    } @formats;
}

sub time_display_12_24 {
    my $loc = shift;
    my $default = Socialtext::Date::l10n->get_time_format($loc, 'default');
    my @formats = grep { $_ ne 'default' }
        Socialtext::Date::l10n->get_all_format_time($loc);

    return first {
        Socialtext::Date::l10n->get_time_format($loc, $_)->pattern
            eq $default->pattern;
    } @formats;
}

__PACKAGE__->meta->make_immutable();
1;

=head1 NAME

Socialtext::Prefs::System - An index of preferences for the System.

=head1 SYNOPSIS

    use Socialtext::Prefs::System

    my $acct_prefs = Socialtext::Prefs::System->new();

    $acct_prefs->prefs; # all prefs
    $acct_prefs->all_prefs; # alias of prefs()
    $acct_prefs->save({new_index=>{key1=>'value1',key2=>'value2'}});

=head1 DESCRIPTION

Manage System preferences.

=cut
