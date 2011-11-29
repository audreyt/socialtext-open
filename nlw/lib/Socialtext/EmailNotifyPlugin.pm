# @COPYRIGHT@
package Socialtext::EmailNotifyPlugin;
use strict;
use warnings;
use base 'Socialtext::Plugin';
use Class::Field qw( const field );
use Socialtext::EmailNotifier;
use Socialtext::l10n qw( loc loc_lang system_locale __ );

const class_id => 'email_notify';
const class_title => __('class.email_notify');
field abstracts => [];
field 'lock_handle';
field notify_requested => 0;

sub register {
    my $self = shift;
    my $registry = shift;

    $self->_register_prefs($registry);
}

our $Default_notify_frequency_in_minutes = 24 * 60;
our $Minimum_notify_frequency_in_minutes = 1;

sub pref_names {
    return qw(notify_frequency sort_order links_only);
}

sub notify_frequency_data {
    my $self = shift;

    return {
        title => loc('email.frequency-of-updates'),
        default_setting => $Default_notify_frequency_in_minutes,
        options => [
            {setting => 0, display => __('time.never')},
            {setting => 1, display => __('every.minute')},
            {setting => 5, display => __('every.5minutes')},
            {setting => 15, display => __('every.15minutes')},
            {setting => 60, display => __('every.hour')},
            {setting => 360, display => __('every.6hours')},
            {setting => 1440, display => __('every.day')},
            {setting => 4320, display => __('every.3days')},
            {setting => 10080, display => __('every.week')},
        ],
    };
}

sub notify_frequency {
    my $self = shift;

    my $data = $self->notify_frequency_data;
    my $p = $self->new_preference('notify_frequency');

    $p->query($data->{title});
    $p->type('pulldown');
    $p->choices($self->_choices($data));
    $p->default($data->{default_setting});

    return $p;
}

sub sort_order_data {
    my $self = shift;

    return {
        title => loc('email.sort-order-of-updates'),
        default_setting => 'chrono',
        options => [
            {setting => 'chrono', display => __('sort.oldest-first')},
            {setting => 'reverse', display => __('sort.newest-first')},
            {setting => 'name', display => __('sort.page-name')},
        ],
    };
}

sub sort_order {
    my $self = shift;

    my $data = $self->sort_order_data;
    my $p = $self->new_preference('sort_order');

    $p->query($data->{title});
    $p->type('radio');
    $p->choices($self->_choices($data));
    $p->default($data->{default_setting});

    return $p;
}

sub links_only_data {
    my $self = shift;

    return {
        title => loc('email.digest-information'),
        default_setting => 'expanded',
        options => [
            {setting => 'condensed', display => __('email.page-name-link-only')},
            {setting => 'expanded', display => __('email.page-name-link-author-date')},
        ],
    };
}

sub links_only {
    my $self = shift;

    my $data = $self->links_only_data;
    my $p = $self->new_preference('links_only');

    $p->query($data->{title});
    $p->type('radio');
    $p->choices($self->_choices($data));
    $p->default($data->{default_setting});

    return $p;
}

1;

