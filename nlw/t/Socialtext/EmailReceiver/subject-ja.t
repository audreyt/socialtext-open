#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::More;

use Socialtext::EmailReceiver::ja;
use Test::MockObject;

my %tests = (
    'Normal Subject'            => 'Normal Subject',
    'Re: Lalala'                => 'Lalala',
    'Re: re: Re:  Re: Lalalala' => 'Lalalala',
    'Fwd: Re:  Re: Hello'       => 'Hello',
    'Fwd:Re:Re:Goodbye'         => 'Goodbye',
    'Re: Fwd:  Re:  Cheap St0x' => 'Cheap St0x',
    '   Spacey    '             => 'Spacey',
);

plan tests => scalar keys %tests;

for my $subject ( sort keys %tests ) {
    my $receiver
        = Socialtext::EmailReceiver::ja->_new( mock_email($subject), mock_ws() );

    is( $receiver->_clean_subject(), $tests{$subject},
        "Clean subject for $subject is $tests{$subject}" );
}

sub mock_email {
    my $subject = shift;

    my $email = Test::MockObject->new();
    $email->mock(
        'header',
        sub {
            if ( $_[1] eq 'Subject' ) {
                return $subject;
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
    $ws->set_isa( 'Socialtext::Workspace' );

    return $ws;
}
