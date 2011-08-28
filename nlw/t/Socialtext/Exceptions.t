#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::More tests => 10;

sub subs_exist {
    check_subs(1, @_);
}

sub subs_dont_exist {
    check_subs(0, @_);
}

sub check_subs {
    my $should_exist = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 2;
    my $caller = caller(1);
    for my $sub (@_) {
        no strict 'refs';
        my $exists = exists ${$caller . '::'}{$sub};
        my $not = $should_exist ? '' : ' not';
        ok $exists == $should_exist, "$sub should$not be defined";
        if ($should_exist) {
            my $sub = \&{"${caller}::$sub"};
            eval { $sub->('my error message') };
            like $@, qr/my error message/, '$@ matches our error message';
        }
    }
}

{
    package Foo;
    use Socialtext::Exceptions ();
    ::subs_dont_exist(qw( auth_error config_error param_error virtual_method_error ));
}

{
    package Bar;
    use Socialtext::Exceptions qw( auth_error config_error );
    ::subs_exist(qw( auth_error config_error ) );
    ::subs_dont_exist(qw( param_error virtual_method_error ) );
}
