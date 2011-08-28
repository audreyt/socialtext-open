#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use Socialtext::SQL;
use Socialtext::Account;
use Socialtext::User;
use mocked 'Socialtext::Registry';
use mocked 'Socialtext::Hub', gtv => 'empty';
use Socialtext::Pluggable::Adapter;
use Test::Socialtext tests => 46;

###############################################################################
# Fixtures: db
fixtures(qw( db destructive ));

ok $INC{'Socialtext/Pluggable/Plugin/TestPlugin.pm'}, "Test plugin loaded";

my $adapt = Socialtext::Pluggable::Adapter->new;
my $registry = Socialtext::Registry->new;

# use a Mocked hub so that hooks can find their way back to the Adapter
my $hub = Socialtext::Hub->new;
$hub->{pluggable} = $adapt;
$adapt->{hub} = $hub;
$registry->hub($hub);
my $email = "bob.".time.'@ken.socialtext.net';
$hub->{current_user} = Socialtext::User->create(
    email_address => $email, username => $email
);

Socialtext::Account->Default->enable_plugin('testplugin');

my $template_vars;

# Setup hooks before register
Socialtext::Pluggable::Plugin::TestPlugin->test_hooks(
    'test.name', sub { $_[0]->name },
    'action.test_action' , sub {
        my $self = shift;
        $template_vars = $self->template_vars;
        return 'action contents';
    },
    'wafl.test_wafl', sub { 'wafl contents' },
);

$adapt->register($registry);

ok scalar(grep { /Pluggable::Plugin::TestPlugin/ } $adapt->plugins),
   'Mocked plugin is loaded';

ok scalar(grep { $_ eq 'testplugin' } $adapt->plugin_list),
   'Mocked plugin shows up in plugin_list';

ok $adapt->plugin_exists('testplugin'), 'plugin_exists returns true when the plugin exists';
ok !$adapt->plugin_exists('something'), 'plugin_exists returns false when the plugin does not exist';

# Test that name is properly based off the class name
is $adapt->hook('test.name'), 'testplugin', 'TestPlugin name is "testplugin"';

is $registry->call('wafl', 'test_wafl'), 'wafl contents',
   "wafl.test_wafl can be called through registry";

is $registry->call('action', 'test_action'), 'action contents',
   "action hooks autovivify and can be called through registry";
ok $template_vars, 'was able to get template vars';
is $template_vars->{action_plugin}, 'testplugin', 'action_plugin was provided to templates';

# Test plugin dependencies and optional_dependencies
my $acct = Socialtext::Account->Default;
my $wksp = Socialtext::Workspace->create(
    name       => "test-$^T",
    title      => "Test $^T",
    account_id => $acct->account_id,
    skip_default_pages => 1,
);
my %things = (account => $acct, workspace => $wksp);

sub set_plugin_scope {
    my $scope = shift || 'always';
    for my $p (qw(A B C)) {
        my $pclass = "Socialtext::Pluggable::Plugin::$p";
        $pclass->scope($scope);
    }
}

for my $t (keys %things) {
    warn "Setting plugin scope for $t";
    set_plugin_scope($t);

    warn "Disabling plugins a, b and c for $t";
    $things{$t}->disable_plugin($_) for qw(a b c);
    warn "Enabling plugin a for $t";
    $things{$t}->enable_plugin('a');
    warn "done";
    ok $things{$t}->is_plugin_enabled('a'), "enabling a enables a";
    ok $things{$t}->is_plugin_enabled('b'), "enabling a enables b";
    ok $things{$t}->is_plugin_enabled('c'), "enabling a enables b -> c";

    $things{$t}->disable_plugin($_) for qw(a b c);
    $things{$t}->enable_plugin('b');
    ok $things{$t}->is_plugin_enabled('b'), "enabling b enables b";
    ok $things{$t}->is_plugin_enabled('a'), "enabling b enables a";
    ok $things{$t}->is_plugin_enabled('c'), "enabling b enables c";

    $things{$t}->disable_plugin($_) for qw(a b c);
    $things{$t}->enable_plugin('c');
    ok $things{$t}->is_plugin_enabled('c'), "enabling c enables c";
    ok $things{$t}->is_plugin_enabled('b'), "enabling c enables b";
    ok $things{$t}->is_plugin_enabled('a'), "enabling c enables b -> a";

    $things{$t}->enable_plugin($_) for qw(a b c);
    $things{$t}->disable_plugin('a');
    ok !$things{$t}->is_plugin_enabled('a'), "disabling a disables a";
    ok !$things{$t}->is_plugin_enabled('b'), "disabling a disables b";
    ok !$things{$t}->is_plugin_enabled('c'), "disabling a disables b -> c";

    $things{$t}->enable_plugin($_) for qw(a b c);
    $things{$t}->disable_plugin('b');
    ok !$things{$t}->is_plugin_enabled('b'), "disabling b disables b";
    ok $things{$t}->is_plugin_enabled('a'), "disabling b doesn't disable a";
    ok !$things{$t}->is_plugin_enabled('c'), "disabling b disables c";

    $things{$t}->enable_plugin($_) for qw(a b c);
    $things{$t}->disable_plugin('c');
    ok !$things{$t}->is_plugin_enabled('c'), "disabling c disables c";
    ok !$things{$t}->is_plugin_enabled('b'), "disabling c disables b";
    ok $things{$t}->is_plugin_enabled('a'), "disabling c doesn't disable a";
}

# Plugins for dependency tests
{
    package Socialtext::Pluggable::Plugin::A; # like people
    use strict;
    use warnings;
    use base 'Socialtext::Pluggable::Plugin';
    my $SCOPE;
    sub scope { $SCOPE = $_[1] if @_ > 1; return $SCOPE || 'always' };
    sub register {}
    sub enables { qw(b) }
}

{
    package Socialtext::Pluggable::Plugin::B; # like signals
    use strict;
    use warnings;
    use base 'Socialtext::Pluggable::Plugin';
    my $SCOPE;
    sub scope { $SCOPE = $_[1] if @_ > 1; return $SCOPE || 'always' };
    sub register {}
    sub dependencies { qw(a c) }
}

{
    package Socialtext::Pluggable::Plugin::C; # just for the circular dep
    use strict;
    use warnings;
    use base 'Socialtext::Pluggable::Plugin';
    my $SCOPE;
    sub scope { $SCOPE = $_[1] if @_ > 1; return $SCOPE || 'always' };
    sub register {}
    sub dependencies { qw(b) } # circular dependency
}
