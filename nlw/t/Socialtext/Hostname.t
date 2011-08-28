#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::More;

use Socialtext::Hostname ();
use Sys::Hostname ();

# The only way to test if this thing is working is when it's run on a
# system where we know what results to expect. On a system that's
# misconfigured we can easily get entirely bogus results.
my %TestHosts = (
    'talc.socialtext.net' => {
        hostname => 'talc',
        domain   => 'socialtext.net',
        fqdn     => 'talc.socialtext.net',
    },
    'topaz.socialtext.net' => {
        hostname => 'topaz',
        domain   => 'socialtext.net',
        fqdn     => 'topaz.socialtext.net',
    },
    'galena.socialtext.net' => {
        hostname => 'galena',
        domain   => 'socialtext.net',
        fqdn     => 'galena.socialtext.net',
    },
    'borax.socialtext.net' => {
        hostname => 'borax',
        domain   => 'socialtext.net',
        fqdn     => 'borax.socialtext.net',
    },
    'lucite.socialtext.net' => {
        hostname => 'lucite',
        domain   => 'socialtext.net',
        fqdn     => 'lucite.socialtext.net',
    },
);

my %DevHosts;
for my $int ( 1..8 ) {
    $DevHosts{"dev$int.socialtext.net"} =  { 
         hostname => "dev$int", 
         domain => 'socialtext.net', 
         fqdn => "dev$int"
    };
}

my %KnownHosts = ( %TestHosts, %DevHosts );

my $hn = Sys::Hostname::hostname();
my $expect = $KnownHosts{$hn};
if ($expect) {
    plan tests => 3;
}
else {
    plan skip_all => "Cannot run these tests on a host we don't know about ($hn)";
}

is( Socialtext::Hostname::hostname(), $expect->{hostname},
    'check hostname()' );
is( Socialtext::Hostname::domain(), $expect->{domain},
    'check domain()' );
is( Socialtext::Hostname::fqdn(), $expect->{fqdn},
    'check fqdn()' );
