package Socialtext::Pluggable::Plugin::Locales;
# @COPYRIGHT@
use warnings;
use strict;
use Socialtext::l10n qw/loc system_locale loc_lang/;
use Socialtext::Locales qw/available_locales/;
use base 'Socialtext::Pluggable::Plugin';

use constant scope => 'always';
use constant hidden => 1; # hidden to admins
use constant read_only => 0; # cannot be disabled/enabled in the control panel

sub register {
    my $class = shift;

    $class->add_hook('template.st_settings.append' => 'st_settings');
    $class->add_hook("action.language_settings"   => \&language_settings);
}

sub st_settings {
    my $self = shift;

    $self->challenge(type => 'settings_requires_account')
        unless ($self->logged_in);

    my $prefs = $self->get_user_prefs();
    my $locale = $prefs->{locale} // system_locale();
    my $languages = available_locales();

    my @locales = map { +{
        setting => $_,
        display => $languages->{$_},
    } } sort {
        ($languages->{$a} =~ /DEV/ <=> $languages->{$b} =~ /DEV/)
            or ($a cmp $b)
    } keys %$languages;

    return $self->template_render(
        'element/settings/language_settings_section',
        plugin => {
            locales => {
                locale =>  {
                    title => loc('locales.display-language'),
                    default_setting => $locale,
                    options => \@locales,
                },
            },
        },
    );
}

sub language_settings {
    my $self = shift;
    my %cgi_vars = $self->cgi_vars;

    $self->challenge(type => 'settings_requires_account')
        unless ($self->logged_in);

    my $prefs = $self->get_user_prefs();
    my $locale = $prefs->{locale} // '';
    my $system_locale = system_locale();

    my $message = '';
    if ($cgi_vars{Button}) {
        $locale = $cgi_vars{locale} // '';
        $self->set_user_prefs(locale => $locale);
        loc_lang($locale || $system_locale);
        $message = loc('config.saved');
    }

    my $languages = available_locales();
    my $choices = [ map { +{
        value => $_,
        label => $languages->{$_},
        selected => ($locale eq $_),
    }} sort { ($languages->{$a} =~ /DEV/ <=> $languages->{$b} =~ /DEV/) or ($a cmp $b) } grep {
        $_ ne $system_locale
    } keys %$languages ];

    unshift @$choices, {
        value => "",
        label => loc("loc.system-default=lang", $languages->{system_locale()}),
        selected => ($locale eq ''),
    };

    my $settings_section = $self->template_render(
        'element/settings/language_settings_section',
        form_action    => 'language_settings',
        message        => $message,
        locales        => $choices,
    );

    return $self->template_render('view/settings',
        settings_table_id => 'settings-table',
        settings_section  => $settings_section,
        display_title     => loc('loc.settings'),
    );
}

1;
__END__

=head1 NAME

Socialtext::Pluggable::Plugin::Locale

=head1 SYNOPSIS

Per-user localization preferences.

=head1 DESCRIPTION

=cut
