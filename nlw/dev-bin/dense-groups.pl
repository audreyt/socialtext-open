#!/usr/bin/env perl
$|=1;

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Socialtext::Account;
use Socialtext::Group;
use Socialtext::Role;
use Socialtext::User;
use Socialtext::SQL qw/sql_txn get_dbh/;

my $NUM_USERS  = shift || 50;
my $NUM_GROUPS = shift || 500;

my $now     = time;
my $account = Socialtext::Account->Default();
my $creator = Socialtext::User->SystemUser();
my $member_id = Socialtext::Role->Member()->role_id;

print "Creating $NUM_USERS Users, first user is mob-user-$now-1\@ken.socialtext.net ...\n";
my @user_ids;
foreach my $num (1 .. $NUM_USERS) {
    my $email = "mob-user-$now-$num\@ken.socialtext.net";
    my $user  = Socialtext::User->create(
        username      => $email,
        email_address => $email,
    );
    die "Can't create User $num\n" unless $user;
    push @user_ids, $user->user_id;
    print "u";
}
print "\n";

print "Creating $NUM_GROUPS Groups (each one containing *ALL* Users)...\n";
foreach my $num (1 .. $NUM_GROUPS) {
    my $group = Socialtext::Group->Create( {
        driver_group_name  => "mob-group-$now-$num",
        primary_account_id => $account->account_id,
        created_by_user_id => $creator->user_id,
    } );
    die "Can't create Group $num\n" unless $group;

    # Add the Users to the Group, quickly (I know this doesn't do *everything*
    # that "$group->add_user()" does, but we just need the user_sets_for_user
    # table to be populated).
    sql_txn {
        my $uset = $group->user_set;
        my $group_uset_id = $group->user_set_id;
        my $dbh = get_dbh();
        $dbh->do(q{
            LOCK user_set_include,user_set_path IN SHARE ROW EXCLUSIVE MODE
        });
        $uset->_create_insert_temp($dbh, 'bulk');
        $uset->_insert($dbh, $_, $group_uset_id, $member_id, 'bulk')
            for @user_ids;
    };

    print "g";
}
print "\nDone!\n";
