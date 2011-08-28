# @COPYRIGHT@
package Socialtext::Events;
use warnings;
use strict;

use Class::Field qw(const);
use Socialtext::HTTP ':codes';
use Socialtext::Events::Recorder;
use Socialtext::Events::Reporter;
use Socialtext::Signal::Render;
use Socialtext::Timer qw/time_scope/;
use List::MoreUtils qw/all/;
use Carp qw/croak/;

our @BlackList;

sub Get {
    my $class = shift;
    my $viewer = shift || croak 'must supply viewer';
    my $reporter = Socialtext::Events::Reporter->new(viewer => $viewer);
    return $reporter->get_events(@_);
}

sub GetActivities {
    my $class = shift;
    my $viewer = shift || croak 'must supply viewer';
    my $user = shift || croak 'must supply user to view (or maybe you just passed in one user to this function)';
    my $reporter = Socialtext::Events::Reporter->new(viewer => $viewer);
    return $reporter->get_events_activities(@_, actor_id => $user);
}

sub GetWorkspaceActivities {
    my $class = shift;
    my $viewer = shift || croak 'must supply viewer';
    my $workspace = shift || croak 'must supply workspace to view';
    my $reporter = Socialtext::Events::Reporter->new(viewer => $viewer);
    return $reporter->get_events_workspace_activities(
        @_, page_workspace_id => $workspace);
}

sub GetGroupActivities {
    my $class = shift;
    my $viewer = shift || croak 'must supply viewer';
    my $group = shift || croak 'must supply group to view';
    my $reporter = Socialtext::Events::Reporter->new(viewer => $viewer);
    return $reporter->get_events_group_activities(
        @_, group_id => $group);
}

sub BlackList {
    my $class = shift;
    @BlackList = @_;
}

sub EventInBlackList {
    my $class = shift;
    my $event = shift;

    return 0 unless @BlackList;

    for my $item (@BlackList) {
        return 1 if all {
            defined $event->{$_} and $event->{$_} eq $item->{$_}
        } keys %$item;
    }

    return 0;
}

sub Record {
    my $class = shift;
    my $ev = shift;
    my $t = time_scope 'record_event';

    return if $class->EventInBlackList($ev);

    my $signal = $ev->{signal};
    if ($signal && ref $signal) {
        $ev->{context}{body} = Socialtext::Signal::Render->new(
            user => $signal->user
        )->render_signal($signal)->{body};
        $ev->{context}{account_ids} = $signal->account_ids;
        $ev->{context}{group_ids} = $signal->group_ids;
        $ev->{context}{uri} = $signal->uri;
        $ev->{signal} = $signal->signal_id;
        if ($ev->{action} ne 'signal') {
            $ev->{context}{creator_id} = $signal->user->user_id;
        }
    }

    if ($ev->{event_class} && $ev->{event_class} eq 'page' &&
        $ev->{page} && ref($ev->{page}))
    {
        my $page = $ev->{page};
        $ev->{actor} ||= $page->hub->current_user;
        $ev->{workspace} ||= $page->hub->current_workspace;
        $ev->{context} ||= {};
        $ev->{context}{revision_count} ||= $page->revision_count;
        $ev->{context}{revision_id} ||= $page->revision_id;

        if ($ev->{signal}) {
            $ev->{context}{account_ids} ||= [ $page->hub->current_workspace->account_id ] ;
        }

        if (my $es = $page->edit_summary) {
            $ev->{context}{edit_summary} ||= $es;
        }

        my $t_page = delete $ev->{target_page};
        my $t_page_workspace = delete $ev->{target_workspace};
        my $t_page_id = $t_page->id if $t_page;
        my $t_ws_name = $t_page_workspace->name if $t_page_workspace;
        $ev->{context}{target_page}{id} = $t_page_id if $t_page_id;
        $ev->{context}{target_page}{workspace_name} = $t_ws_name if $t_ws_name;

        $ev->{context}{summary} = delete $ev->{summary}
            if $ev->{summary};
    }

    my $recorder = Socialtext::Events::Recorder->new;
    return $recorder->record_event($ev);
}

1;
