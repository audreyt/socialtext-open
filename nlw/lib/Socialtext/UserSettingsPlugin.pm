# @COPYRIGHT@
package Socialtext::UserSettingsPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

use Class::Field qw( const field );
use Socialtext::AppConfig;
use Socialtext::EmailSender::Factory;
use Socialtext::Permission qw( ST_ADMIN_WORKSPACE_PERM );
use Socialtext::TT2::Renderer;
use Socialtext::User;
use Socialtext::Group;
use Socialtext::WorkspaceInvitation;
use Socialtext::GroupInvitation;
use Socialtext::URI;
use Socialtext::l10n qw(:all);
use Socialtext::Helpers;

sub class_id {'user_settings'}
const cgi_class => 'Socialtext::UserSettings::CGI';
field 'users_new_ids';
field users_already_present => [];

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add( action => 'settings' );
    $registry->add( action => 'users_settings' );
    $registry->add( action => 'users_listall' );
    $registry->add( action => 'users_invitation' );
    $registry->add( action => 'users_invite' );
    $registry->add( action => 'users_search' );
}

# for backwards compat
sub settings {
    my $self = shift;
    $self->redirect('action=users_settings');
}

sub users_settings {
    my $self = shift;

    $self->reject_guest(type => 'settings_requires_account');

    $self->_update_current_user()
        if $self->cgi->Button;

    my $settings_section = $self->template_process(
        'element/settings/users_settings_section',
        user => $self->hub->current_user,
        $self->status_messages_for_template,
    );

    return $self->_render_settings(
        loc('config.user-settings'),
        $settings_section,
    );
}

sub _obfuscate_passwords {
    my $self = shift;
    $self->hub->rest->query->param(-name => 'old_password', -value => 'xxx')
        if $self->cgi->old_password;
    $self->hub->rest->query->param(-name => 'new_password', -value => 'xxx')
        if $self->cgi->new_password;
    $self->hub->rest->query->param(-name => 'new_password_retype', -value => 'xxx')
        if $self->cgi->new_password_retype;
}

sub _update_current_user {
    my $self = shift;
    my $user = $self->hub->current_user;

    my %update;
    if (   $self->cgi->old_password
        or $self->cgi->new_password
        or $self->cgi->new_password_retype ) {
        $self->add_error(loc('error.incorrect-old-password'))
            unless $user->password_is_correct( $self->cgi->old_password );
        $self->add_error(loc('error.new-password-mismatch'))
            unless $self->cgi->new_password eq
            $self->cgi->new_password_retype;

        if ($self->input_errors_found) {
            $self->_obfuscate_passwords;
            return;
        }

        $update{password} = $self->cgi->new_password;
    }

    $self->_obfuscate_passwords;

    $update{first_name}  = $self->cgi->first_name;
    $update{middle_name} = $self->cgi->middle_name;
    $update{last_name}   = $self->cgi->last_name;

    eval { $user->update_store(%update) };

    if ( my $e
        = Exception::Class->caught('Socialtext::Exception::DataValidation') )
    {
        $self->add_error($_) for $e->messages;
    }
    elsif ($@) {
        die $@;
    }

    return if $self->input_errors_found;

    $self->message(loc('config.saved'));
}

sub get_admins {
    my $self = shift;
    my $workspace = $self->hub->current_workspace;
    my @admins;
    my $users_with_roles = $workspace->user_roles(direct => 1);

    while ( my $tuple = $users_with_roles->next ) {
        my $user = $tuple->[0];
        my $role = $tuple->[1];
        if ( $role->name eq 'admin' ) {
            push( @admins, $user->email_address );
        }
    }
    return (@admins);
}

sub users_listall {
    my $self = shift;

    $self->reject_guest(type => 'settings_requires_account');

    $self->_update_users_in_workspace()
        if $self->cgi->Button;

    my $ws = $self->hub->current_workspace;
    my @uwr = sort { lcmp($a->[0]->best_full_name, $b->[0]->best_full_name) }
        $ws->user_roles(direct => 1)->all;

    my @gwr = $ws->group_roles->all;
    my $is_auw = $ws->is_all_users_workspace;
    my $settings_section = $self->template_process(
        'element/settings/users_listall_section',
        users_with_roles => \@uwr,
        groups_with_roles => \@gwr,
        is_auw => $is_auw,
        is_business_admin => $self->hub->current_user->is_business_admin,
        workspace => $ws,
        $self->status_messages_for_template,
    );

    my $display_title =
        $self->hub->checker->check_permission('admin_workspace')
        ? loc('config.user-admin')
        : loc('config.user-list');

    return $self->_render_settings(
        $display_title,
        $settings_section,
    );
}

