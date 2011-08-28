#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext;
BEGIN {
    unless ( eval { require Email::Send::Test; 1 } ) {
        plan skip_all => 'These tests require Email::Send::Test to run.';
    }
    else {
        plan tests => 27;
    }
}

use Socialtext::User;
use Socialtext::Workspace;

BEGIN {
    use_ok( 'Socialtext::WorkspaceInvitation' );
}

fixtures(qw( empty ));

$Socialtext::EmailSender::Base::SendClass = 'Test';

my $workspace = Socialtext::Workspace->new( name => 'empty' );
my $current_user    = Socialtext::User->new( username => 'devnull1@socialtext.com' );

Can_send_without_exception: {
    my $invitation = Socialtext::WorkspaceInvitation->new(
        workspace => $workspace,
        from_user => $current_user,
        invitee   => 'devnull7@socialtext.com',
    );

    eval { $invitation->send(); };
    my $e = $@;
    is( $e, '', "send without exception" );
}

my @cases = ( { label        => 'non-appliance',
                is_appliance => 0,
                username     => 'devnull8@socialtext.com',
                tests        => [ qr/From: "devnull1" <devnull1\@socialtext\.com>/,
                                  qr/to join Empty Wiki/,
                                  qr{/submit/confirm_email},
                                ],
              },
              { label        => 'non-appliance has account',
                is_appliance => 0,
                username     => 'devnull8@socialtext.com',
                tests        => [ qr/already have a Socialtext account/,
                                ],
              },
              { label        => 'appliance',
                is_appliance => 1,
                username     => 'devnull9@socialtext.com',
                tests        => [ qr/I'm inviting you/,
                                  qr{/submit/confirm_email},
                                ],
              },
              { label        => 'appliance has account',
                is_appliance => 1,
                username     => 'devnull9@socialtext.com',
                tests        => [ qr/already have a Socialtext Appliance account/,
                                ],
              }
            );


for my $c (@cases) {
    local $SIG{__DIE__};
    local $ENV{NLW_IS_APPLIANCE} = $c->{is_appliance};

    Email::Send::Test->clear;

    my $invitation = Socialtext::WorkspaceInvitation->new(
        workspace => $workspace,
        from_user => $current_user,
        invitee   => $c->{username},
    );

    $invitation->send() ;

    my $expected = 0;
    if( _confirm_user_if_neccessary( $c->{username} ) ) {
        $expected = 2;
    } else {
        $expected = 1;
    }

    my $user = Socialtext::User->Resolve( $c->{username} );
    is $user->primary_account_id, $workspace->account_id,
       'invited user primary_account_id matches workspace';

    my @emails = Email::Send::Test->emails;
    is scalar @emails, $expected, "$expected email(s) were sent: $c->{label}";
    for my $rx ( @{ $c->{tests} } ) {
        like( $emails[0]->as_string, $rx,
              "$c->{label} - email matches $rx" );
    }
};

my $hub = new_hub('empty');
my $viewer = $hub->viewer;
ok( $viewer, "viewer acquired" );
{
    Email::Send::Test->clear;
    my $extra_text = <<'EOF';
Here is a paragraph of text. Lalalala.

* A list
* Item 2

Another paragraph.
EOF

    my $invitation = Socialtext::WorkspaceInvitation->new(
        workspace  => $workspace,
        from_user  => $current_user,
        invitee    => 'devnull9@socialtext.com',
        extra_text => $extra_text,
        viewer     => $viewer,
    );
    $invitation->send();

    my @emails = Email::Send::Test->emails;
    is( scalar @emails, 1, 'one email was sent' );

    my $plain_body = ( $emails[0]->parts() )[0]->body();
    like( $plain_body, qr/Here is a paragraph/,
          'plain body contains extra text' );
    like( $plain_body, qr/\* A list/,
          'plain body contains list in extra text verbatim' );

    my $html_body = ( $emails[0]->parts() )[1]->body();
    like( $html_body, qr{<p>\s*Here is a paragraph[^<]+<br />\s*</p>}s,
          'html body contains extra text as html' );
    like( $html_body, qr{<li>\s*A list},
          'html body contains list items' );
}

{
    # {bz: 4767}: Re-invited user is not assigned to the correct account
    my $deleted = Socialtext::Account->Deleted();

    # create a user in a new account
    my $account = Socialtext::Account->create(name => "fuzz");

    {
        my $user = Socialtext::User->create(
            username      => 'deleted@ken.socialtext.net',
            first_name    => 'Dele',
            last_name     => 'Ted',
            email_address => 'deleted@ken.socialtext.net',
            password      => 'd3vnu11l'
        );

        $user->deactivate;
        is($user->primary_account_id, $deleted->account_id, "User is deleted");
        ok !$user->requires_password_change, "Password confirmation mail has not been sent";
    }

    my $invitation = Socialtext::WorkspaceInvitation->new(
        workspace  => $workspace,
        from_user  => $current_user,
        invitee    => 'deleted@ken.socialtext.net',
        viewer     => $viewer,
    );
    $invitation->send();

    {
        my $user = Socialtext::User->Resolve( 'deleted@ken.socialtext.net' );
        is($user->primary_account_id, $workspace->account_id,
            "User's primary account is re-assigned to workspace's account on re-invite");
        ok $user->requires_password_change, "Password confirmation mail has been sent";
    }
}

sub _confirm_user_if_neccessary {
    my $username = shift;

    my $user = Socialtext::User->new( username => $username );

    if ($user && $user->requires_email_confirmation) {
        warn "# Confirming user $username\n";
        $user->confirm_email_address();
        $user->update_store( password => 'secret' );
        return 1;
    }

    return 0;
}
