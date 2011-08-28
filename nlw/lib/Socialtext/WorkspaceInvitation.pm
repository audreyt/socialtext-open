# @COPYRIGHT@
package Socialtext::WorkspaceInvitation;

use strict;
use warnings;

our $VERSION = '0.01';

use Socialtext::AppConfig;
use Socialtext::TT2::Renderer;
use Socialtext::URI;
use Socialtext::User;
use Socialtext::l10n qw(system_locale loc);
use Socialtext::EmailSender::Factory;

=pod

=over 4

=item * workspace => $workspace

=item * from_user => $from_user

=item * invitee   => $invitee_address

=item * extra_text => $extra_text

=item * viewer    => $viewer

=back

=cut

sub new {
    my $class = shift;
    my $self = { @_ };
    bless $self, $class;
    return $self;
}

sub send {
    my $self = shift;

    # TODO filter the case where the user already is a member of this workspace
    # SEE UserSettingsPlugin->_invite_users and the @present variable
    $self->_invite_one_user( );
}

sub _invite_one_user {
    my $self = shift;
    my $wksp = $self->{workspace};

    my $user = Socialtext::User->new(
        email_address => $self->{invitee}
    );
    if ($user and $user->is_deactivated) {
        $user->reactivate(account_id => $wksp->account_id);
    }

    $user ||= Socialtext::User->create(
        username => $self->{invitee},
        email_address => $self->{invitee},
        first_name => $self->{invitee_first_name},
        last_name => $self->{invitee_last_name},
        created_by_user_id => $self->{from_user}->user_id,
        primary_account_id => $wksp->account_id,
    );

    $user->create_email_confirmation()
        unless $user->has_valid_password();

    if (!$wksp->has_user($user, direct => 1)) {
        $wksp->add_user(
            user => $user,
            role => Socialtext::Role->Member(),
        );
    }

    $self->_log_action( "INVITE_USER", $user->email_address );
    $self->invite_notify( $user );
}

# TODO: refactor this with and fold it into invite_notify
sub invite_admin_notify {
    my $self         = shift;
    my $user         = shift;
    my $workspace    = $self->{workspace};
    my $from_user    = $self->{from_user};
    my $template_dir = $workspace->invitation_template;

    my $subject = loc( 
        "invite.wiki=title", 
        $workspace->title
    );

    my $renderer = Socialtext::TT2::Renderer->instance();

    my %vars = (
        workspace_title => $workspace->title,
        workspace_uri   => $workspace->uri,
    );

    my $text_body = $renderer->render(
        template => "email/$template_dir/workspace-admin-invitation.txt",
        vars     => \%vars,
    );

    my $locale = system_locale();
    my $email_sender = Socialtext::EmailSender::Factory->create($locale);
    $email_sender->send(
        from      => $self->{from_user}->name_and_email,
        to        => $user->email_address,
        subject   => $subject,
        text_body => $text_body,
    );
}

sub invite_notify {
    my $self       = shift;
    my $user       = shift;
    my $extra_text = $self->{extra_text};
    my $workspace  = $self->{workspace};

    my $template_dir = $workspace->invitation_template;

    my $subject = loc("invite.wiki=title", $workspace->title);

    my $renderer = Socialtext::TT2::Renderer->instance();

    my $forgot_pw_uri
        = Socialtext::URI::uri( path => '/nlw/forgot_password.html' );

    my $app_name = Socialtext::AppConfig->is_appliance()
        ? 'Socialtext Appliance'
        : 'Socialtext';

    my %vars = (
        username              => $user->username,
        requires_confirmation => $user->requires_email_confirmation,
        confirmation_uri      => $user->confirmation_uri || '',
        workspace_title       => $workspace->title,
        workspace_uri         => $workspace->uri,
        inviting_user         => $self->{from_user}->best_full_name,
        app_name              => $app_name,
        forgot_password_uri   => $forgot_pw_uri,
        appconfig             => Socialtext::AppConfig->instance(),
    );

    my $text_body = $renderer->render(
        template => "email/$template_dir/workspace-invitation.txt",
        vars     => {
            %vars,
            extra_text => $extra_text,
        }
    );

    my $html_body = $renderer->render(
        template => "email/workspace-invitation.html",
        vars     => {
            %vars,
            workspace_invitation_body => "email/$template_dir/workspace-invitation-body.html",
            extra_text =>
                     $self->{viewer} ? $self->{viewer}->process( $extra_text || '' ) :
                                       $extra_text,
        }
    );

    my $locale = system_locale();
    my $email_sender = Socialtext::EmailSender::Factory->create($locale);
    $email_sender->send(
        from      => $self->{from_user}->name_and_email,
        to        => $user->email_address,
        subject   => $subject,
        text_body => $text_body,
        html_body => $html_body,
    );
}

sub _log_action {
    my $self = shift;
    my $action = shift;
    my $extra  = shift;
    my $workspace = $self->{workspace}->name;
    my $page_name = '';
    my $user_name = $self->{from_user}->user_id;
    my $log_msg = "$action : $workspace : $page_name : $user_name";
    if ($extra) {
        $log_msg .= " : $extra";
    }
    Socialtext::Log->new()->info("$log_msg");
}

1;
