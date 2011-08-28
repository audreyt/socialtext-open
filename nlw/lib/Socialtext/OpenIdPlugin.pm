# @COPYRIGHT@
package Socialtext::OpenIdPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';
use URI::Escape;
use Encode;
use Socialtext::l10n qw(loc system_locale);
use Socialtext::EmailSender::Factory;

use Class::Field qw( const field );


sub class_id { 'openid' }
const cgi_class => 'Socialtext::OpenId::CGI';
field 'users_new_ids';
field users_already_present => [];

sub register {
    my $self = shift;
    $self->hub->registry->add(action => 'openid_invite');
}

sub openid_invite {
    my $self = shift;

    $self->hub->assert_current_user_is_admin;

    if ( $self->cgi->users_openid &&
         $self->cgi->users_email ) {
        my %user_hash = ( $self->cgi->users_email =>
                            $self->cgi->users_openid );

        unless ( keys %user_hash ) {
            $self->add_error (loc("error.openid-users-required"));
            return;
        }

        my $html = $self->_invite_users(\%user_hash);
    } else {
        $self->add_error (loc("error.openid-and-email-required"));
        return;
    }
}


sub _invite_users {
    my $self = shift;
    my $user_hash = shift;
    my %users = %{$user_hash};
    my %users_to_invite = ();

    my @present;

    foreach my $email (keys %users) {
        my $username = $users{$email};
        $username =~ s/\s//g;
        my $user = Socialtext::User->new ( email_address => $email,
                                           username => $username );

        if ( $user &&
             $self->hub->current_workspace->has_user( $user ) )
        {
            push @present, $email;
            next;
        }

        $users_to_invite{$email} = {
            username => $username,
            email_address => $email,
            password => 'a lovely password',
        };
    }

    for my $user_data ( values %users_to_invite ) {
        $self->invite_one_user ( $user_data );
    }

    my $settings_section = $self->template_process(
        'element/settings/users_invited_openid',
        users_invited         => [sort keys %users],
        $self->status_messages_for_template,
    );

    $self->screen_template('view/settings');
    return $self->render_screen(
        settings_table_id   => 'settings-table',
        settings_section    => $settings_section,
        hub                 => $self->hub,
        display_title       => loc('config.user-invite'),
        pref_list           => $self->_get_pref_list,
    );
}

sub invite_one_user {
    my $self = shift;
    my $user_data = shift;

    my $user = Socialtext::User->new(
        email_address => $user_data->{email_address} );
    $user ||= Socialtext::User->create(
        %$user_data,
        created_by_user_id => $self->hub->current_user->user_id,
    );

    $self->hub->current_workspace->add_user(
        user => $user,
        role => Socialtext::Role->Member(),
    );

    $self->invite_notify ($user);
}

sub invite_notify {
    my $self = shift;
    my $user = shift;

    my $template_dir = $self->hub->current_workspace->invitation_template;

    my $subject = loc("openid.invite=wiki" ,$self->hub->current_workspace->name);

    my $renderer = Socialtext::TT2::Renderer->instance();

    my $app_name =
        Socialtext::AppConfig->is_appliance()
        ? 'Socialtext Appliance'
        : 'Socialtext';

    my %vars = (
        username        => $user->username,
        workspace_title => $self->hub->current_workspace->title,
        workspace_uri   => $self->hub->current_workspace->uri,
        inviting_user   => $self->hub->current_user->best_full_name,
        app_name        => $app_name,
        appconfig       => Socialtext::AppConfig->instance(),
    );

    my $text_body = $renderer->render(
        template => "email/$template_dir/workspace-invitation.txt",
        vars     => {
            %vars,
        }
    );

    my $html_body = $renderer->render(
        template => "email/workspace-invitation.html",
        vars     => {
            %vars,
            workspace_invitation_body =>
                "email/$template_dir/workspace-invitation-body.html",
        }
    );

    my $locale = system_locale();
    my $email_sender = Socialtext::EmailSender::Factory->create($locale);
    $email_sender->send(
        from      => $self->hub->current_user->name_and_email,
        to        => $user->email_address,
        subject   => $subject,
        text_body => $text_body,
        html_body => $html_body,
    );
}

package Socialtext::OpenId::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'users_openid';
cgi 'users_email';

1;
