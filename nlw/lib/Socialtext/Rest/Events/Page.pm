package Socialtext::Rest::Events::Page;
# @COPYRIGHT@
use warnings;
use strict;
use base 'Socialtext::Rest::EventsBase';

use Socialtext::l10n 'loc';

sub collection_name {
    my $self = shift;
    return loc("rest.events=page,wiki", 
                $self->hub->pages->current->title,
                $self->hub->current_workspace->title);
}

sub events_auth_method { 'page' }

sub get_resource {
    my $self = shift;
    my $rest = shift;
    my $content_type = shift;

    my %args = $self->extract_common_args;

    $args{page_id} = $self->hub->pages->current->id;
    $args{page_workspace_id} = $self->hub->current_workspace->workspace_id;
    $args{event_class} = 'page';

    my $events = Socialtext::Events::Reporter->new(viewer => $self->hub->current_user)->get_events(%args);
    $events ||= [];
    return $events;
}

1;
