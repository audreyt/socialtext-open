# @COPYRIGHT@
package Socialtext::Session;
use 5.12.0;
use warnings;

our $VERSION = '0.01';

use Apache::Session::Wrapper 0.28;
use Data::Dumper ();
use Socialtext::SQL qw/get_dbh/;
use Socialtext::AppConfig;
use HTML::Scrubber;
use Scalar::Util 'reftype';

Apache::Session::Wrapper->RegisterFlexClass(
    type => 'store',
    name => 'Postgres::Socialtext',
    required => 'Postgres',
);

sub new {
    my $class = shift;

    return bless {}, $class;
}

sub _session {
    return $_[0]->_wrapper->session;
}

sub _ssl_only {
    my $self = shift;
    unless (defined $self->{ssl_only}) {
        $self->{ssl_only} = Socialtext::AppConfig->ssl_only ? 1 : 0;
    }
    return $self->{ssl_only};
}

sub _wrapper {
    return $_[0]->{wrapper} if $_[0]->{wrapper};

    $_[0]->{wrapper} =
        Apache::Session::Wrapper->new(
            use_cookie  => 1,
            cookie_name => 'NLW-session',
            cookie_secure => $_[0]->_ssl_only(),
            class       => 'Flex',
            store       => 'Postgres::Socialtext',
            lock        => 'Null',
            generate    => 'MD5',
            serialize   => 'Base64',
            handle      => get_dbh(),
            commit      => 0, # autocommit
            ($Socialtext::PlackApp::Response ? (header_object => $Socialtext::PlackApp::Response) : ()),
        );

    return $_[0]->{wrapper};
}

sub save_args {
    my $self = shift;
    my %args = @_;

    while ( my ( $k, $v ) = each %args ) {
        $self->_session->{__saved_args__}{$k} = $v;
    }
}

sub saved_args { $_[0]->_session->{__saved_args__} || {} }

sub remove {
    my ($self,$key) = @_;
    delete $self->_session->{__saved_args__}{$key};
}

sub add_message {
    return if $_[0]->_exists( $_[0]->_session->{__messages__}, $_[1] );
    push @{ $_[0]->_session->{__messages__} }, $_[1];
}

sub add_error {
    return if $_[0]->_exists( $_[0]->_session->{__errors__}, $_[1] );
    push @{ $_[0]->_session->{__errors__} }, $_[1];
}

sub _exists {
    shift;
    my $array = shift;
    my $item  = shift;

    my $string = ref $item ? _stringify($item) : $item;

    return 1 if grep { ( ref $_ ? _stringify($_) : $_ ) eq $string } @{$array};
}

# This is crude but given that we only put simple hash references into
# the session, as opposed to any sort of complex object, I expect this
# should work, and not be too slow.
sub _stringify {
    return Data::Dumper::Dumper( $_[0] );
}

sub last_workspace_id { $_[0]->_session->{last_workspace_id} }

sub set_last_workspace_id { $_[0]->_session->{last_workspace_id} = $_[1] }

sub messages { my $s = $_[0]->_session;
               $s->{__messages__} ? map { _scrub($_) } @{ delete $s->{__messages__} } : () }

sub errors   { my $s = $_[0]->_session;
               $s->{__errors__} ? map { _scrub($_) } @{ delete $s->{__errors__} } : () }

sub _scrub {
    my $obj = shift;
    given (reftype $obj) {
        when ('ARRAY') {
            $_ = _scrub($_) for @$obj;
            return $obj;
        }
        when ('HASH') {
            $obj->{$_} = _scrub($obj->{$_}) for keys %$obj;
            return $obj;
        }
        when ('SCALAR') {
            $$obj = _scrub($$obj);
            return $obj;
        }
        default {
            state $scrubber //= HTML::Scrubber->new( allow => [ qw[ p b i u hr br em strong span ] ] );
            return $scrubber->scrub($obj);
        }
    }
}

sub has_errors { scalar @{ $_[0]->_session->{__errors__} || [] } }

sub clean { delete @{ $_[0]->_session }{ qw( __messages__ __errors__ __saved_args__ ) } }

sub write { delete $_[0]->{wrapper} }


1;
__END__

=head1 NAME

Socialtext::Session - Provides a higher-level session API for Socialtext apps

=head1 SYNOPSIS

  use Socialtext::Session;

  my $session = Socialtext::Session->from_apache_object($r);

=head1 DESCRIPTION

Uses C<Apache::Session::Wrapper> to provide a session for Socialtext
apps. It also uses a custom session storage subclass to set/update
C<session.last_updated> so we can delete stale sessions.

=head1 FUNCTIONS

This package provides the following functions:

=over 4

=item * Socialtext::Session->new($r)

Takes an C<Apache> object and returns a new C<Socialtext::Session>
object.

=item * $session->save_args(%kv_pairs)

Saves a set of key/value pairs in the session for later retrieval via
the C<saved_args()> method.

=item * $session->saved_args()

Returns the saved args as a hashref.

=item * $session->remove($arg)

Remove the value identified by the key $arg.

=item * $session->add_message($message)

=item * $session->add_error($message)

Stores a message or error in the session

=item * $session->set_last_workspace_id($ws_id)

Sets the workspace_id for the last workspace the client viewed.

=item * $session->has_errors()

Returns true if the session has errors, without deleting them from the
session.

=item * $session->messages()

=item * $session->errors()

Retrieves the stored messages or errors. Once retrieved, they are
deleted from the session.

=item * $session->last_workspace_id()

Retrieves the workspace_id for the last workspace the client viewed.

=item * $session->clean()

Deletes all saved args, messages, and errors in the session.

=item * $session->write()

Forces the session to be written to the DBMS.

B<WARNING:> calling this method destroys the session, so it can only
be called once, and after that the object is no longer usable.

=back

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005-2006 Socialtext, Inc., All Rights Reserved.

=cut
