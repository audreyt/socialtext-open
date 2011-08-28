#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::More;

BEGIN {
    unless (eval q{require Judy::1;}) {
        plan skip_all =>
            "Judy and Judy::1 are required for Socialtext::IntSet";
    }
    else {
        plan tests => 91;
    }
}

use Test::Differences qw/eq_or_diff/;
use ok 'Socialtext::IntSet';

pack_sanity: {
    eq_or_diff [unpack('w*',pack('w*',5))], [5], 'pack test';
    eq_or_diff [unpack('w*',pack('w*',1,128,1024))], [1,128,1024], 'pack test2';
}

set_sanity: {
    my $x = 0;
    my $was_set = !Judy::1::Set($x,42);
    ok !$was_set, "bit wasn't in empty set";
    $was_set = !Judy::1::Set($x,42);
    ok $was_set, "bit was in the set already";
    $was_set = Judy::1::Unset($x,42);
    ok $was_set, "bit was cleared";
    $was_set = Judy::1::Unset($x,42);
    ok !$was_set, "bit was already cleared";
    Judy::1::Free($x);
}

basic_construction: {
    my $ints = Socialtext::IntSet->FromArray(1,2,3);
    ok $ints;

    ok $ints->get(2);
    ok !$ints->get(4);

    ok !$ints->set(4), '4 wasn\'t set';
    ok $ints->get(4), '4 is set now';

    my $raw = $ints->array; # lazy-build the new raw list
    eq_or_diff $raw, [1..4], "built array correctly";

    ok $ints->get(3), '3 is there';
    $ints->unset(3);
    ok !$ints->get(3), '3 now gone';
    ok $ints->get(4), '4 is still set';
    eq_or_diff $ints->array, [1,2,4], "3 gone in array";

    is $ints->nth(0), undef, '0th bit is missing';
    is $ints->nth(1), 1, '1st bit is present';
    is $ints->nth(2), 2, '2nd bit is present';
    is $ints->nth(3), 4, '3rd bit is present';
    is $ints->nth(4), undef, '4th bit is missing';
}

serialize: {
    my $ints = Socialtext::IntSet->FromArray([5,8,1024]);
    ok $ints;

    my $ser1 = $ints->serial;
    ok ref($ser1);
    is length($$ser1), 1+1+2, "expected BER length";
    eq_or_diff [unpack 'w*',$$ser1], [5,3,1016],
        'conversion from raw to serial';

    my $ints2 = Socialtext::IntSet->FromSerial($ser1);
    ok $ints2;
    eq_or_diff $ints->array, [5,8,1024], "serialize roundtrip ok";

    $ints = Socialtext::IntSet->FromArray([0,2,3]);
    my $ser2 = $ints->serial;
    ok ref($ser2);
    is length($$ser2), 1+1+1, "expected BER length";
    eq_or_diff [unpack 'w*',$$ser2], [0,2,1],
        'conversion from raw to serial';

    $ints2 = Socialtext::IntSet->FromSerial($ser2);
    ok $ints2;
    eq_or_diff $ints->array, [0,2,3], "serialize roundtrip ok";
}

sub run_generator {
    my $gen = shift;
    my @generated;
    while (defined(my $n = $gen->())) {
        push @generated, $n;
    }
    return \@generated;
}

generator: {
    my $ints = Socialtext::IntSet->FromArray([7,9,11]);
    ok $ints;
    my @generated;
    my $gen = $ints->generator;
    ok ref($gen) eq 'CODE', "got a code-ref";
    eq_or_diff run_generator($gen), [7,9,11], "generator worked";

    @generated = ();
    my $gen2 = $ints->generator;
    ok ref($gen2) eq 'CODE', "got a code-ref";
    eq_or_diff run_generator($gen2), [7,9,11], "generator worked again";
}

generator_has_weak_ref: {
    my $ints = Socialtext::IntSet->FromArray([1,2..99,100]);
    ok $ints;
    is $ints->count, 100;
    my $gen = $ints->generator;
    ok ref($gen) eq 'CODE', "got a code-ref";
    is $gen->(), 1, "got first number";
    undef $ints;
    is $gen->(), undef, "but not second; reference is gone";
}