sub _update_users_in_workspace {
    my $self = shift;
    $self->hub->assert_current_user_is_admin;


    my $ws = $self->hub->current_workspace;
    my %removed;
    for my $user_id ( $self->cgi->remove_user ) {
        my $user = Socialtext::User->new( user_id => $user_id );

        $ws->remove_user( user => $user );

        $removed{$user_id} = 1;
    }

    for my $user_id ( grep { !$removed{$_} } $self->cgi->reset_password ) {
        my $user = Socialtext::User->new( user_id => $user_id );
        my $confirmation = $user->create_password_change_confirmation;
        $confirmation->send;
    }

    my %should_be_admin = map { $_ => 1 } $self->cgi->should_be_admin;
    if ( keys %should_be_admin ) {

        my $users_with_roles
            = $self->hub->current_workspace->user_roles(direct => 1);

        while ( my $tuple = $users_with_roles->next ) {

            my $user = $tuple->[0];
            my $role = $tuple->[1];
            my $make_admin = $should_be_admin{$user->user_id};

            # REVIEW - this is a hack to prevent us from removing the
            # impersonator role from users in this loop. The real
            # solution is to replace the is/is not admin check with
            # something like a pull down or radio group which allows
            # for assigning of different roles.
            next if $role->name ne 'admin'
                and $role->name ne 'member';

            next if $make_admin
                and $ws->permissions->user_can(
                    user       => $user,
                    permission => ST_ADMIN_WORKSPACE_PERM,
                );

            next if not $make_admin
                and not $ws->permissions->user_can(
                    user       => $user,
                    permission => ST_ADMIN_WORKSPACE_PERM,
                );

            $ws->assign_role_to_user(
                user => $user,
                role => ($make_admin ? Socialtext::Role->Admin()
                                     : Socialtext::Role->Member()),
            );
        }
    }
    else {
        $self->add_warning(loc("error.removing-last-admin"));
    }

    $self->message(loc('config.saved'));

    return;
}

# XXX this method doesn't seem to have test coverage
sub users_invitation {
    my $self = shift;
    if ( !$self->hub->checker->check_permission('request_invite') ) {
        $self->hub->assert_current_user_is_admin;
    }

    my $ws                            = $self->hub->current_workspace;
    my $restrict_invitation_to_search = $ws->restrict_invitation_to_search;
    my $invitation_filter             = $ws->invitation_filter;
    my $template_dir                  = $ws->invitation_template;
    my $restrict_domain               = $ws->account->restrict_to_domain;
    my $template;
    my $action;

    if ($restrict_invitation_to_search) {
        $template = 'element/settings/users_invite_search_section';
        $action   = 'users_search';
    }
    elsif ( my $screen = Socialtext::AppConfig->custom_invite_screen() ) {
        $template = 'element/settings/users_invite_' . $screen;
        $action   = $screen;
    }
    else {
        $template = 'element/settings/users_invite_section';
        $action   = 'users_invite';
    }

    $self->hub->action(
        $restrict_invitation_to_search ? 'users_search' : $action );


    my $user = $self->hub->current_user;
    my @invite_groups = 
        grep { 
                $_->user_has_role(
                    user => $user, 
                    role => Socialtext::Role->Admin) 
            } $ws->groups->all;

    my $settings_section = $self->template_process(
        $template,
        invitation_filter         => $invitation_filter,
        workspace_invitation_body =>
            "email/$template_dir/workspace-invitation-body.html",
        restrict_domain => $restrict_domain,
        groups => \@invite_groups,
        is_admin => $self->hub->checker->check_permission('admin_workspace'),
        $self->status_messages_for_template,
    );

    return $self->_render_settings(
        loc('config.user-invite'),
        $settings_section,
    );
}


sub users_invite {
    my $self = shift;
    if ( !$self->hub->checker->check_permission('request_invite') ) {
        $self->hub->assert_current_user_is_admin;
    }

    my ($emails, $invalid) = Socialtext::Helpers->validate_email_addresses(
        $self->cgi->users_new_ids
    );
    my @grouparams= $self->cgi->invite_to_group; 

    my $invite_groups = $self->cgi->group_invite ? \@grouparams : undef; 

    my $html = $self->_invite_users($emails, $invalid, $invite_groups);
    return $html if $html;
}

