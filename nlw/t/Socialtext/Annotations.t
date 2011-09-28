#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 9;
use ok 'Socialtext::Annotations';

merge: {
    my $a1 = [
        { n1 => {k1 => 'v1', k2 => 'kv2'}},
        { n2 => {k2 => 'v2'}},
    ];
    my $a2 = [
        { n1 => {k1 => 'v3'}},
    ];

    Socialtext::Annotations::MergeAnnotations($a1, $a2);
    is $a1->[0]->{n1}{k1}, 'v3', 'key updated';
    is $a1->[0]->{n1}{k2}, 'kv2', 'key in same anno not updated';
    is $a1->[1]->{n2}{k2}, 'v2', 'orig key not updated';
}

remove_null: {
    my $a1 = [
        { n1 => {k1 => 'v1', k2 => undef}},
        { n2 => {k2 => 'v2'}},
    ];
    Socialtext::Annotations::RemoveNullAnnotations($a1);
    ok exists $a1->[0]->{n1}{k1}, 'k1 in n1 exists';
    ok exists $a1->[1]->{n2}{k2}, 'k2 in n2 exists';
    ok !exists $a1->[0]->{n1}{k2}, 'k2 in n1 does not exist';

    $a1 = [
        { n1 => {k1 => undef, k2 => undef}},
        { n2 => {k2 => 'v2'}},
    ];
    Socialtext::Annotations::RemoveNullAnnotations($a1);
    ok !exists $a1->[0]->{n1}, 'namespace n1 does not exist';
    ok exists $a1->[0]->{n2}, 'namespace n2 exists';
}

