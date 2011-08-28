#!/usr/bin/env perl
# @COPYRIGHT@
package Foo;    # so we can use the Async::Wrapper here in the test
use strict;
use warnings;
use Test::Socialtext tests => 8;
use Moose;
use File::Temp qw(tempfile);
use List::MoreUtils qw(part);
use Socialtext::Async::Wrapper;

fixtures(qw( base_layout ));

sub check_log (;$);

my ($fh,$filename) = tempfile;
my $fileno = $fh->fileno;
ok $fileno, "filehandle has a fileno we can check ($fileno)";
my $inode = `lsof -n -p $$ -a -d $fileno -F i | egrep '^i'`;
chomp $inode;
ok $inode, "got a inode";
print "# parent inode: $inode\n";
Socialtext::Async::Wrapper->RegisterAtFork(sub {
    my $kid_inode = `lsof -n -p $$ -a -d $fileno -F i | egrep '^i'`;
    chomp $kid_inode;
    open STDERR, '>>&', $fh;
    select STDERR; $|=1; select STDOUT;
    print STDERR "# kid inode: $kid_inode\n";
});

worker_function short_time => sub {
    return "yes!";
};

worker_function take_a_long_time => sub {
    sleep 2;
};

worker_wrap wrapper_method => 'Foo::existing_method';
sub wrapper_method {
    call_orig_in_worker(wrapper_method => @_);
}
sub existing_method {
    sleep 2;
}


do_not_log_short_running: {
    call_orig_in_worker(short_time => 'Foo', 7,8,9);
    check_log;
}

log_long_running_function: {
    call_orig_in_worker(take_a_long_time => 'Foo', 1, 2, 3);
    check_log qr/long running worker \\'worker_take_a_long_time\\'/;
}

log_long_running_method: {
    Foo->existing_method(4,5,6);
    check_log qr/long running worker \\'worker_wrapper_method\\'/;
}

sub check_log (;$) {
    my $look_for = shift;
    sleep 1; # allow kid to flush
    seek $fh, 0, 0;
    my @lines = <$fh>;
    truncate $fh, 0;
    my ($info,$warn) = part { /^# / ? 0 : 1 } @lines;

    if ($info && @$info) {
        if ($info->[0] =~ /^# kid inode: (.+)$/) {
            my $kid_inode = $1;
            is $inode, $kid_inode, "parent and kid inode is the same (descriptor wasn't closed)";
        }
    }

    $warn ||= [];
    if (defined $look_for) {
        like $warn->[0], $look_for, 'found our log line';
        is scalar(@$warn), 1, 'only a single line' or diag @$warn;
    }
    else {
        is scalar(@$warn), 0, 'nothing logged' or diag @$warn;
    }
}
