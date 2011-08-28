#!perl
use warnings;
use strict;
use Test::More tests => 5;

use ok 'Socialtext::UUID', qw/new_uuid/;

my $uuid = new_uuid();
# e.g. dfd6fd31-e518-41ca-ad5a-6e06bc46f1dd
like $uuid, qr/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/,
    "correct UUID format";

my $uuid2 = new_uuid();
isnt $uuid, $uuid2, "new uuid gets generated each call (1-2)";
my $uuid3 = new_uuid();
isnt $uuid2, $uuid3, "new uuid gets generated each call (2-3)";
isnt $uuid, $uuid3, "new uuid gets generated each call (1-3)";
