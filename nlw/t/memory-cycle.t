#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext;

BEGIN {
    unless ( eval { require Test::Memory::Cycle;
                    Test::Memory::Cycle->import(); 1 } ) {
        plan skip_all => 'These tests require Test::Memory::Cycle to run.';
    }
}

fixtures( 'admin' );

plan tests => 3;

my $hub = new_hub('admin');

{
    $hub->pages->new_from_name('FormattingTest')->to_html;
    $hub->current_user(undef);
    $hub->current_workspace(undef);

    memory_cycle_ok( $hub, 'check for cycles in Socialtext::Hub object' );
    memory_cycle_ok( $hub->main, 'check for cycles in NLW object' );
    memory_cycle_ok( $hub->viewer,
        'check for cycles in Socialtext::Formatter::Viewer object' );
}
