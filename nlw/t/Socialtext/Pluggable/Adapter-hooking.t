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
use Test::Socialtext tests => 1;
use Test::Differences;

###############################################################################
# Fixtures: db
fixtures(qw( db ));

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

$adapt->plugin_class('a')->register();
$adapt->plugin_class('b')->register();
$adapt->plugin_class('c')->register();
$adapt->register($registry);

my $acct = Socialtext::Account->Default;
$acct->enable_plugin($_) for qw/a b c/;

my @hook_order;
$adapt->hook('monkey');
eq_or_diff \@hook_order, [qw/A C B/], 'Hooks fired in correct order';
exit;

# Plugins for dependency tests
{
    package Socialtext::Pluggable::Plugin::A;
    use strict;
    use warnings;
    use base 'Socialtext::Pluggable::Plugin';
    sub register {
        shift->add_hook('monkey', 'fire_hook', priority => 3);
    }
    sub fire_hook { push @hook_order, 'A' }
}

{
    package Socialtext::Pluggable::Plugin::B;
    use strict;
    use warnings;
    use base 'Socialtext::Pluggable::Plugin';
    sub register {
        shift->add_hook('monkey', 'fire_hook', priority => 80);
    }
    sub fire_hook { push @hook_order, 'B' }
}

{
    package Socialtext::Pluggable::Plugin::C;
    use strict;
    use warnings;
    use base 'Socialtext::Pluggable::Plugin';
    sub register {
        shift->add_hook('monkey', 'fire_hook');
    }
    sub fire_hook { push @hook_order, 'C' }
}
