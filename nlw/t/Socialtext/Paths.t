#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::AppConfig;
use Test::Socialtext tests => 6;

BEGIN { use_ok("Socialtext::Paths") }
fixtures(qw( base_layout ));

my $test_dir = Socialtext::AppConfig->test_dir();

STORAGE_DIRECTORY_PATH: {
    my $dir = Socialtext::Paths::storage_directory();
    ok( defined($dir), "Ensure storage_directory() returns something." );
    like($dir, qr{$test_dir/root/storage/?$}, "Ensure the path looks correct.");
    ok((-d $dir), "Ensure storage directory exists: $dir" );
}

STORAGE_DIRECTORY_SUBDIR: {
    my $dir = Socialtext::Paths::storage_directory("cows-love-matthew");
    ok( defined($dir),
        "Ensure storage_directory(cows-love-matthew) returns something." );
    like( $dir, qr{$test_dir/root/storage/cows-love-matthew/?$},
        "Ensure the path looks correct." );
}
