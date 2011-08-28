# @COPYRIGHT@
package Test::Socialtext::Mechanize;

use strict;
use warnings;
use Test::WWW::Mechanize;
use Test::More;
use Carp qw( croak );

use base qw( Test::WWW::Mechanize );

=head1 NAME

Test::Socialtext::Mechanize - The TW-specific mech subclass

=head1 SYNOPSIS

    use Test::Socialtext::Mechanize;

    my $mech = Test::Socialtext::Mechanize->new;
    $mech->get( $url );

=head1 DESCRIPTION

The TW mech is a standard Test::WWW::Mechanize, with NLW-specific
methods added.

=head1 METHODS

=head2 new

Standard Mech constructor.

=cut

sub new {
    my $class = shift;
    my %passed_args = @_;

    my $self = $class->SUPER::new( %passed_args );

    return $self;
}

sub linter {
    my $self = shift;

    if ( !$self->{_linter} ) {
        require HTML::Lint;
        $self->{_linter} = HTML::Lint->new;
    }
    return $self->{_linter};
}

sub get {
    my $self = shift;
    my $rc = $self->SUPER::get( @_ );

    if ( $self->is_html && $self->linter ) {
        my $linter = $self->linter;
        $linter->newfile();
        $linter->clear_errors();

        $linter->parse( $self->content );
        my @errors = $linter->errors;
        warn $_->as_string, "\n" for @errors;
    }
    return $rc;
}


=head2 html_ok( [$linter] [$msg] )

Checks the validity of the HTML on the current page.  If the page is not
HTML, then it fails.  If you need to pass a custom HTML::Lint object in,
you can.

=cut

sub html_ok {
    my $self = shift;
    my $linter = (ref($_[0]) eq "HTML::Lint") ? shift : $self->linter;
    my $msg = shift || $self->uri;

    my $ok;

    if ( $self->is_html ) {
        require Test::HTML::Lint;

        local $Test::Builder::Level = $Test::Builder::Level + 1;
        $linter->newfile( $self->uri );
        $linter->clear_errors();
        $ok = Test::HTML::Lint::html_ok( $linter, $self->content, $msg );
    }
    else {
        $ok = fail( $msg );
    }

    return $ok;
}

1; # Happy
