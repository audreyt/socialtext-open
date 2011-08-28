#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 3;
use Test::Socialtext::CLIUtils qw/expect_failure expect_success/;

fixtures(qw/db/);

my $export_dir = 't/test-data/bad-yaml-account.id-X.export';
ok -e $export_dir, 'found export dir';

expect_failure(
    sub {
        Socialtext::CLI->new(argv => ['--dir', $export_dir])
            ->import_account();
    },
    qr/\*{78}/,
    'account fails to import in spectacular fashion'
);
