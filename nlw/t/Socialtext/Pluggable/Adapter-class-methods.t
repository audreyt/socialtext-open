#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::More tests => 21;
use Data::Dumper;
#use mocked 'Module::Pluggable';
use mocked 'Socialtext::Hub';
use mocked 'Socialtext::Registry';

{
    no warnings 'redefine', 'once';
    *Socialtext::Hub::new = sub { die "new hub" };
}

use_ok 'Socialtext::Pluggable::Plugin';
use_ok 'Socialtext::Pluggable::Adapter';

sub protect_sanity {
    my $method = shift;
    my @pluggables = grep m#Socialtext/Pluggable/Plugin/#, keys(%INC);
    my @plugin_classes = map { s/\.pm$//; s#/#::#g; $_ } @pluggables;
    foreach my $plugin (@plugin_classes) {
        no strict 'refs';
        no warnings 'redefine';
        *{"${plugin}::$method"} = sub {};
    }
}

# Methods that get called on specific plugins:

foreach my $method (qw(EnablePlugin
                       DisablePlugin))
{
    local *Socialtext::Pluggable::Adapter::AUTOLOAD;
    protect_sanity($method);

    ok(Socialtext::Pluggable::Adapter->can($method),
        "adapter should implement $method");
    ok(!Socialtext::Pluggable::Plugin->can($method),
        "base plugin should not implement $method");

    my ($mock_calls, $test_calls) = (0,0);
    {
        no strict 'refs';
        no warnings 'redefine';
        *{"Socialtext::Pluggable::Plugin::TestPlugin::$method"} = 
            sub { my $class=shift; $mock_calls += @_ };
        *{"Socialtext::Pluggable::Plugin::Test::$method"} = 
            sub { my $class=shift; $test_calls += @_ };
    }

    my $some_arg = { foo => 'bar' };

    Socialtext::Pluggable::Adapter->$method('testplugin' => $some_arg);
    is $mock_calls, 1, "testplugin plugin called for the first time";
    is $test_calls, 0, "test plugin got skipped";
    Socialtext::Pluggable::Adapter->$method('test' => $some_arg);
    is $mock_calls, 1, "testplugin plugin didn't get called twice";
    is $test_calls, 1, "test plugin called for the first time";
}

# methods that get called on all plugins:

foreach my $method (qw(EnsureRequiredDataIsPresent))
{
    local *Socialtext::Pluggable::Adapter::AUTOLOAD;
    protect_sanity($method);

    ok(Socialtext::Pluggable::Adapter->can($method),
        "adapter should implement $method");
    ok(!Socialtext::Pluggable::Plugin->can($method),
        "base plugin should not implement $method");

    my $some_arg = { foo => 'bar' };

    my ($mock_calls, $test_calls) = (0,0);
    {
        no strict 'refs';
        no warnings 'redefine';
        *{"Socialtext::Pluggable::Plugin::TestPlugin::$method"} = 
            sub { my $class=shift; $mock_calls += @_ };
        *{"Socialtext::Pluggable::Plugin::Test::$method"} = 
            sub { my $class=shift; $test_calls += @_ };
    }

    Socialtext::Pluggable::Adapter->$method($some_arg);
    is $mock_calls, 1, 'testplugin plugin got called for the first time';
    is $test_calls, 1, 'test plugin got called for the first time';

    Socialtext::Pluggable::Adapter->$method($some_arg, $some_arg);
    is $mock_calls, 3, 'testplugin plugin got called for the first time';
    is $test_calls, 3, 'test plugin got called for the first time';
}

ok 1, 'complete';