sub users_search {
    my $self = shift;
    my $filter = $self->hub->current_workspace->invitation_filter();
    my $template_dir = $self->hub->current_workspace->invitation_template();
    if ( !$self->hub->checker->check_permission('request_invite') ) {
        $self->hub->assert_current_user_is_admin;
    }

    my @users;

    if ( $self->cgi->Button ) {
        if ( $self->cgi->Button eq 'Invite' && $self->cgi->email_addresses ) {
            my @emails = map {+{email_address=>$_}} $self->cgi->email_addresses;
            my @invalid;
            my @grouparams= $self->cgi->invite_to_group; 

            my $invite_groups = $self->cgi->group_invite ? \@grouparams : undef; 
            my $html = $self->_invite_users(\@emails, \@invalid, $invite_groups);
            return $html if $html;
        }
    }

    if ( $self->cgi->user_search ) {
        @users = Socialtext::User->Search( $self->cgi->user_search );
    }

    if (@users && $filter) {
        @users = grep { $_ if ($_->{email_address} =~ qr/$filter/) } 
                    @users;
    }

    # Grep out de-activated users.  This makes our search much slower b/c we
    # need to instantiate each user to check if they're deactivated.
    @users = grep { 
        my $user = Socialtext::User->new(email_address => $_->{email_address});
        $user && !$user->is_deactivated
    } @users;

    my $user = $self->hub->current_user;
    my $ws = $self->hub->current_workspace;
    my @invite_groups = 
        grep { 
                $_->user_has_role(
                    user => $user, 
                    role => Socialtext::Role->Admin) 
            } $ws->groups->all;
    
    my $settings_section = $self->template_process(
        'element/settings/users_invite_search_section',
        invitation_filter => $filter,
        $self->status_messages_for_template,
        workspace_invitation_body     => "email/$template_dir/workspace-invitation-body.html",
        users => \@users,
        groups => \@invite_groups,
        is_admin => $self->hub->checker->check_permission('admin_workspace'),
        search_performed => 1,
    );

    return $self->_render_settings(
        loc('config.user-invite'),
        $settings_section,
    );
}

sub _invite_users {
    my $self = shift;
    my ($emails, $invalid, $invite_groups) = @_;
    my $ws = $self->hub->current_workspace;
    my $ws_filter = $ws->invitation_filter();

    my %invitees;
    my @present;
    my @wrong_domain;
    my @actual_groups; 
    
    if ($invite_groups) {
        @actual_groups = 
            map { Socialtext::Group->GetGroup(group_id => $_ ) } 
            @$invite_groups;
    };
    for my $e (@{ $emails }) {
        my $email = $e->{email_address};
        next if $invitees{$email};

        if ($ws_filter) {
            unless ( $email =~ qr/$ws_filter/ ) {
                push @$invalid, $email;
                next;
            }
        }
        unless ($ws->account->email_passes_domain_filter($email)) {
            push @wrong_domain, $email;
            next;
        }

        # Check for _direct_ membership here.
        my $invitee = Socialtext::User->new( email_address => $email );
        if ($invitee && $ws->has_user($invitee, direct => 1)) {
            push @present, $email;
            # do not invite this email address unless they are being invited
            # to groups
            next unless $invite_groups;
        }

        $invitees{$email} = {
            username      => $email,
            email_address => $email,
            first_name => $e->{first_name},
            last_name => $e->{last_name},
        };
    }

    my $extra_invite_text = $self->cgi->append_invitation ?
                            $self->cgi->invitation_text :
                            '';

    my $has_role_in_group = {};
    my $no_role_in_group = {};
    my @invited = ();
    if ($self->hub->checker->check_permission('admin_workspace')) {
        for my $user_data ( values %invitees ) {
            if ($invite_groups) {
                my ($good, $bad) = $self->_filter_groups_for_user(
                    $user_data, \@actual_groups);

                if (scalar(@$bad)) {
                    $has_role_in_group->{$user_data->{email_address}} = $bad;
                }

                next unless scalar(@$good);
                $no_role_in_group->{$user_data->{email_address}} = $good;
                $self->group_invite_one_user(
                    $user_data, $extra_invite_text, $good);
            } else {
                push(@invited, $user_data->{email_address});
                $self->invite_one_user( $user_data, $extra_invite_text );
            }
        }
    }
    else {
        $self->invite_request_to_admin( \%invitees, $extra_invite_text );
    }

    my $settings_section = $self->template_process(
        'element/settings/users_invited_section',
        users_invited         => [ sort @invited ],
        users_already_present => [ sort @present ],
        invalid_addresses     => [ sort @$invalid ],
        has_role_in_group     => $has_role_in_group,
        no_role_in_group      => $no_role_in_group,
        domain                => $ws->account->restrict_to_domain,
        wrong_domain          => [ sort @wrong_domain ],
        groups                => $invite_groups ? \@actual_groups : [],
        checker               => $self->hub->checker,
        $self->status_messages_for_template,
    );

    return $self->_render_settings(
        loc('config.user-invite'),
        $settings_section,
    );
}

