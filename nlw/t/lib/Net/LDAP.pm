package Net::LDAP;
# @COPYRIGHT@

use strict;
use warnings;
use unmocked 'Test::MockObject';
use unmocked 'Net::LDAP::Constant', 
    qw/LDAP_SUCCESS LDAP_TIMEOUT LDAP_NO_RESULTS_RETURNED 
       LDAP_INVALID_CREDENTIALS/;
use unmocked 'Net::LDAP::Util';

my %behaviour;
sub set_mock_behaviour {
    shift if ($_[0] eq 'Net::LDAP');
    %behaviour = @_;
}
my $mocked;
sub mocked_object {
    return $mocked;
}

sub new {
    my ($class, $host, %opts) = @_;

    # fail right away if we're not supposed to be able to connect
    return undef if $behaviour{'connect_fail'};

    # instantiate a new Net::LDAP object
    my $self = {
        'sources'   => $host,
        %opts,
        };
    bless $self, $class;

    # create new mock object for testing, and set its behaviour
    $mocked = Test::MockObject->new($self);
    $mocked->set_true( 'disconnect' );

    $behaviour{'bind_fail'}
        ? $mocked->mock( 'bind', sub {
            return Net::LDAP::Message->new(code=>LDAP_INVALID_CREDENTIALS)
            } )
        : $behaviour{'bind_credentials'}
            ? $mocked->mock( 'bind', sub {
                # auth, requiring authentication
                my ($self, $user, %opts) = @_;
                my $pass = $opts{'password'};
                if ($user) {
                    # authenticated bind attempt
                    return ($behaviour{'bind_credentials'}{$user} eq $pass)
                        ? return Net::LDAP::Message->new(code=>LDAP_SUCCESS)
                        : return Net::LDAP::Message->new(code=>LDAP_INVALID_CREDENTIALS);
                }
                # anonymous bind attempt
                return $behaviour{'bind_credentials'}{'anonymous'}
                    ? return Net::LDAP::Message->new(code=>LDAP_SUCCESS)
                    : return Net::LDAP::Message->new(code=>LDAP_INVALID_CREDENTIALS);
                } )
            : $mocked->mock( 'bind', sub {
                # auth, anonymous ok
                return Net::LDAP::Message->new(code=>LDAP_SUCCESS);
                } );

    $behaviour{'search_fail'}
        ? $mocked->mock( 'search', sub {
            return Net::LDAP::Search->new(code=>LDAP_TIMEOUT);
            } )
        : $behaviour{'search_results'}
            ? $mocked->mock( 'search', sub {
                return Net::LDAP::Search->new(
                    code    => LDAP_SUCCESS,
                    entries => [ @{$behaviour{'search_results'}} ],
                    )
                } )
            : $mocked->mock( 'search', sub {
                return Net::LDAP::Search->new(code=>LDAP_NO_RESULTS_RETURNED)
                } );

    # return the mocked object back to the caller.
    return $mocked;
}

package Net::LDAP::Message;
sub new {
    my ($class, %opts) = @_;
    my $self = \%opts;
    bless $self, $class;
    return $self;
}
sub code {
    return shift->{'code'};
}
sub error {
    my $self = shift;
    if ($self->{'code'}) {
        return Net::LDAP::Util::ldap_error_text( $self->{'code'} );
    }
    return;
}

package Net::LDAP::Search;
our @ISA = qw(Net::LDAP::Message);
sub shift_entry {
    my $self = shift;
    if (scalar @{$self->{'entries'}}) {
        return Net::LDAP::Message::Entry->new( %{shift @{$self->{'entries'}}} );
    }
    return undef;
}
sub entries {
    my $self = shift;
    my @entries = map { Net::LDAP::Message::Entry->new(%{$_}) } @{$self->{'entries'}};
}
sub count {
    my $self = shift;
    return scalar @{$self->{'entries'}};
}

package Net::LDAP::Message::Entry;
sub new {
    my ($class, %opts) = @_;
    my $self = \%opts;
    bless $self, $class;
    return $self;
}
sub get_value {
    my ($self, $field) = @_;
    return $self->{$field};
}
sub dn {
    my $self = shift;
    return $self->{'dn'};
}

1;

=head1 NAME

Net::LDAP - MOCKED Net::LDAP

=head1 SYNOPSIS

  use mocked 'Net::LDAP';
  ...

  # set behaviour of mocked LDAP connection
  Net::LDAP->set_mock_behaviour(
    # ...
    );

  # run tests
  # ...

  # examine Test::MockObject object...
  $mock = Net::LDAP->mocked_object();
  ...

=head1 DESCRIPTION

F<t/lib/Net/LDAP.pm> provides a B<mocked> version of C<Net::LDAP> that can be
used for testing.

Currently, only the methods actually used are mocked; if you're adding new
functionality to the rest of the project then you may need to mock additional
methods as necessary.

=head1 CONTROLLING MOCK BEHAVIOUR

The following behaviour of C<Net::LDAP> can be controlled by calling
C<Net::LDAP-E<gt>set_mock_behaviour()>:

=over

=item connect_fail=>1

All connection attempts will fail.

=item bind_fail=>1

All bind attempts will fail.

=item bind_credentials => { 'username' => 'password', 'user2' => 'pass2', ... }

Bind attempts require any one of the specified credentials.

Use a username of "anonymous" to control whether or not anonymous binds
succeed/fail.  e.g. anonymous=>1

=item search_fail=>1

Any attempts to search the LDAP directory will fail.

=item search_results=>[...]

A list-ref of hash-refs, containing search results.  Each search result entry
should contain the LDAP attributes/values that are expected to be returned.

=back

Example:

  Net::LDAP->set_mock_behaviour(
    bind_credentials => {
      'cn=First Last,dc=example,dc=com' => 'foobar',
      },
    search_results => [
      { dn => 'cn=First Last,dc=example,dc=com',
        cn => 'First Last',
        gn => 'First',
        sn => 'Last',
        mail => 'test@example.com',
        },
      ],
    );

B<NOTE,> that each call to C<set_mock_behaviour()> replaces the B<entire> set
of behaviour that is to be expected; we don't add to the behaviour, but replace
it outright with what you've specified.

Thus, to reset the behaviour back to the defaults, just use:

  Net::LDAP->set_mock_behaviour();

=head1 EXAMINING RESULTS

Once you've finished running your tests, you can access the mocked C<Net::LDAP>
object by calling C<Net::LDAP-E<gt>mocked_object()>.  B<Note,> though, that
this returns to you the I<most recently mocked C<Net::LDAP> object>; if you've
had several LDAP calls fired off and have created more than one C<Net::LDAP>
object then you're only going to find results on the B<most recent one.>

Once you've got a copy of the mocked C<Net::LDAP> object, you can examine it
using any of the methods provided by C<Test::MockObject>.

Example:

  $mock = Net::LDAP->mocked_object();
  $mock->called_pos_ok( 1, 'bind' );
  ($self, $dn, %opts) = $mock->call_args(1);
  ok defined $dn, 'authenticated bind; got DN';
  ok defined $opts{'password'}, 'authenticated bind; got password';

=head1 SEE ALSO

L<Net::LDAP>,
L<Test::MockObject>.

=cut
