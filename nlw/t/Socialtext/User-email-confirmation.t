#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 15;
use Socialtext::User;

BEGIN {
    # if we don't have Email::Send::Test installed, skip *ALL* of the tests;
    # otherwise we generate _real_ test messages.
    unless ( eval { require Email::Send::Test; 1 } ) {
        plan skip_all => 'These tests require Email::Send::Test to run.';
    }
    $Socialtext::EmailSender::Base::SendClass = 'Test';
}

###############################################################################
# Fixtures: db
#
# Need to have the DB bootstrapped, but don't care whats in it.
fixtures( 'db' );

###############################################################################
# Test: confirmation e-mail qualities
confirmation_email_qualities: {
    my $user = create_test_user();
    isa_ok $user, 'Socialtext::User', 'new test user';

    # set the confirmation info for this user.
    $user->create_email_confirmation();

    # verify the qualities that the confirmation email has.
    my $confirmation = $user->email_confirmation;
    is length $confirmation->token, 27,    '... has base64 encoded email confirmation hash';
    ok $user->requires_email_confirmation, '... user requires email confirmation';
    ok !$confirmation->has_expired,        '... confirmation has not yet expired';

    # confirm the email, and make sure it sticks
    $user->confirm_email_address();
    ok !$user->requires_email_confirmation,
        '... user no longer requires confirmation';
}

###############################################################################
# Test: make sure that the confirmation hash gets re-used if it already exists
#
# Fixes RT #20767
confirmation_hash_reused: {
    my $user = create_test_user();
    isa_ok $user, 'Socialtext::User', 'new test user';

    # set the confirmation info for this user, and get the hash it generated.
    $user->create_email_confirmation;
    my $hash_orig = $user->email_confirmation->token();

    # sleep a bit; the hash is time() based, and we want to make sure that
    # changes
    diag "sleeping a few secs" if ($ENV{TEST_VERBOSE});
    sleep 2;

    # set the confirmation info again, and get the generated hash again
    $user->create_email_confirmation;
    my $hash_reused = $user->email_confirmation->token();

    # the confirmation hash *should* have been reused
    is $hash_reused, $hash_orig, 'confirmation hash reused if it already exists';
}

###############################################################################
# Test: verify the contents of the confirmation e-mail.
confirmation_email_contents: {
    my $user = create_test_user();
    isa_ok $user, 'Socialtext::User', 'new test user';

    # set the confirmation info the this user, and get the generated e-mail
    Email::Send::Test->clear();
    my $uce = $user->create_email_confirmation;
    $uce->send;

    my @emails = Email::Send::Test->emails();
    is scalar @emails, 1, 'one confirmation e-mail was sent';

    my $email = shift @emails;

    # verify the e-mail headers
    like $email->header('Subject'), qr/Welcome to the .*? community - please confirm your email to join/, '... e-mail subject correct';
    is $email->header('To'), $user->name_and_email(), '... e-mail is addressed to the test user';

    # verify the contents of the message parts
    my @parts = $email->parts();
    my $part;

    $part = shift @parts;
    is $part->header('Content-Type'), 'text/plain; charset="UTF-8"', '... first message part is text/plain';
    like $part->body(), qr|/submit/confirm_email\?hash=\S{27}|, '... ... text part contains confirmation link';

    $part = shift @parts;
    is $part->header('Content-Type'), 'text/html; charset="UTF-8"', '... second message part is text/html';
    like $part->body(), qr|/submit/confirm_email\?hash=\S{27}|, '... ... html part contains confirmation link';
}
