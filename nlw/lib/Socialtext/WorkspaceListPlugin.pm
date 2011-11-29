package Socialtext::WorkspaceListPlugin;
# @COPYRIGHT@
use strict;
use warnings;
use Class::Field qw(const);
use Socialtext::l10n qw(loc __ lcmp);
use Socialtext::SQL qw(:time);
use Socialtext::Workspace;

use base 'Socialtext::Plugin';

const class_id    => 'workspace_list';
const class_title => __('class.workspace_list');

sub WORKSPACE_LIST_SIZE { 10 }

sub register {
    my $self = shift;
    my $registry = shift;

    $registry->add(action => 'widget_workspace_list');
    $registry->add(action => 'workspace_membership');
}

sub workspace_membership {
    my $self = shift;

    my $ws = $self->hub->current_workspace;
    my @uwr = sort { lcmp($a->[0]->best_full_name, $b->[0]->best_full_name) }
        $ws->user_roles(direct => 1)->all;

    my @users = ();
    foreach my $ur (@uwr) {
        my $edit = $ws->last_edit_for_user($ur->[0]->user_id);
        $edit->{local_edit_time}
            = $edit->{edit_time}
            ? $self->hub->timezone->get_date_user(
            sql_parse_timestamptz($edit->{edit_time}))
            : '';
            
        push @users, { 
            name => $ur->[0]->best_full_name(workspace =>$ws),
            username => $ur->[0]->username,
            id => $ur->[0]->user_id,
            role => $ur->[1]->name,
            last_edit => $edit,
        };
    }

    my $iter = $ws->groups;
    my @gwr = $ws->group_roles->all;
    my @groups = ();
    foreach my $gr (@gwr) {
        push @groups, { 
            name => $gr->[0]->name,
            id => $gr->[0]->group_id,
            role => $gr->[1]->name,
        };
    }

    return $self->template_render(
       template => 'view/workspace_membership',
       vars     => {
           $self->hub->helpers->global_template_vars,
           users => \@users,
           groups => \@groups,
           workspace => $ws,
       },
   );
}

sub widget_workspace_list {
    my $self = shift;
    return $self->template_render(
       template => 'view/widget_workspace_list',
       vars     => {
           $self->hub->helpers->global_template_vars,
           action            => 'widget_workspace_list',
           my_workspaces     => [ $self->my_workspaces ],
           public_workspaces => [ $self->public_workspaces ],
           link_target => '_blank',
       },
   );
}

sub my_workspaces {
    my $self = shift;

    # get the list of workspaces that the logged in user is a member of
    my $user = $self->hub->current_user();
    my @workspaces;
    my $it = $user->workspaces();
    while (my $ws = $it->next) {
        push @workspaces, [ $ws->name, $ws->title ];
    }

    return @workspaces;
}

sub public_workspaces {
    my $self = shift;

    # get the list of public workspaces:
    # - "help"
    # - "hand-picked list of ws by admin" (TODO)
    # - "most often accessed public workspaces last week"
    my @available = Socialtext::Workspace->MostOftenAccessedLastWeek;

    my $ws_help = Socialtext::Workspace->help_workspace();
    unshift @available, [$ws_help->name, $ws_help->title] if $ws_help;

    # trim list to max length, and remove duplicates
    my %seen;
    my @workspaces;
    while (@available) {
        my $ws = shift @available;
        next if ($seen{ $ws->[0] }++);
        push @workspaces, $ws;
        last if (scalar(@workspaces) == WORKSPACE_LIST_SIZE);
    }

    return @workspaces;
}

1;
