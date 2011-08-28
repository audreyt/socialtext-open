package Socialtext::WebApp;
# @COPYRIGHT@

use strict;
use warnings;
use unmocked 'Test::MockObject';
use unmocked 'Socialtext::URI';
use mocked 'Apache::Request';

###############################################################################
# Set up mock object
our $Instance;

sub NewForNLW {
    unless ($Instance) {
        $Instance = Test::MockObject->new()
            ->mock( 'apache_req', sub { 
                    my $self = shift;
                    $self->{apache_req} ||= Apache::Request->new();
                    $self->{apache_req}
                } )
            ->set_false( '_handle_error' )
            ->mock( 'redirect' => sub {
                my $self = shift;
                my $uri  = (@_ == 1) ? shift : Socialtext::URI::uri(@_);
                $self->{redirect} = $uri;
            } );
    }
    return $Instance;
}

sub instance { return NewForNLW() }
sub clear_instance { undef $Instance }

1;

=head1 NAME

Socialtext::WebApp - MOCKED Socialtext::WebApp

=head1 SYNOPSIS

  use mocked 'Socialtext::WebApp';

  # get the WebApp instance
  $app = Socialatext::WebApp->NewForNLW();

=head1 DESCRIPTION

F<t/lib/Socialtext/WebApp.pm> provides a B<mocked> version of
C<Socialtext::WebApp> that can be used for testing.

This mocked version is implemented as a singleton; all operations are
performed against a single mocked object.  Between tests, you probably want to
call C<clear()> to clear the record of what's been called.

=head1 MOCKED METHODS

B<NOTE:> this mocked version of C<Socialtext::WebApp> does not (yet) mock all
of the functionality/methods provided by the original.  If you see methods
missing here which you need to test, please add them to the mocked version.

=over

=item B<apache_req()>

Returns an instance of a mocked C<Apache::Request> object.

=item B<_handle_error()>

=item B<redirect()>

=back

=head1 SEE ALSO

L<Test::MockObject>

=cut