empty: {
    my $ints = Socialtext::IntSet->new;
    ok $ints;
    is $ints->count, 0;

    my $ser = $ints->serial;
    is length($$ser), 0, "empty serialization";

    my $arr = $ints->array;
    eq_or_diff $arr, [], "empty array";

    my $gen = $ints->generator;
    ok ref($gen) eq 'CODE', "got a code-ref";
    eq_or_diff run_generator($gen), [], "empty generator worked";

    # this was causing a 'Modification of readonly variable' warning:
    $ints->set($_) for (1..100);
    ok $ints->get(1);

    $gen = $ints->generator;
    ok ref($gen) eq 'CODE', "got a code-ref";
    eq_or_diff run_generator($gen), [1..100], "empty generator worked";
}

destroy: {
    my $ints = Socialtext::IntSet->FromArray([1,2,3]);
    ok $ints;
    my $j1 = $ints->judy1;
    ok $j1;
    ok ref($j1) && $$j1, "Judy::1 is instantiated.";
    undef $ints;
    ok $j1;
    ok $$j1, "Judy::1 not freed since we kept a ref";
}

basic_set_ops: {
    my $ints = Socialtext::IntSet->FromArray([1,2,7,6,3]);
    ok $ints;
    my $ints2 = Socialtext::IntSet->FromArray([4,5,3,7]);
    ok $ints2;

    my $ints3 = $ints->intersection($ints2);
    eq_or_diff $ints3->array, [3,7], "got intersection";
    $ints3 = $ints2->intersection($ints);
    eq_or_diff $ints3->array, [3,7], "got intersection (commutative)";

    my $ints4 = $ints->union($ints2);
    eq_or_diff $ints4->array, [1..7], "got union";
    $ints4 = $ints2->union($ints);
    eq_or_diff $ints4->array, [1..7], "got union (commutative)";

    my $isect = $ints->common($ints2);
    is $isect, 3, 'got lowest-numbered common int';
    $isect = $ints2->common($ints);
    is $isect, 3, 'got lowest-numbered common int (commutative)';
    ok !$ints2->disjoint($ints), "sets aren't disjoint";

    my $ints5 = $ints->subtraction($ints2);
    eq_or_diff $ints5->array, [1,2,6], "got difference";
    my $ints6 = $ints2->subtraction($ints);
    eq_or_diff $ints6->array, [4,5], "got difference (non-commutative)";
}

containership_set_ops: {
    my $ints = Socialtext::IntSet->FromArray([8,27,1023,3242]);
    ok $ints;
    my $ints2 = Socialtext::IntSet->FromArray([27,3242]);
    ok $ints2;
    my $ints3 = $ints->copy;

    ok $ints2->is_subset_of($ints), "subset";
    ok !$ints->is_subset_of($ints2), "subset (non-commutative)";

    ok $ints->is_subset_of($ints3), 'equal set is subset';
    ok !$ints->is_strict_subset_of($ints3), "equal set isn't a strict subset";
    ok $ints2->is_strict_subset_of($ints3), "unequal is a strict subset";

    ok $ints3->equals($ints), "identical sets are equal";
    ok !$ints2->equals($ints), "unequal sets are not equal";

    my $empty1 = Socialtext::IntSet->new;
    my $empty2 = Socialtext::IntSet->new;
    ok $empty1->equals($empty2), "empty set is equal";
    ok !$empty1->is_strict_subset_of($empty2), "empty set isn't strict subset";
}

zero_hero: {
    my $z1 = Socialtext::IntSet->FromArray(0);
    my $z2 = Socialtext::IntSet->FromArray(42,0);

    is $z1->count, 1, 'set with zero has size';
    is $z2->count, 2, 'set with zero and another number has size';

    my $common = $z1->common($z2);
    ok $common eq "0E0", "common returns zero but true";

    my $intersect = $z1->intersection($z2);
    eq_or_diff $intersect->array, [0], "intersection with zero works";
    ok $intersect->equals($z1), "equality with zero works";
    ok !$intersect->equals($z2), "inequality with zero works";

    my $union = $z1->union($z2);
    ok $union->equals($z2), "equality with zero works";
    ok !$union->equals($z1), "inequality with zero works";

    my $diff = $z2->subtraction($z1);
    eq_or_diff $diff->array, [42], "set subtraction works";

    my $gen = $z2->generator;
    ok $gen->() eq "0E0", "generator gives zero-but-true";
    ok $gen->() == 42, "... and a second number";
}

pass 'done';
