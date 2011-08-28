package Socialtext::Job::EmailNotify;
# @COPYRIGHT@
use Moose;
use Socialtext::PreferencesPlugin;
use Socialtext::EmailNotifyPlugin;
use Socialtext::Timer qw/time_scope/;
use namespace::clean -except => 'meta';
use List::Util 'max';

extends 'Socialtext::Job';

sub _should_run_on_page {
    my $self = shift;
    return $self->workspace->email_notify_is_enabled;
}

sub _user_job_class {
    return "Socialtext::Job::EmailNotifyUser";
}

sub _default_freq {
    return $Socialtext::EmailNotifyPlugin::Default_notify_frequency_in_minutes;
}

sub _minimum_freq {
    return $Socialtext::EmailNotifyPlugin::Minimum_notify_frequency_in_minutes;
}

sub _pref_name {
    return 'notify_frequency';
}

sub do_work {
    my $self = shift;
    my $page = $self->page or return;
    my $ws = $self->workspace or return;
    my $hub = $self->hub;

    my $pages_after = $self->arg->{modified_time};
    die "no modified_time supplied" unless defined $pages_after;

    my $ws_id = $ws->workspace_id;

    return $self->completed unless $self->workspace->email_notify_is_enabled;

    return $self->completed if $page->is_system_page;
    return $self->completed unless $page->is_recently_modified($pages_after);


    $hub->log->info( "Sending recent changes notifications from ".$ws->name );

    my @jobs;
    my $job_class = $self->_user_job_class;
    my $create_job = sub {
        my $user_id = shift;
        my $freq = shift;
        my $after = $pages_after + $freq;
        push @jobs, {
            run_after => $after,
            uniqkey => "$ws_id-$user_id",
            arg => "$user_id-$ws_id-$pages_after",
        };

        # Debug only
        # $hub->log->info( "UserID $user_id has freq $freq");
    };

    my $default_freq = $self->_default_freq * 60;

    # Grab all the users with no workspace preference
    No_workspace_pref: {
        my $t = time_scope 'no_ws_pref';
        my $no_pref
            = Socialtext::PreferencesPlugin->Users_with_no_prefs_for_ws($ws_id);
        for my $user_id (@$no_pref) {
            $create_job->($user_id, $default_freq);
        }
    }

    # Now grab all the users that do have workspace prefs
    # Note: this may grab users that are not in the workspace, but this
    # condition will be tested by the job itself.
    Has_workspace_pref: {
        my $t = time_scope 'has_ws_pref';
        my $prefs = Socialtext::PreferencesPlugin->Prefblobs_for_ws($ws_id);
        my $pref_name = $self->_pref_name;
        for my $pref (@$prefs) {
            my ($user_id, $blob) = @$pref;

            my $freq = $default_freq;
            if ($blob and $blob =~ m/"\Q$pref_name\E":"(\d+)"/ and $1 > 0) {
                $freq = max(int($1), $self->_minimum_freq) * 60;
            }
            $create_job->($user_id, $freq) if $freq;
        }
    }


    Inserting_jobs: {
        my $t = time_scope 'insert_jobs';
        $hub->log->info("Creating " . scalar(@jobs) . " new $job_class jobs for workspace $ws_id");
        $self->job->client->bulk_insert(
            TheSchwartz::Moosified::Job->new(
                funcname => $job_class,
                priority => -64,
            ),
            \@jobs,
            ignore_errors => 1,
        );
    }

    $self->completed;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;
