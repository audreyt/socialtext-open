#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::Socialtext tests => 4;
use POSIX;
use Test::Socialtext::Async;

POSIX::setsid;

fixtures(qw( base_config serial ));

ok -x 'bin/st-daemon-monitor', "it's executable";

our $log_dir = Socialtext::Paths->log_directory();

do { open my $fh, '>', "$log_dir/nlw.log" };
my $core = $ENV{USER} . '_testing' . ($ENV{HARNESS_JOB_NUMBER} ? "_$ENV{HARNESS_JOB_NUMBER}" : '');
diag "CORE: $core";
my $rc = system("bin/st-daemon-monitor --solr $core");
ok $rc==0, 'Ran OK';

sleep 1; # log flush
my $logged = do { local (@ARGV,$/) = ("$log_dir/nlw.log"); <> };
ok(!$logged, "nothing got logged") or diag $logged;

pass "all done";
