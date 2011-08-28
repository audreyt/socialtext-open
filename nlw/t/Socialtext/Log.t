#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 6;

use Encode;
use utf8;

BEGIN {
    use_ok( "Socialtext::Log" );
}

fixtures( 'base_layout' );

# These tests are meant to validate that if we log utf8 strings we don't 
# get warnings or errors logging the strings.
# It appears that Sys::Syslog (called by Log::Dispatch::Syslog) dies if 
# passed a utf8 string.
#
eval { Socialtext::Log->new()->error("begin logging test") };
ok( ! $@, "failed begin logging test: $@" ) ;

my $original_string = "yö";
eval { Socialtext::Log->new()->error( $original_string ) };
ok( ! $@, "failed yo test: $@" );

my $utf8_source = "Groß Blah Blah";

eval {Socialtext::Log->new()->error($utf8_source) };
ok( ! $@,  "failed utf8_source test: $@" );

my $utf8_string = Encode::decode_utf8($utf8_source);
eval { Socialtext::Log->new()->error($utf8_string) };
ok( ! $@, "failed utf8_string test: $@" );

eval { Socialtext::Log->new()->error("end logging test") };
ok( ! $@, "failed end logging test: $@" );
