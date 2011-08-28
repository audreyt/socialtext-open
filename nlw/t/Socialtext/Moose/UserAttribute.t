#!perl
# @COPYRIGHT@
use warnings;
use strict;

use Test::Socialtext tests => 23;
use Test::Socialtext::Fatal;
fixtures('db');

my $user = create_test_user();
my $user_id = $user->user_id;

my $non_user_id = $user_id+1;

{
    package MyClass;
    use Moose;
    use MooseX::StrictConstructor;
    use Socialtext::Moose::UserAttribute;
    has_user 'someuser' => (is => 'rw');
}

test_rw_mode: {
    my $c;
    ok !exception {
        $c = MyClass->new(someuser_id => $user_id);
    }, 'constructed';
    ok $c->can('someuser'), 'has someuser accessor';
    ok $c->can('clear_someuser'), 'has a clearer';
    ok $c->can('has_someuser'), 'has a predicate';
    ok $c->can('_build_someuser'), 'builder was injected';
    ok $c->can('someuser_id'), 'has a someuser_id accessor';

    my $someuser = $c->someuser;
    is $someuser->user_id, $user_id, "auto-vivified the correct user";

    $someuser->{_sekret} = 1;
    my $c2 = MyClass->new(someuser => $someuser, someuser_id => 1);
    is $c2->someuser->{_sekret}, 1, "object is sticky";
    is $c2->someuser_id, $user_id, "id was derived from the object";
    isnt $c2->someuser_id, 1, "id was derived from the object";
}

{
    package MyClass2;
    use Moose;
    use MooseX::StrictConstructor;
    use Socialtext::Moose::UserAttribute;
    has_user 'xyzzy' => (is => 'ro');
}

test_ro_mode: {
    my $c;
    ok !exception {
        $c = MyClass2->new(xyzzy_id => $user_id);
    }, 'constructed with ID';
    is $c->xyzzy->user_id, $user_id, 'auto-built user';

    ok !exception {
        $c = MyClass2->new(xyzzy => $user);
    }, 'constructed with object';
    is $c->xyzzy_id, $user_id, 'auto-built user_id';
}

{
    package MyClass3;
    use Moose;
    use MooseX::StrictConstructor;
    use Socialtext::Moose::UserAttribute;
    has_user 'foo' => (is => 'rw', required => 1);
}

required_mode: {
    my $c;
    ok !exception {
        $c = MyClass3->new(foo => $user);
    }, 'constructed with object';
    is $c->foo_id, $user_id, 'constructed the right user_id';

    ok !exception {
        $c = MyClass3->new(foo_id => $user_id);
    }, 'constructed with object';
    is $c->foo->user_id, $user_id, 'auto-built the right user';

    ok exception {
        $c = MyClass3->new();
    }, 'failed construction without object or id';
}

{
    package MyClass4;
    use Moose;
    use MooseX::StrictConstructor;
    use Socialtext::Moose::UserAttribute;
    has_user 'bar' => (is => 'rw', st_maybe => 1);
}

maybe_mode: {
    my $c;
    ok !exception {
        $c = MyClass4->new(bar_id => 0);
    }, 'non-existant user constructs OK';
    ok !$c->has_bar, "bar slot not here yet";
    is $c->bar, undef, 'lazy-build produces no user';
    ok $c->has_bar, "bar slot exists";
}
