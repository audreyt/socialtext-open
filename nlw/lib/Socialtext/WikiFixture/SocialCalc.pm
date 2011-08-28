package Socialtext::WikiFixture::SocialCalc;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::WikiFixture::Socialtext';
use Test::More;

=head1 NAME

Socialtext::WikiFixture::SocialCalc - Helper functions to make testing  without using a browser

=cut

our $VERSION = '0.01';

=head1 DESCRIPTION

This module is a subclass of Socialtext::WikiFixture::Socialtext and includes
extra commands to provide both syntatic sugar for SocialCalc testing and to make
the Socialcalc wikitests better.

=head1 FUNCTIONS

Are identical to it's parent object.  I will just overload the command handler.


=cut

=head2 sc_right_cursor

Move the selected field to the right on a socialcalc page open for edit

=cut


my $tab = '\9';
my $down = '\13';
my $terminator = 'n';

sub sc_right_cursor {
    my $self = shift;
    $self->handle_command('keyPress','st-page-content', $tab, $terminator);
}

=head2 sc_left_cursor 

Move the selected field to the right on a socialcalc page open for edit

=cut

sub sc_left_cursor {
    my $self = shift;
    $self->handle_command('ShiftKeyDown',$terminator);
    $self->handle_command('keyPress','st-page-content', $tab, $terminator);
    $self->handle_command('ShiftKeyUp',$terminator);        
}
    

=head2 sc_down_arrow

Move the cursor down

=cut

sub sc_down_arrow {
    my $self = shift;
    $self->handle_command('keyPress','st-page-content', $down, $terminator);
}



=head1 AUTHOR

Matthew Heusser, C<< <matt.heusser at socialtext.com> >>

=head1 BUGS

Right now, this only works on FireFox. 

Please report any bugs or feature requests to
C<bug-socialtext-editpage at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Socialtext-WikiTest>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Socialtext::WikiFixture::SocialCalc

You can also look for information at:

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2008 Matthew Heusser, all rights reserved.

=cut

1;
