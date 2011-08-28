package Socialtext::Job::Upgrade::RebuildPageLinks;
# @COPYRIGHT@
use Moose;
use Socialtext::l10n qw/loc loc_lang system_locale/;
use Socialtext::PageLinks;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

# This can take a while, especially for super huge workspaces. Never retry.
override 'keep_exit_status_for' => sub { 3600 * 32 };
override 'grab_for'             => sub { 3600 * 16 };
override 'max_retries'          => sub {0};

# Re-parsing all the content for each page can take a long time, so
# we should not allow many of these jobs to run at the same time so that we
# do not stall the ceq queue
sub is_long_running { 1 }

sub do_work {
    my $self = shift;
    my $ws   = $self->workspace or return;
    my $hub  = $self->hub or return;

    return $self->completed unless $ws->real;

    my $ws_name = $ws->name;
    $self->hub->log->info("Rebuilding page links for workspace: $ws_name");

    for my $page ($self->hub->pages->all) {
        my $links = Socialtext::PageLinks->new(hub => $hub, page => $page);
        $links->update;
    }

    $self->completed();
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::Upgrade::RebuildPageLinks - Rebuild a workspace's page links

=head1 SYNOPSIS

    use Socialtext::JobCreator;

    Socialtext::JobCreator->insert(
        'Socialtext::Job::Upgrade::RebuildPageLinks',
        {
            workspace_id => 1,
        },
    );

=head1 DESCRIPTION

Schedule a job to be run by TheCeq which will rebuild all of a workspace's
links (including backlinks). The legacy filesystem based links are unlinked
after all links have been updated or added to the database.

=cut
