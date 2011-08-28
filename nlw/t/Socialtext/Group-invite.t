#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 3;
use Socialtext::Group;
use Socialtext::Role;
use Socialtext::Events;

fixtures(qw( db ));

my $AdminRole = Socialtext::Role->Admin();

###############################################################################
# TEST: Invitation gets recorded against the *correct* inviter.
#       Bug #3749
invite_user_event_gets_recorded_properly: {
    my $group   = create_test_group();
    my $inviter = create_test_user();
    my $invitee = create_test_user();

    # Give the inviter sufficient privs to invite another User.
    $group->add_user(
        user => $inviter,
        role => $AdminRole,
    );

    # Invite the User into the Group
    my $invitation = $group->invite(
        from_user => $inviter,
    );
    $invitation->queue(
        $invitee->email_address,
        first_name => $invitee->first_name,
        last_name  => $invitee->last_name,
    );

    # Confirm that the User now has a Role in the Group
    ok $group->has_user($invitee), 'User invited to Group';

    # And confirm that the Event shows the *right* person as having invited
    # the User.
    my $events = Socialtext::Events->GetGroupActivities($inviter, $group);
    my ($add_invitee_event) =
        grep { $_->{person}{id} == $invitee->user_id }
        grep { $_->{action} eq 'add_user' }
        @{$events};

    ok $add_invitee_event, '... found Event recording User being invited';
    is $add_invitee_event->{actor}{best_full_name}, $inviter->guess_real_name,
        '... and was recorded by the correct Inviter';
}
