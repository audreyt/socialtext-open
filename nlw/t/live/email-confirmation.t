#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Live fixtures => ['admin'];
# Importing Test::Socialtext will cause it to create fixtures now, which we
# want to happen want to happen _after_ Test::Live stops any running
# Apache instances, and all we really need here is Test::More.
use Test::More tests => 12;
use Socialtext::User;

# plan tests => 1;

warn("currently just testing the redirect and confirmation not found error paths\n");

my $live = Test::Live->new();
my $base_uri = $live->base_url;

my $confirming_user =
  Socialtext::User->create(
                           username => 'email-confirmer1',
                           email_address => 'devnull5@socialtext.com',
                           password => 'hubba-bubba',
                          );

CONFIRM_WITH_PASSWORD_REDIRECT_WORKS:{
    $confirming_user->set_confirmation_info();
    my $uri = $confirming_user->confirmation_uri();
    $live->mech()->get($uri);
    my $content = $live->mech()->content();
    is( $live->mech()->status, 200, "GET $uri returned 200" );
    like( $live->mech()->uri(), qr%/nlw/login%, "redirected to /nlw/login" );
    unlike( $content, qr/given confirmation URL does not match/,
            "check content to make sure we don't get an error message" );

    # clear the confirmation info
    $confirming_user->confirm_email_address();
}

CONFIRM_CHANGE_PASSWORD_REDIRECT_WORKS:{
    $confirming_user->set_confirmation_info( is_password_change => 1 );
    my $uri = $confirming_user->confirmation_uri();
    $live->mech()->get($uri);
    my $content = $live->mech()->content();
    is( $live->mech()->status, 200, "GET $uri returned 200" );
    like( $live->mech()->uri(), qr%/nlw/choose_password%, "redirected to /nlw/choose_password" );
    unlike( $content, qr/given confirmation URL does not match/,
            "check content to make sure we don't get an error message" );

    # clear the confirmation info
    $confirming_user->confirm_email_address();
}

BUNGLED_URI_FAILS_CORRECTLY:{
    $confirming_user->set_confirmation_info( is_password_change => 1 );
    my $uri = $confirming_user->confirmation_uri();
    $uri =~ s/hash=.*$/hash=what+hath+god+wrought/;
    $live->mech()->get($uri);
    my $content = $live->mech()->content();
    is( $live->mech()->status, 200, "GET $uri returned 200" );
    like( $live->mech()->uri(), qr%/nlw/login%, "redirected to /nlw/login" );
    like( $content, qr/given confirmation URL does not match/,
          "check content to make sure we don't get an error message" );

    # clear the confirmation info
    $confirming_user->confirm_email_address();
}

URI_WITH_PLUS_WORKS_CORRECTLY: {
    my $uri = 'foo';
    warn( "looping until we get a confirmation hash with a '+'\n" );
    while ( $uri !~ /%2B/ ) {
        # clear the confirmation info
        $confirming_user->confirm_email_address();
        # generate a new one
        $confirming_user->set_confirmation_info( is_password_change => 1 );
        $uri = $confirming_user->confirmation_uri();
    }
    # change the %2B to a plus sign
    $uri =~ s/%2B/+/g;
    $live->mech()->get($uri);
    my $content = $live->mech()->content();
    is( $live->mech()->status, 200, "GET $uri returned 200" );
    like( $live->mech()->uri(), qr%/nlw/choose_password%, "redirected to /nlw/choose_password" );
    unlike( $content, qr/given confirmation URL does not match/,
            "check content to make sure we don't get an error message" );

    # clear the confirmation info
    $confirming_user->confirm_email_address();
       
}
