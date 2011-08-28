#!perl -w
# @COPYRIGHT@

use strict;
use warnings;

use Test::More tests => 7;

BEGIN {
    use_ok( 'Socialtext::Base' );
}

my $base = Socialtext::Base->new;

ASSERTIONS_TRUE: {
    my $had_no_blow_up = 0;
    eval {
        $base->assert( 0 == 0 );
        $had_no_blow_up = 1;
    };
    ok( $had_no_blow_up, 'True assertion does not blow up.' );
    is( $@, '', 'True assertion does not set $@.' );
}

ASSERTIONS_FALSE: {
    my $had_blow_up = 1;
    eval {
        $base->assert( 0 == 1 );
        $had_blow_up = 0;
    };
    ok( $had_blow_up, 'False assertion blows up.' );
    isnt( $@, '', 'False assertion sets $@.' );
}

TEST_DUMPER_TO_FILE: {
    my $path = "/tmp/dumper-test-$$";
    my %data = (
        foo  => 'bar',
        baz  => [ 0, 1, 2, 3 ],
        quux => {
            one => 1,
            two => 2
        }
    );
    unlink $path;
    -e $path and die;

    $base->dumper_to_file( $path, \%data );

    ok( -e $path, 'dumper_to_file() creates the file.' );

    my $dumped_data = do $path;
    unlink $path or die "$path: $!";

    is_deeply(
        $dumped_data,
        \%data,
        'dumper_to_file() dumped data is correct.'
    );
}
