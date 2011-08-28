package Socialtext::WikiFixture::RestPerf;
# @COPYRIGHT@
use Moose;
use Time::HiRes qw/gettimeofday tv_interval/;
use namespace::clean -except => 'meta';

extends 'Socialtext::WikiFixture::SocialRest';

=head1 NAME

Socialtext::WikiFixture::RestPerf - Perf testing the rest api using wikitests

=cut

our $VERSION = '0.01';

=head1 DESCRIPTION

Makes the Rest tools perf-testable

=cut

around 'get' => sub {
    my $orig = shift;

    my $start = [gettimeofday];
    $orig->(@_);
    my $elapsed = tv_interval($start);
    print "GET $_[1] took $elapsed\n";
};

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;