sub _render_settings {
    my $self = shift;
    my $title = shift;
    my $settings = shift;

    my $cur_ws = $self->hub->current_workspace;
    my $scope = $cur_ws && $cur_ws->real ? 'workspace' : 'global';
    
    $self->screen_template('view/settings');
    return $self->render_screen(
        settings_table_id => 'settings-table',
        settings_section  => $settings,
        hub               => $self->hub,
        display_title     => $title,
        pref_list         => $self->_get_pref_list($scope),
    );
}

sub _filter_groups_for_user {
    my $self = shift;
    my $user_data = shift;
    my $groups = shift;

    my $user = Socialtext::User->new(
        email_address => $user_data->{email_address});
    return ($groups, []) unless $user;

    my @good = ();
    my @bad = ();
    for my $group (@$groups) {
        if ($group->has_user($user, {direct=>1}) ) {
            push(@bad, $group);
        }
        else {
            push(@good, $group);
        }
    }

    return (\@good, \@bad);
}

sub invite_request_to_admin {
    my $self = shift;
    my $user_hash   = shift;
    my $extra_text  = shift;
    my $user_string = '';
    my $admin_email = join( ',', $self->get_admins );
    my @invited_users;
    foreach my $user ( values %$user_hash ) {
        push( @invited_users, $user->{email_address} );
    }

    my $renderer = Socialtext::TT2::Renderer->instance();
    my $subject  = loc('invite.request=wiki',$self->hub->current_workspace->title);

    my $template_dir = $self->hub->current_workspace->invitation_template;
    my $url = $self->hub->current_workspace->uri . "?action=users_invite";

    my %vars = (
        inviting_user   => $self->hub->current_user->email_address,
        workspace_title => $self->hub->current_workspace->title,
        invited_users   => [@invited_users],
        url             => $url,
        extra_text      => $extra_text,
        appconfig       => Socialtext::AppConfig->instance,
    );

    my $text_body = $renderer->render(
        template => "email/$template_dir/invite-request-email.txt",
        vars     => \%vars,
    );

    my $html_body = $renderer->render(
        template => "email/$template_dir/invite-request-email.html",
        vars     => \%vars,
    );

    my $locale = system_locale();
    my $email_sender = Socialtext::EmailSender::Factory->create($locale);
    $email_sender->send(
        from      => $self->hub->current_user->name_and_email,
        to        => $admin_email,
        subject   => $subject,
        text_body => $text_body,
        html_body => $html_body,
    );

}

sub group_invite_one_user {
    my $self = shift;
    my $user_data  = shift;
    my $extra_text = shift;
    my $invite_groups= shift;

    for my $group (@$invite_groups) {
        my $invitation = Socialtext::GroupInvitation->new(
            group              => $group,
            from_user          => $self->hub->current_user,
            invitee            => $user_data->{email_address},
            extra_text         => $extra_text
        ); 
        $invitation->queue( $user_data->{email_address},
                    first_name => $user_data->{first_name},
                    last_name => $user_data->{last_name});
    }
}

sub invite_one_user {
    my $self = shift;
    my $user_data  = shift;
    my $extra_text = shift;

    my $invitation =
    Socialtext::WorkspaceInvitation->new(
        workspace          => $self->hub->current_workspace,
        from_user          => $self->hub->current_user,
        invitee            => $user_data->{email_address},
        invitee_first_name => $user_data->{first_name},
        invitee_last_name  => $user_data->{last_name},
        extra_text         => $extra_text,
        viewer             => $self->hub->viewer
    );
    $invitation->send();
}

package Socialtext::UserSettings::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'Button';
cgi new_password        => '-trim';
cgi new_password_retype => '-trim';
cgi old_password        => '-trim';
cgi 'remove_user';
cgi 'reset_password';
cgi 'should_be_admin';
cgi 'user_search';
cgi 'email_addresses';
cgi 'users_new_ids';
cgi 'first_name';
cgi 'middle_name';
cgi 'last_name';
cgi 'append_invitation';
cgi 'invitation_text';
cgi 'dm_sends_email';
cgi 'invite_to_group';
cgi 'group_invite';
1;
