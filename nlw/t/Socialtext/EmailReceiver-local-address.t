#!perl
# @COPYRIGHT@
use Test::More;

use warnings;
use strict;

BEGIN {
    eval 'use Test::MockObject';
    plan skip_all => 'This test requires Test::MockObject' if $@;
}

use Socialtext::EmailReceiver::en;

my %tests = (
    q|"admin+My Test"@socialtext.net| =>
        'name and category with spaces wrapped in quotes',
    q|admin+MyTest@socialtext.net| => 'name and category but no quotes',
    q|"admin"@socialtext.net|      => 'name wrapped in quotes',
    q|ADmin@socialtext.net|        => 'mixed case ws name',
    q|admin@socialtext.net|        => 'lower case ws name'
);

plan tests => scalar keys %tests;

for my $address ( sort keys %tests ) {
    my $receiver
        = Socialtext::EmailReceiver::en->_new( mock_email($address), mock_ws() );

    my $found = $receiver->_get_to_address_local_part();
    ( my $expect = $address ) =~ s/\@socialtext\.net$//;
    $expect =~ s/^\"|\"$//g;

    is( $found, $expect, $tests{$address} );
}


sub mock_email {
    my $address = shift;

    my $email = Test::MockObject->new();
    $email->mock(
        'header',
        sub {
            if ( $_[1] eq 'To' ) {
                return $address;
            }
            else {
                return '';
            }
        }
    );

    return $email;
}

sub mock_ws {
    my $ws = Test::MockObject->new();

    $ws->mock( 'incoming_email_placement', sub { 'top' } );
    $ws->mock( 'name', sub { 'admin' } );

    $ws->set_isa( 'Socialtext::Workspace' );

    return $ws;
}
