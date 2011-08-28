package Socialtext::Job::Upgrade::SaveOldDefaultDashboard;
# @COPYRIGHT@
use Moose;
use Socialtext::SQL qw/sql_execute/;
use Socialtext::Gadgets::Container::AccountDashboard;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

# Dashboard layout to save for each account
my @old_default_gadgets = (
    {
        src => 'local:widgets:one_page',
        col => 0,
        prefs => [
            [ workspace_name => 'help' ],
            [ page_title => 'learning_resources' ],
        ],
    },
    {
        src => 'local:widgets:one_page',
        col => 0,
        prefs => [
            [ workspace_name => 'help' ],
            [ page_title => 'welcome' ],
        ],
    },
    { src => 'local:widgets:activities.xml', col => 1 },
    { src => 'local:widgets:my_workspaces', col => 2 },
    { src => 'local:widgets:active_members', col => 2 },
    { src => 'local:widgets:top_content', col => 2 },
);

sub do_work {
    my $self = shift;

    my $account_id = $self->account->account_id;

    # Check if the dashboard already exists
    my $container = Socialtext::Gadgets::Container::AccountDashboard->Fetch(
        viewer => Socialtext::User->SystemUser,
        owner  => Socialtext::Account->new(account_id => $account_id),
        name   => 'default',
        no_create => 1,
    );
    return $self->completed if $container;

    # Create the account dashboard
    $container = Socialtext::Gadgets::Container::AccountDashboard->Fetch(
        viewer => Socialtext::User->SystemUser,
        owner  => Socialtext::Account->new(account_id => $account_id),
        name   => 'default',
        no_gadgets => 1,
    );

    # Install default widgets
    for my $gadget (@old_default_gadgets) {
        Socialtext::Gadgets::GadgetInstance->Install(
            container_id => $container->container_id,
            viewer => Socialtext::User->SystemUser,
            %$gadget,
        );
    }

    $self->completed();
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::Upgrade::SaveOldDefaultDashboard - Save old layouts

=head1 SYNOPSIS

    use Socialtext::Migration::Utils qw/create_job/;
    create_job('SaveOldDefaultDashboard');
    exit 0;

=head1 DESCRIPTION

Schedule a job to be run by TheCeq which will save the old default dashboard for each existing account.

=cut
