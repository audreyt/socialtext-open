#!/usr/bin/env perl
# @COPYRIGHT@
use warnings;
use strict;

use Test::Socialtext tests => 9;
use Socialtext::SQL qw/get_dbh sql_txn/;
use ok 'Socialtext::UserSet', qw/:const/;
use POSIX ();
use File::Temp qw/tempfile/;
use Fcntl qw/SEEK_SET/;
use Time::HiRes qw/sleep/;

fixtures(qw(clean db destructive));

my $OFFSET = GROUP_OFFSET + 1_000_000;
my $member = Socialtext::Role->new(name => 'member')->role_id;
ok $member;
my $admin  = Socialtext::Role->new(name => 'admin')->role_id;
ok $admin;

select STDERR; $|=1;
select STDOUT; $|=1;

my $state = tempfile;

Socialtext::SQL::disconnect_dbh();

my $pid_one = fork();
die "can't fork: $!" unless defined $pid_one;
kid(10000) unless $pid_one;
pass "forked $pid_one";

my $pid_two = fork();
die "can't fork: $!" unless defined $pid_one;
kid(20000) unless $pid_two;
pass "forked $pid_two";

Socialtext::SQL::disconnect_dbh();
parent();
exit 0;

sub kid {
    my $n = shift;
    diag "$$ BEGIN";
    my $dbh = get_dbh();
    my $uset = Socialtext::UserSet->new;
    eval {
        for my $set ($n .. $n+10) {
            sql_txn {
                $uset->add_role($set => $OFFSET, $member);
                $uset->update_role($set => $OFFSET, $admin);
                diag "$$ OK $set";
            };
        }
    };
    if ($@) {
        diag $@;
        print $state "$$ FAILED\n";
    }
    else {
        print $state "$$ OK\n";
    }
    diag "$$ DONE";
    $state->close();
    POSIX::_exit(0);
}

sub parent {
    my $pid = waitpid -1,0;
    pass "got $pid";
    $pid = ($pid == $pid_one) ? $pid_two : $pid_one; # wait for the other one
    $pid = waitpid $pid,0;
    pass "got $pid";

    seek $state,SEEK_SET,0;
    while (my $line = <$state>) {
        chomp $line;
        like $line, qr/\d+ OK/, 'kid was ok';
    }
}
