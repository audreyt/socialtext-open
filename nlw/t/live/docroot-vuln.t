#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::HTTP::Socialtext '-syntax', tests => 3;
use Test::More;
use Test::Live fixtures => ['admin','foobar'];
use File::Basename qw(basename);

my $BASE = Test::HTTP::Socialtext->url('/');

test_http "Trying to download sekret file" {
    >> GET ${BASE}plugin/foobar/attachments/formattingtest/20070117192201-23-20625/thing.png

    << 404
}

# Load logo
use Test::Socialtext::Environment;
my $hub = Test::Socialtext::Environment->instance()
    ->hub_for_workspace('admin');
my $admin = $hub->current_workspace();
my $image = 't/attachments/socialtext-logo-30.gif';
$admin->set_logo_from_file( filename => $image );
ok( ( -f $admin->logo_filename ), "logo exists" );

my $logo_path = "logos/admin/" . basename( $admin->logo_filename );
test_http "Trying to download logo file" {
    >> GET ${BASE}${logo_path}

    << 200
}
