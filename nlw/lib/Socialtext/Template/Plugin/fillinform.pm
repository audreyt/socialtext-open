package Socialtext::Template::Plugin::fillinform;

# @COPYRIGHT@
use strict;
use warnings;

require Template::Plugin;
use base qw(Template::Plugin);

use HTML::FillInForm::ForceUTF8;

use vars qw($FILTER_NAME);
$FILTER_NAME = 'fillinform';

sub new {
    my ( $class, $context, @args ) = @_;
    my $name = $args[0] || $FILTER_NAME;
    $context->define_filter( $name, $class->filter_factory() );
    bless {}, $class;
}

sub filter_factory {
    my $class = shift;
    my $sub = sub {
        my ( $context, @args ) = @_;
        my $config = ref $args[-1] eq 'HASH' ? pop(@args) : {};
        return sub {
            my $text = shift;
            my $fif  = HTML::FillInForm::ForceUTF8->new;
            return $fif->fill( scalarref => \$text, %$config );
        };
    };
    return [ $sub, 1 ];
}

1;

