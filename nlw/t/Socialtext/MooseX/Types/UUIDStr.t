#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 6;
use Test::Fatal;
use Moose::Util::TypeConstraints;
use Socialtext::MooseX::Types::UUIDStr;

my $uuid     = 'dfd6fd31-e518-41ca-ad5a-6e06bc46f1dd';
my $not_uuid = 'this is not a uuid';

###############################################################################
# TEST: Str.UUID
str_uuid: {
    my $type = Moose::Util::TypeConstraints::find_or_parse_type_constraint(
        'Str.UUID'
    );
    ok $type, 'Found Str.UUID type';

    ok $type->check($uuid), '... checks w/UUID';
    ok !$type->check($not_uuid), '... fails check w/non-UUID';
}

###############################################################################
# TEST: Class instantiation
instantiation: {
    package Foo;
    use Moose;
    use Socialtext::MooseX::Types::UUIDStr;
    has 'uuid' => (is => 'rw', isa => 'Str.UUID');

    package main;
    pass 'Instantiation tests';


    is exception { Foo->new(uuid => $uuid) }, undef,
        '... Str.UUID w/UUID value';
    like exception { Foo->new(uuid => $not_uuid) }, qr/invalid UUID/,
        '... Str.UUID w/non-UUID value';
}
