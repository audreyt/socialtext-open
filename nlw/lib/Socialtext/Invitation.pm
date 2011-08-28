package Socialtext::Invitation;
# @COPYRIGHT@
use Moose;
use Socialtext::AppConfig;
use Socialtext::TT2::Renderer;
use Socialtext::URI;
use Socialtext::JobCreator;
use Socialtext::User;
use Socialtext::l10n qw(system_locale);
use Socialtext::EmailSender::Factory;
use namespace::clean -except => 'meta';

has 'from_user'  => (is => 'ro', isa => 'Socialtext::User', required => 1);
has 'viewer'     => (is => 'ro', isa => 'Socialtext::Formatter::Viewer');
has 'extra_text' => (is => 'ro', isa => 'Maybe[Str]');
has 'template'   => (is => 'ro', isa => 'Str', default => 'st');

sub queue {
    my $self    = shift;
    my $invitee = shift;
    my %addtl   = @_;

    my $role   = delete $addtl{role} || Socialtext::Role->Member();
    my $object = $self->object;
    my $user   = Socialtext::User->new(email_address => $invitee);
    if ($user and $user->is_deactivated) {
        $user->reactivate(account_id => $object->account_id);
    }

    $user ||= Socialtext::User->create(
        username           => $invitee,
        email_address      => $invitee,
        created_by_user_id => $self->from_user->user_id,
        primary_account_id => $object->account_id,
        %addtl,
    );

    $user->create_email_confirmation()
        unless $user->has_valid_password();

    $object->assign_role_to_user(
        actor => $self->from_user,
        user  => $user,
        role  => $role,
    );

    Socialtext::JobCreator->insert(
        'Socialtext::Job::Invite',
        {
            job => { priority => 80 },
            user_id         => $user->user_id,
            sender_id       => $self->from_user->user_id,
            extra_text      => $self->extra_text,
            template        => $self->template,
            $self->id_hash(),
        }
    );
}

sub invite_notify {
    my $self     = shift;
    my $user     = shift;
    my $template = $self->template;

    my $app_name = Socialtext::AppConfig->is_appliance()
        ? 'Socialtext Appliance'
        : 'Socialtext';

    my %vars = (
        user                  => $user,
        from_user             => $self->from_user,
        username              => $user->username,
        requires_confirmation => $user->requires_email_confirmation,
        confirmation_uri      => $user->confirmation_uri || '',
        host                  => Socialtext::AppConfig->web_hostname(),
        inviting_user         => $self->from_user->best_full_name,
        app_name              => $app_name,
        forgot_password_uri   =>
            Socialtext::URI::uri(path => '/nlw/forgot_password.html'),
        appconfig => Socialtext::AppConfig->instance(),
        $self->_template_args,
    );

    my $extra_text = $self->extra_text;
    my $type = $self->_template_type;
    my $renderer = Socialtext::TT2::Renderer->instance();
    my $text_body = $renderer->render(
        template => "email/$template/$type-invitation.txt",
        vars     => {
            %vars,
            extra_text => $extra_text,
        }
    );

    my $html_body = $renderer->render(
        template => "email/$type-invitation.html",
        vars     => {
            %vars,
            invitation_body =>
                "email/$template/$type-invitation-body.html",
            extra_text => $self->{viewer}
                ? $self->{viewer}->process($extra_text || '')
                : $extra_text,
        }
    );

    # a requirement for [Story: User breezes through Free registration],
    # messages from 'System User' should come from 'Socialtext'. Calling
    # this user 'Socialtext' elsewhere in the system doesn't make sense,
    # so override the username here.
    my $sys_user = Socialtext::User->SystemUser();
    my $from = ($self->from_user->user_id == $sys_user->user_id)
        ? 'Socialtext <' . $sys_user->email_address . '>'
        : $self->from_user->name_and_email,

    my $locale = system_locale();
    my $email_sender = Socialtext::EmailSender::Factory->create($locale);
    my $subject = $self->_subject;
    $email_sender->send(
        from      => $from,
        to        => $user->email_address,
        subject   => $subject,
        text_body => $text_body,
        html_body => $html_body,
    );

    $self->_log_action("INVITE_USER_ACCOUNT", $user->email_address);
}

sub _log_action {
    my $self      = shift;
    my $action    = shift;
    my $extra     = shift;
    my $name      = $self->_name;
    my $page_name = '';
    my $user_name = $self->from_user->user_id;
    my $log_msg   = "$action : $name : $page_name : $user_name";
    if ($extra) {
        $log_msg .= " : $extra";
    }
    Socialtext::Log->new()->info("$log_msg");
}

__PACKAGE__->meta->make_immutable;
1;

=head1 NAME

Socialtext::Invitation - Base class for sending Invitation emails

=head1 DESCRIPTION

C<Socialtext::Invitation> is a base class that can be extended to send
invitation emails to Users when they are added to different collections of
users, such as Workspaces, Accounts, or Groups.

=head1 SYNOPSIS

    package Socialtext::MyInvitation;
    use Moose;

    extends 'Socialtext::Invitation';

    ... # Your additional code

=head1 AUTHOR

Socialtext, Inc.,  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc.,  All Rights Reserved.

=cut
