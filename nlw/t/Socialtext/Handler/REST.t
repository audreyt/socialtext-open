#!perl
# @COPYRIGHT@

use strict;
use warnings;

BEGIN {
    use Test::Socialtext tests => 3;
    fixtures(qw( empty ));
    use_ok( 'Socialtext::Handler::REST' );
}

DATA_URL_DOEST_NOT_MATCH_INCORRECT_THINGS: {
    my $req = FakeRequest->new( uri => "/datacow" );
    my $ra = Socialtext::Handler::REST->new( request => $req );
    $ra->loadResource( $req->uri );
    my %headers = $ra->header;
    is( $headers{-status}, "404 Not Found" );
}

DATA_URL_DOEST_NOT_MATCH_INCORRECT_THINGS2: {
    my $req = FakeRequest->new( uri => "/i/love/datacow/index.cgi" );
    my $ra = Socialtext::Handler::REST->new( request => 1 );
    $ra->loadResource( $req->uri );
    my %headers = $ra->header;
    is( $headers{-status}, "404 Not Found" );
}

package FakeRequest;

our $AUTOLOAD;
sub new { my $c = shift; bless({@_}, $c); }
sub AUTOLOAD {
    my $self   = shift;
    my $method = $AUTOLOAD;
    $method =~ s/.*://;
    return if $method eq 'DESTROY';
    return @_ ? $self->{$method} = shift : $self->{$method};
}
