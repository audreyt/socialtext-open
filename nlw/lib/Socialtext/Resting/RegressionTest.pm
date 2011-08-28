# @COPYRIGHT@
package Socialtext::Resting::RegressionTest;
use strict;
use warnings;
use Socialtext::Resting;

=head1 NAME

Socialtext::Resting::RegressionTest - Rester to regression-test workspace

=cut

our $VERSION = '0.01';

=head1 METHODS

=head2 new

Returns a new rester for the regression-test workspace

=cut

sub new {
    my $class = shift;

    return Socialtext::Resting->new(                                           
        server => 'https://www2.socialtext.net',
        username => 'tester@ken.socialtext.net',
        password => 'wikitest',
        workspace => 'regression-test',
        @_,
    );   
}

1;
