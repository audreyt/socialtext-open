#!perl
#@COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 26;

fixtures(qw( db ));

BEGIN {
    use_ok('Socialtext::Session');
}

{
    my $session = Socialtext::Session->new();
    $session->add_message('Hello');

    my @messages = $session->messages();
    is( scalar @messages, 1, 'there is one message in the session' );
    is( $messages[0], 'Hello', 'check message content' );

    ok( ! $session->messages(), 'calling messages() once delete messages from session' );
}

{
    my $session = Socialtext::Session->new();
    $session->add_message('Hello');
    $session->add_message('Goodbye');

    my @messages = $session->messages();
    is( scalar @messages, 2, 'there are two messages in the session' );
    is( $messages[0], 'Hello', 'check message content' );
    is( $messages[1], 'Goodbye', 'check message content' );
}

{
    my $session = Socialtext::Session->new();
    $session->add_error('Hello');

    ok( $session->has_errors(), 'has_errors() is true' );

    my @errors = $session->errors();
    is( scalar @errors, 1, 'there is one error in the session' );
    is( $errors[0], 'Hello', 'check error content' );

    ok( ! $session->errors(), 'calling errors() once delete errors from session' );
    ok( ! $session->has_errors(), 'has_errors() is false' );
}

{
    my $session = Socialtext::Session->new();
    $session->add_error('Hello');
    $session->add_error('Goodbye');

    my @errors = $session->errors();
    is( scalar @errors, 2, 'there are two errors in the session' );
    is( $errors[0], 'Hello', 'check error content' );
    is( $errors[1], 'Goodbye', 'check error content' );
}

{
    my $session = Socialtext::Session->new();
    $session->save_args( foo => 1, bar => 2 );

    my $args = $session->saved_args();
    is( $args->{foo}, 1, 'saved_args - foo = 1' );
    is( $args->{bar}, 2, 'saved_args - bar = 2' );
}

{ # remove
    my $session = Socialtext::Session->new();
    $session->save_args( foo => 1, bar => 2 );

    $session->remove('foo');

    my $args = $session->saved_args();
    is( $args->{foo}, undef, 'saved_args - foo is undef' );
    is( $args->{bar}, 2, 'saved_args - bar = 2' );
}

{
    my $session = Socialtext::Session->new();
    $session->set_last_workspace_id(37);

    is( $session->last_workspace_id(), 37, 'last workspace id is 37' );
}

{
    my $session = Socialtext::Session->new();
    $session->add_message('Hello');
    $session->add_error('Kaboom');
    $session->save_args( foo => 1 );

    $session->clean();

    ok( ! $session->messages(), 'clean() deletes messages' );
    ok( ! $session->errors(), 'clean() deletes errors' );
    ok( ! $session->saved_args()->{foo}, 'clean() deletes saved args' );
}

{
    my $session = Socialtext::Session->new();
    $session->add_message('Hello');
    $session->add_message('Hello');

    is( scalar $session->messages(), 1, 'duplicate messages are ignored' );
}

{
    my $session = Socialtext::Session->new();
    $session->add_error('Hello');
    $session->add_error('Hello');

    is( scalar $session->errors(), 1, 'duplicate errors are ignored' );
}

{
    my $session = Socialtext::Session->new();
    $session->add_error( { type => 'foo', message => 'Hello' } );
    $session->add_error( { type => 'foo', message => 'Hello' } );

    is( scalar $session->errors(), 1, 'duplicate errors are ignored - error is a ref' );
}


# For our purposes, the session can be a dumb hashref
package Apache::Session::Wrapper;

no warnings 'redefine';

sub new {
    return bless {}, $_[0];
}

sub session {
    return $_[0];
}
