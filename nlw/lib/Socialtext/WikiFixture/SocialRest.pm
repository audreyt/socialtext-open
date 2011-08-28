# @COPYRIGHT@
package Socialtext::WikiFixture::SocialRest;
use strict;
use warnings;
use base 'Socialtext::WikiFixture::SocialBase';
use base 'Socialtext::WikiFixture';
use Cwd;
use Guard qw(scope_guard);
use Socialtext::System qw(shell_run);
use Test::HTTP;
use Test::More;

# mix-in some commands from the Socialtext fixture
# XXX Should move these to socialbase?
{
    require Socialtext::WikiFixture::Socialtext;
    no warnings 'redefine';
    *st_ldap = \&Socialtext::WikiFixture::Socialtext::st_ldap;
}

=head1 NAME

Socialtext::WikiFixture::SocialRest - Test the REST API without using a browser

=cut

our $VERSION = '0.01';

=head1 DESCRIPTION

This module is a subclass of Socialtext::WikiFixture and includes
extra commands specific for testing the Socialtext REST API.

=head1 FUNCTIONS

=head2 init()

Creates the Test::HTTP object.

=cut

sub init {
    my $self = shift;

    # Set up the Test::HTTP object initially
    Socialtext::WikiFixture::SocialBase::init($self);
    Socialtext::WikiFixture::init($self);
}

=head2 handle_command( @row )

Run the command.  Subclasses can override this.

=cut

sub handle_command {
    my $self = shift;
    my ($command, @opts) = $self->_munge_command_and_opts(@_);

    # Lets (ab)use some existing test methods

    eval { $self->SUPER::_handle_command($command, @opts) };
    return unless $@;

    if ($self->can($command)) {
        return $self->$command(@opts);
    }
    die "Unknown command for the fixture: ($command)\n";

}

=head2 comment ( message )

Use the comment as a test comment

=cut

sub comment {
    my $self = shift;
    $self->{http}->name(shift);
}

sub st_client_ssl {
    my $self    = shift;
    my $command = shift;
    my @args    = @_;

    if ($command eq 'server-on') {
        $self->_manage_certs(qw( init --force ));
        $self->_manage_certs(qw( install ));
        $self->st_config('set ssl_only 1');
        shell_run(qw( gen-config ));
        $self->restart_everything;
    }
    elsif ($command eq 'server-off') {
        $self->st_config('set ssl_only 0');
        shell_run(qw( gen-config ));
        $self->restart_everything;
    }
    elsif ($command eq 'client-on') {
        my $username = shift @args;
        die "cannot 'st-client-ssl client-on' without a username\n" unless $username;
        $self->_manage_certs(qw( client --force --username ), $username);
        $ENV{HTTPS_PKCS12_FILE} = "ssl/binary/${username}.p12";
        $ENV{HTTPS_PKCS12_PASSWORD} = "password";
    }
    elsif ($command eq 'client-off') {
        delete $ENV{HTTPS_PKCS12_FILE};
        delete $ENV{HTTPS_PKCS12_PASSWORD};
    }
    else {
        die "unknown st-client-ssl option '$command'\n";
    }
}

sub _manage_certs {
    my $self = shift;
    my @cmds = @_;

    my $ssl_dir = 'ssl';
    my $old_dir = getcwd();

    mkdir($ssl_dir, 0755) unless (-e $ssl_dir);
    chdir($ssl_dir) || die "Can't cd to '$ssl_dir'; $!";
    scope_guard { chdir($old_dir) };

    shell_run('manage-certs', @cmds);
}

=head1 AUTHOR

Luke Closs, C<< <luke.closs at socialtext.com> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-socialtext-editpage at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Socialtext-WikiTest>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Socialtext::WikiFixture::SocialRest

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Socialtext-WikiTest>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Socialtext-WikiTest>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Socialtext-WikiTest>

=item * Search CPAN

L<http://search.cpan.org/dist/Socialtext-WikiTest>

=back

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2008 Luke Closs, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
