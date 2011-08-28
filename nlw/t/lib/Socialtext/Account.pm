package Socialtext::Account;
# @COPYRIGHT@
use warnings;
use strict;
use base 'Socialtext::MockBase';
use unmocked 'Class::Field', qw/field/;

field 'account_id';
field 'name', '-init' => '"Account ".$self->account_id';
field 'is_system_created' => 1;
field 'skin_name' => 's3';
field 'email_addresses_are_hidden' => 0;
field '_plugin' => {};

my $NextAccountID = 1;
my %Accounts = ();
my %AccountsByName = ();

sub new {
    my ($class, %p) = @_;
    my $acct;
    if ($p{name}) {
        $acct = $AccountsByName{$p{name}};
    }
    elsif ($p{account_id}) {
        $acct = $Accounts{$p{account_id}};
        $p{name} ||= "Account $p{account_id}";
    }
    else {
        return;
    }

    if (!$acct) {
        $acct = $class->create(%p);
    }
    return $acct;
}

sub Resolve {
    my $class = shift;
    my $maybe_account = shift;
    my $account;

    if ( $maybe_account =~ /^\d+$/ ) {
        $account = Socialtext::Account->new(account_id => $maybe_account);
    }

    $account ||= Socialtext::Account->new(name => $maybe_account);
    return $account;
}

sub create {
    my ($class, %p) = @_;
    $p{account_id} ||= $NextAccountID++;
    my $acct = $class->SUPER::new(%p);
    $Accounts{$acct->account_id} = $acct;
    $AccountsByName{$acct->name} = $acct;
}

sub Default    { $_[0]->create(name => 'Default'); }
sub Socialtext { $_[0]->create(name => 'Socialtext'); }
sub Deleted    { $_[0]->create(name => 'Deleted'); }

sub is_plugin_enabled { $_[0]->_plugin->{$_[1]} ? 1 : 0; }
sub enable_plugin { $_[0]->_plugin->{$_[1]} = 1; }
sub disable_plugin { $_[0]->_plugin->{$_[1]} = 0; }

1;
