#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::HTTP::Socialtext tests => 40;

# This test verifies the expected behaviour presented at
#
#   https://www.socialtext.net
#     /stdev/index.cgi?socialtext_expected_credentials_behaviors

use CGI::Cookie;
use HTTP::Cookies;
use Socialtext::User;
use Socialtext::HTTP ':codes';
use Socialtext::HTTP::Cookie;
use Test::Live;

our $TODO;

# Logical-or together to get the type of creds you'd like.
my $NO_CREDS   = 0;
my $HTTP_BASIC = 1;
my $COOKIE     = 2;
my $BOGUS      = 4;

my @CREDS_BEHAVIORS = ( $HTTP_BASIC, $COOKIE, $BOGUS );
my %DESCRIPTION = (
    $HTTP_BASIC => 'HTTP Basic',
    $COOKIE     => 'HTTP Cookie',
    $BOGUS      => 'bogus creds',
);

# noauth now redirects to just feed so we go there directly
# to see what happens authwise
Noauth_feeds: {
    my $t = make_tester( 'noauth feeds', '/feed/workspace/public' );
    $t->( $_, 200 )
        for ( $NO_CREDS, $HTTP_BASIC, $COOKIE, $HTTP_BASIC | $BOGUS );
    TODO: {
        local $TODO = "Need to fix a bug in User.pm";
        $t->($COOKIE | $BOGUS, 200);
    }
}

# only test admin here. public will never present creds so 
# we don't test it here.
Auth_feeds: {
    for my $ws qw(admin) {
        my $t = make_tester( "$ws auth feed", "/feed/workspace/$ws" );
        $t->( $_, 200 ) for ( $HTTP_BASIC, $COOKIE );
        $t->( $_, 401 ) for ( $NO_CREDS, $HTTP_BASIC | $BOGUS );
        TODO: {
            local $TODO = "Need to fix a bug in User.pm";
            $t->($COOKIE | $BOGUS, 401);
        }
    }
}

Public_rest: {
    my $t = make_tester( 'public REST', '/data/workspaces/public/pages' );
    $t->( $_, 200 ) for ( $HTTP_BASIC, $COOKIE );
    $t->( $_, 200 ) for ( $NO_CREDS, $HTTP_BASIC | $BOGUS );
    TODO: {
        local $TODO = "Need to fix a bug in User.pm";
        $t->($COOKIE | $BOGUS, 401);
    }
}

Private_rest: {
    my $t = make_tester( 'private REST', '/data/workspaces/admin/pages' );
    $t->( $_, 200 ) for ( $HTTP_BASIC, $COOKIE );
    $t->( $_, 401 ) for ( $NO_CREDS, $HTTP_BASIC | $BOGUS );
    TODO: {
        local $TODO = "Need to fix a bug in User.pm";
        $t->($COOKIE | $BOGUS, 401);
    }
}

Public_workspace: {
    my $t = make_tester( 'public workspace', '/public/index.cgi?public_wiki' );
    $t->( $_, 200 )
        for ( $NO_CREDS, $HTTP_BASIC, $COOKIE, $HTTP_BASIC | $BOGUS );
    TODO: {
        local $TODO = "Need to fix a bug in User.pm";
        $t->($COOKIE | $BOGUS, 200);
    }
}

Private_workspace: {
    my $t = make_tester( 'private workspace', '/admin/index.cgi?admin_wiki');
    $t->( $_, 200 ) for ( $HTTP_BASIC, $COOKIE);
    $t->( $_, 302 ) for ( $NO_CREDS, $HTTP_BASIC | $BOGUS );
    TODO: {
        local $TODO = "Need to fix a bug in User.pm";
        $t->( $COOKIE | $BOGUS, 302 );
    }
}

Public_miki: {
    my $t = make_tester( 'public miki', '/lite/page/public/public_wiki' );
    $t->( $_, 200 )
        for ( $NO_CREDS, $HTTP_BASIC, $COOKIE, $HTTP_BASIC | $BOGUS );
    TODO: {
        local $TODO = "Need to fix a bug in User.pm";
        $t->($COOKIE | $BOGUS, 200);
    }
}

Private_miki: {
    my $t = make_tester( 'private miki', '/lite/page/admin/admin_wiki' );
    $t->( $_, 200 ) for ( $HTTP_BASIC, $COOKIE );
    $t->( $_, 302 ) for ( $NO_CREDS, $HTTP_BASIC | $BOGUS );
    TODO: {
        local $TODO = "Need to fix a bug in User.pm";
        $t->($COOKIE | $BOGUS, 302);
    }
}

# Returns a function suitable for testing the given URL.
sub make_tester {
    my ( $name, $path ) = @_;
    my $url = Test::HTTP::Socialtext->url($path);

    # $f->(CREDS BEHAVIOR, EXPECTED HTTP CODE) will run the testing function
    # against the URL it was created with, with the type of creds you specify,
    # and will ensure that the HTTP response code is what you expect.
    return sub {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        my ( $creds_behavior, $expected_code ) = @_;
        my %behavior = map { ( $_, 1 ) }
            grep { ( $_ & $creds_behavior ) == $_ } @CREDS_BEHAVIORS;
        my $description = join ', ',
            map { $DESCRIPTION{$_} } sort keys %behavior;

        {
            my $test = Test::HTTP->new("$name $description");

            local $Test::HTTP::BasicUsername = $Test::HTTP::BasicUsername;
            local $Test::HTTP::BasicPassword = $Test::HTTP::BasicPassword;

            if ( $behavior{$BOGUS} ) {
                $Test::HTTP::BasicUsername = 'foo@example.com';
                $Test::HTTP::BasicPassword = 'sev?';
            }

            $test->ua->cookie_jar(
                Test::Socialtext::CookieJar->new($Test::HTTP::BasicUsername) )
                if $behavior{$COOKIE};

            unless ( $behavior{$HTTP_BASIC} ) {
                $Test::HTTP::BasicUsername = undef;
                $Test::HTTP::BasicPassword = undef;
            }

            $test->get($url);
            $test->status_code_is($expected_code);
        }
    };
}

package Test::Socialtext::CookieJar;

# This class implements the bare cookie jar spec (see LWP::UserAgent and
# HTTP::Cookies) but _always_ puts a cookie for its user in the outgoing HTTP
# request packet.
#
# EXTRACT: Having this class available to other tests might be a good step
# toward writing better live tests.

sub new { bless { username => $_[1] }, $_[0] }

sub extract_cookies { }

sub add_cookie_header {
    my ( $self, $request ) = @_;
    
    $request->header(Cookie => $self->_make_http_cookie());
}

sub _make_http_cookie {
    my ( $self ) = @_;

    # EXTRACT: Even if we have to use CGI::Cookie to build the string, it
    # would be nice to be able to extract some code from here to
    # ST::Apache::User or somesuch so that we're more ignorant of the name of
    # the cookie and how it's constructed. -mml 2007-03-09

    my $user = Socialtext::User->new( username => $self->{username} );

    # If no user got created, assume that we're trying to make bogus creds.
    my $user_id = $user ? $user->user_id : '314159';

    return '' . CGI::Cookie->new(
        -domain => Socialtext::AppConfig->cookie_domain,
        -name   => Socialtext::HTTP::Cookie->USER_DATA_COOKIE,
        -value  => {
            user_id => $user_id,
            MAC     => Socialtext::HTTP::Cookie->MAC_for_user_id($user_id),
        }
    );
}
