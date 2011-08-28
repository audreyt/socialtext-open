package Socialtext::User::Restrictions::email_confirmation;

use Moose;
with 'Socialtext::User::Restrictions::base';

use Socialtext::AppConfig;
use Socialtext::EmailSender::Factory;
use Socialtext::l10n qw(system_locale loc);
use Socialtext::TT2::Renderer;
use Socialtext::URI;

sub _restriction_type { 'email_confirmation' };

sub send {
    my $self = shift;
    $self->_send_email;
}

sub confirm {
    my $self = shift;
    $self->_send_completed_email;
    $self->_send_completed_signal unless $self->workspace_id;
};

# XXX - Yuck; this same URI is also used by "password_change"
sub uri {
    my $self = shift;
    return Socialtext::URI::uri(
        path  => '/nlw/submit/confirm_email',
        query => { hash => $self->token },
    );
}

sub _send_email {
    my $self     = shift;
    my $user     = $self->user;
    my $uri      = $self->uri;
    my $renderer = Socialtext::TT2::Renderer->instance();
    my $workspace = $self->workspace;
    my %vars = (
        confirmation_uri => $uri,
        appconfig        => Socialtext::AppConfig->instance(),
        account_name     => $user->primary_account->name,
        target_workspace => $workspace
    );

    my $text_body = $renderer->render(
        template => 'email/email-address-confirmation.txt',
        vars     => \%vars,
    );

    my $html_body = $renderer->render(
        template => 'email/email-address-confirmation.html',
        vars     => \%vars,
    );

    my $locale       = system_locale();
    my $email_sender = Socialtext::EmailSender::Factory->create($locale);
    $email_sender->send(
        to        => $user->name_and_email(),
        subject   => $workspace ?
            loc('wiki.welcome-confirm=name', $workspace->title)
            :
            loc('account.welcome-confirm=name', $user->primary_account->name),
        text_body => $text_body,
        html_body => $html_body,
    );
}

sub _send_completed_email {
    my $self     = shift;
    my $user     = $self->user;
    my $ws       = $self->workspace;
    my $renderer = Socialtext::TT2::Renderer->instance();
    my $app_name =
        Socialtext::AppConfig->is_appliance()
        ? loc('email.socialtext-appliance')
        : loc('email.socialtext');
    my @workspaces;
    my @groups;
    my $subject;

    if ($ws) {
        $subject = loc('email.confirmation-subject=wiki', $ws->title());
    }
    else {
        $subject = loc("email.confirmation-subject=app", $app_name);
        @groups     = $user->groups->all;
        @workspaces = $user->workspaces->all;
    }

    my %vars = (
        title => ($ws) ? $ws->title() : $app_name,
        uri   => ($ws) ? $ws->uri() : Socialtext::URI::uri(path => '/challenge'),
        workspaces       => \@workspaces,
        groups           => \@groups,
        target_workspace => $ws,
        user             => $user,
        app_name         => $app_name,
        appconfig        => Socialtext::AppConfig->instance(),
        support_address  => Socialtext::AppConfig->instance()->support_address,
    );

    my $text_body = $renderer->render(
        template => 'email/email-address-confirmation-completed.txt',
        vars     => \%vars,
    );

    my $html_body = $renderer->render(
        template => 'email/email-address-confirmation-completed.html',
        vars     => \%vars,
    );

    my $locale       = system_locale();
    my $email_sender = Socialtext::EmailSender::Factory->create($locale);
    $email_sender->send(
        to        => $user->name_and_email(),
        subject   => $subject,
        text_body => $text_body,
        html_body => $html_body,
    );
}

sub _send_completed_signal {
    my $self = shift;

    require Socialtext::Pluggable::Adapter;
    my $signals = Socialtext::Pluggable::Adapter->plugin_class('signals');
    return unless $signals;

    my $user = $self->user;
    return unless $user->can_use_plugin('signals');

    my $wafl = '{user: ' . $user->user_id . '}';
    my $body =
        loc('info.just-joined=user,group!', $wafl, $user->primary_account->name);
    eval {
        $signals->Send( {
            user        => $user,
            account_ids => [ $user->primary_account_id ],
            body        => $body,
        } );
    };
    warn $@ if $@;
}

__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

Socialtext::User::Restrictions::email_confirmation - Email Confirmation restriction

=head1 SYNOPSIS

  use Socialtext::User::Restrictions::email_confirmation;

  # require that a User confirm their e-mail address
  my $restriction = Socialtext::User::Restrictions::email_confirmation->CreateOrReplace( {
      user_id      => $user->user_id,
      workspace_id => $workspace->workspace_id,
  } );

  # send the User the e-mail asking them to confirm their e-mail address
  $restriction->send;

  # let the User know that they've completed the confirmation
  $restriction->confirm;

  # clear the Restriction (after the User completed their confirmation)
  $restriction->clear;

=head1 DESCRIPTION

This module implements a Restriction requiring the User to confirm their
e-mail address.

=head1 METHODS

=over

=item $self->send()

Sends out a notification e-mail to the User to let them know that they need to
confirm their e-mail address.

=item $self->uri()

Returns the URI that the User should be directed to in order to confirm their
e-mail address.

=item $self->confirm()

Sends out all of the notifications necessary, once the User has confirmed
their e-mail address.

=back

=head1 COPYRIGHT

Copyright 2011 Socialtext, Inc., All Rights Reserved.

=cut
