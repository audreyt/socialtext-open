# @COPYRIGHT@
package Socialtext::UserPreferencesPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';
use Socialtext::l10n qw( loc loc_lang __ );
use Socialtext::Locales qw( valid_code );

use Class::Field qw( const field );
use Socialtext::Exceptions qw( data_validation_error );
use Socialtext::String ();

use Socialtext::JobCreator;

const class_id => 'user_preferences';
const class_title => __('class.user_preferences');
const cgi_class => 'Socialtext::UserPreferences::CGI';
field 'user_id';
field preference_list => [];

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add( action => 'preferences_settings' );
}

sub preferences_settings {
    my $self = shift;

    $self->reject_guest(type => 'settings_requires_account');

    my $class_id = $self->cgi->preferences_class_id;
    if ( $class_id eq '' ) {
        my $message = loc("error.no-preference-class-id");
        data_validation_error errors => [$message];
    }

    my $list
        = $self->hub->registry->lookup->add_order->{$class_id}{preference}
        or die "No preference key for $class_id in add_order";

    my $object = $self->hub->$class_id;

    if ( $self->cgi->Button ) {
        $self->save($object);
        $self->message(loc('pref.saved'));
    }

    my $prefs = $self->preferences->new_for_user($self->hub->current_user);

    my @pref_list = map { $prefs->$_ } @$list;
    my $settings_section = $self->template_process(
        'element/settings/preferences_settings_section',
        preference_list => \@pref_list,
        $self->status_messages_for_template,
    );

    my $ws = $self->hub->current_workspace;
    my $scope = $ws && $ws->real ? 'workspace' : 'global';

    $self->screen_template('view/settings');
    return $self->render_screen(
        settings_table_id => 'settings-table',
        settings_section  => $settings_section,
        hub               => $self->hub,
        display_title     => loc('pref.for-class=title', $object->class_title),
        pref_list         => $self->_get_pref_list($scope),
    );
}

sub _is_favorites_page_title_valid {
    my $self = shift;
    my $name = shift;

    if ( Socialtext::String::MAX_PAGE_ID_LEN
         < length Socialtext::String::title_to_id($name) ) {
        return 0;
    }
    return 1;
}

# XXX this method may not have test coverage
sub save {
    my $self = shift;
    my $object = shift;

    my %cgi = $self->cgi->vars;

    my $user  = $self->hub->current_user;
    my $prefs = $self->hub->preferences->new_for_user($user);

    my $settings = {};
    my $class_id = $object->class_id;
    for my $key (sort keys %cgi) {
        my $value = $cgi{$key};
        next unless ($key =~ /^${class_id}__(.*)/);
        my $pref = $1;
        $pref =~ s/-boolean$//;

        # immediately show the new locale if it is changed
        if ($pref eq 'locale') {
            if (valid_code($value)) {
                loc_lang($value);
            }
            else {
                # Find the old locale to re-save from pkg name
                ($value = ref(loc_lang)) =~ s/.+:://;
            }
        }

        my $job_type;
        if ($class_id eq 'email_notify' and $pref eq 'notify_frequency') {
            $job_type = 'Socialtext::Job::EmailNotifyUser';
        }
        elsif ($class_id eq 'watchlist' and $pref eq 'watchlist_notify_frequency') {
            $job_type = 'Socialtext::Job::WatchlistNotifyUser';
        }

        if ($job_type) {
            my $old_val = $prefs->{$pref}->value;
            my $ws_id = $self->hub->current_workspace->workspace_id;
            my $user_id = $self->hub->current_user->user_id;
            my $seconds = ($value - $old_val) * 60;

            if ($value == 0) {
                Socialtext::JobCreator->cancel_job(
                    funcname => $job_type,
                    uniqkey => "$ws_id-$user_id",
                );
            }
            elsif ($seconds != 0) {
                Socialtext::JobCreator->move_jobs_by(
                    funcname => $job_type,
                    uniqkey => "$ws_id-$user_id",
                    seconds => $seconds,
                );
            }
        }

        $settings->{$pref} = $value
          unless exists $settings->{$pref};

        if( $class_id eq 'favorites' ) {
            if(! $self->_is_favorites_page_title_valid($settings->{$pref})) {
                my $message = loc("error.page-title-too-long");
                $self->add_error($message);
                return;
            }
        }
    }
    if (keys %$settings) {
        $self->preferences->store( $user, $class_id, $settings );
    }
}

package Socialtext::UserPreferences::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'Button';
cgi 'preferences_class_id';

1;

