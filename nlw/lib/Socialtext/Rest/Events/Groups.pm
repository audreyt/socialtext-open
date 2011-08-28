package Socialtext::Rest::Events::Groups;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::Rest::EventsBase';
use Socialtext::Permission qw/ST_READ_PERM/;
use Socialtext::Exceptions;

use Socialtext::l10n 'loc';

sub collection_name { 
    my $self = shift;
    return loc("rest.activity=user", $self->_group->display_name);
}

sub get_resource {
    my ($self, $rest) = @_;
    my $viewer = $self->rest->user;

    # fake it like it was a param too (instead of just a placeholder)
    $self->rest->query->param('group_id',$self->group_id);

    # Permission check is done in extract_common_args:
    my @args = $self->extract_common_args();
    my $events = Socialtext::Events->GetGroupActivities($viewer, $self->_group);
    $events ||= [];
    return $events;
}

sub _group { # called outside of this file
    my $self = shift;
    return Socialtext::Group->GetGroup(group_id => $self->group_id);
}

1;

=head1 NAME

Socialtext::Rest::Events::Groups - Activity stream for a group.

=head1 SYNOPSIS

    GET /data/events/groups/:group_id

=head1 DESCRIPTION

View the activity stream for the group.

=cut
