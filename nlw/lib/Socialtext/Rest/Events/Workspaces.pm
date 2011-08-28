package Socialtext::Rest::Events::Workspaces;
use Moose;
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::Exceptions;
use Socialtext::l10n 'loc';
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::EventsBase';

sub collection_name { 
    my $self = shift;
    return loc("rest.activity=user", $self->_workspace->title);
}

sub get_resource {
    my ($self, $rest) = @_;
    my $user = $self->rest->user;

    unless ($user->is_business_admin || $self->_workspace->has_user($user)) {
        Socialtext::Exception::Auth->throw();
    }

    return Socialtext::Events->GetWorkspaceActivities(
        $user, $self->workspace, $self->extract_common_args(),
    ) || [];
}

has '_workspace' => (
    is => 'ro', isa => 'Socialtext::Workspace', lazy_build => 1,
);
sub _build__workspace {
    my $self = shift;
    my $name = $self->ws;
    return Socialtext::Workspace->new(name => $name) ||
        Socialtext::Exception::NoSuchResource->throw(
            name => "workspace $name",
        );
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::Events::Groups - Activity stream for a group.

=head1 SYNOPSIS

    GET /data/events/groups/:group_id

=head1 DESCRIPTION

View the activity stream for the group.

=cut
