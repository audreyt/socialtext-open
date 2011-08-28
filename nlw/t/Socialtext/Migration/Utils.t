#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::More tests => 5;
use mocked 'Socialtext::Schema';

BEGIN {
    use_ok 'Socialtext::Migration::Utils', 'ensure_socialtext_schema';
}

Already_at_right_version: {
    local $Socialtext::Schema::CURRENT_VERSION = 3;
    ensure_socialtext_schema(1);
    is $Socialtext::Schema::CURRENT_VERSION, 3;
    ensure_socialtext_schema(2);
    is $Socialtext::Schema::CURRENT_VERSION, 3;
    ensure_socialtext_schema(3);
    is $Socialtext::Schema::CURRENT_VERSION, 3;
}

Sync: {
    local $Socialtext::Schema::CURRENT_VERSION = 3;
    ensure_socialtext_schema(4);
    is $Socialtext::Schema::CURRENT_VERSION, 4;
}
