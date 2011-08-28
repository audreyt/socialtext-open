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
    $registry->add(preference => $self->notify_frequency);
    $registry->add(preference => $self->sort_order);
    $registry->add(preference => $self->links_only);
}

our $Default_notify_frequency_in_minutes = 24 * 60;
our $Minimum_notify_frequency_in_minutes = 1;

sub notify_frequency {
    my $self = shift;
    my $p = $self->new_preference('notify_frequency');
    $p->query(__('email.frequency?'));
    $p->type('pulldown');
    my $choices = [
        0 => __('time.never'),
        1 => __('every.minute'),
        5 => __('every.5minutes'),
        15 => __('every.15minutes'),
        60 => __('every.hour'),
        360 => __('every.6hours'),
        1440 => __('every.day'),
        4320 => __('every.3days'),
        10080 => __('every.week'),
    ];
    $p->choices($choices);
    $p->default($Default_notify_frequency_in_minutes);
    return $p;
}

sub sort_order {
    my $self = shift;
    my $p = $self->new_preference('sort_order');
    $p->query(__('email.page-digest-sort?'));
    $p->type('radio');
    my $choices = [
        chrono => __('sort.oldest-first'),
        reverse => __('sort.newest-first'),
        name => __('sort.page-name'),
    ];
    $p->choices($choices);
    $p->default('chrono');
    return $p;
}

sub links_only {
    my $self = shift;
    my $p = $self->new_preference('links_only');
    $p->query(__('email.page-digest-details?'));
    $p->type('radio');
    my $choices = [
        condensed => __('email.page-name-link-only'),
        expanded => __('email.page-name-link-author-date'),
    ];
    $p->choices($choices);
    $p->default('expanded');
    return $p;
}

1;

