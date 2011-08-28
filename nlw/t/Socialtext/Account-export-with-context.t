#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;

use File::Temp qw/tempdir/;
use Socialtext::Cache;
use Test::Socialtext;
use Test::Socialtext::AccountContext;
use Test::Socialtext::CLIUtils qw/expect_success/;
fixtures(qw/clean db destructive/);

my $acct_name = Test::Socialtext::create_unique_id .'-acct';
my $context   = Test::Socialtext::AccountContext->new(export_name=>$acct_name);

plan tests => $context->test_plan + 3;

$context->prepare();

# export the account
my $account  = Socialtext::Account->new(name=>$acct_name);
my $adapter  = Socialtext::Pluggable::Adapter->new();
my $hub      = $adapter->make_hub( Socialtext::User->SystemUser );
my $tempdir  = tempdir();
my $filename = $account->export(dir => $tempdir, hub => $hub);
ok -f $filename, "$acct_name - exported ok";

# rebuild our env; we're only supporting imports onto a clean appliance for
# now, so let's make our env as clean as it can be.
Socialtext::Cache->clear();
system('dev-bin/make-test-fixture --fixture clean --fixture db');

# import
expect_success(
    sub {
        Socialtext::CLI->new(
            argv => [ '--dir', $tempdir ]
        )->import_account;
    },
    qr/\Q$acct_name\E account imported./,
    'account imported',
);

$context->clear_shares();
$context->validate();

exit;
