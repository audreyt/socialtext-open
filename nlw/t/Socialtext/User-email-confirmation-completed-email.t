#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 24;
use Socialtext::Account;
use Socialtext::User;
use Socialtext::Workspace;
use Socialtext::Role;

BEGIN {
    unless ( eval { require Email::Send::Test; 1 } ) {
        plan skip_all => 'These tests require Email::Send::Test to run.';
    }
    $Socialtext::EmailSender::Base::SendClass = 'Test';
}

fixtures(qw( clean db ));

my $AdminRole = Socialtext::Role->Admin();

my $user = Socialtext::User->create(
    username      => 'devnull9@socialtext.net',
    email_address => 'devnull9@socialtext.net',
    password      => 'password'
);

{
    $user->create_email_confirmation();

    my @emails = Email::Send::Test->emails();
    is( scalar @emails, 0, 'no email was sent while user still requires confirmation' );

    $user->confirm_email_address();
    @emails = Email::Send::Test->emails();
    is( scalar @emails, 1, 'one email was sent when user was confirmed' );
    is( $emails[0]->header('Subject'),
        'You can now login to the Socialtext application',
        'check email subject - user is in no workspaces' );
    is( $emails[0]->header('To'), $user->name_and_email(),
        'email is addressed to user' );

    my @parts = $emails[0]->parts;
    like( $parts[0]->body, qr[/challenge],
          'text email body has login link' );
}

{
    Email::Send::Test->clear();

    my $ws = Socialtext::Workspace->create(
        name               => 'test',
        title              => 'Test WS',
        skip_default_pages => 1,
        account_id         => Socialtext::Account->Socialtext()->account_id(),
    );
    $ws->add_user( user => $user );

    $user->create_email_confirmation();
    $user->confirm_email_address();

    my @emails = Email::Send::Test->emails();
    is( scalar @emails, 1, 'one email was sent when user was confirmed' );
    is( $emails[0]->header('Subject'),
        'You can now login to the Socialtext application',
        'check email subject - user is in a workspace' );

    my @parts = $emails[0]->parts;
    like( $parts[0]->body, qr[/test/],
          'text email body has link to workspace' );
}
{
    Email::Send::Test->clear();

    my $ws = Socialtext::Workspace->create(
        name               => 'test1',
        title              => 'Test WS',
        skip_default_pages => 1,
        account_id         => Socialtext::Account->Socialtext()->account_id(),
    );
    $ws->add_user( user => $user );

    $ws = Socialtext::Workspace->create(
        name               => 'test2',
        title              => 'Test WS',
        skip_default_pages => 1,
        account_id         => Socialtext::Account->Socialtext()->account_id(),
    );
    $ws->add_user( user => $user );

    $ws = Socialtext::Workspace->create(
        name               => 'test3',
        title              => 'Test WS',
        skip_default_pages => 1,
        account_id         => Socialtext::Account->Socialtext()->account_id(),
    );
    $ws->add_user( user => $user );

    $user->create_email_confirmation();
    $user->confirm_email_address();

    my @emails = Email::Send::Test->emails();
    is( scalar @emails, 1, 'one email was sent when user was confirmed' );
    is( $emails[0]->header('Subject'),
        'You can now login to the Socialtext application',
        'check email subject - user is in multiple workspace' );

    my @parts = $emails[0]->parts;
    like( $parts[0]->body, qr[/test1/],
          'text email body has link to first workspace' );
    like( $parts[1]->body, qr[/test1/],
          'html email body has link to first workspace' );
    like( $parts[0]->body, qr[/test2/],
          'text email body has link to second workspace' );
    like( $parts[1]->body, qr[/test2/],
          'html email body has link to second workspace' );
    like( $parts[0]->body, qr[/test3/],
          'text email body has link to third workspace' );
    like( $parts[1]->body, qr[/test3/],
          'html email body has link to third workspace' );
}

sub _invite_user_to_group {
    my $name = shift;
    my $inviter = shift;
    my $invitee = shift;

    my $group   = create_test_group(unique_id => $name);
    $group->add_user(
        user => $inviter,
        role => $AdminRole,
    );

    my $invitation = $group->invite(
        from_user => $inviter,
    );
    $invitation->queue(
        $invitee->email_address,
        first_name => $invitee->first_name,
        last_name  => $invitee->last_name,
    );

    return $group;
}

{
    Email::Send::Test->clear();

    my $inviter = create_test_user();
    my $g1 = _invite_user_to_group('group 1', $inviter, $user);
    my $g2 = _invite_user_to_group('group 2', $inviter, $user);
    my $g3 = _invite_user_to_group('group 3', $inviter, $user);

    $user->create_email_confirmation();
    $user->confirm_email_address();

    my @emails = Email::Send::Test->emails();
    is( scalar @emails, 1, 'one email was sent when user was confirmed' );
    is( $emails[0]->header('Subject'),
        'You can now login to the Socialtext application',
        'check email subject - user is in a group' );

    my @parts = $emails[0]->parts;
    my $uri = '/st/group/' . $g1->group_id;
    like( $parts[0]->body, qr[$uri], 'text email body has link to group 1' );
    like( $parts[1]->body, qr[$uri], 'html email body has link to group 1' );
    $uri = '/st/group/' . $g2->group_id;
    like( $parts[0]->body, qr[$uri], 'text email body has link to group 2' );
    like( $parts[1]->body, qr[$uri], 'html email body has link to group 2' );
    $uri = '/st/group/' . $g3->group_id;
    like( $parts[0]->body, qr[$uri], 'text email body has link to group 3' );
    like( $parts[1]->body, qr[$uri], 'html email body has link to group 3' );
}
