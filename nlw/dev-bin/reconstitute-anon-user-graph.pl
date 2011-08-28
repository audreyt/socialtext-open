#!/usr/bin/env perl
# @COPYRIGHT@
use warnings;
use strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Socialtext::SQL qw/get_dbh/;
use YAML::Syck qw/LoadFile/;
use List::MoreUtils qw/zip/;

# 
# Reconstitues the user graph generaed by anon-user-graph-dump.pl
#
# Currently expects the schema version to be schema 95 for testing the big
# user-set migration.
# 
# run `st-db dropdb; st-db createdb; psql -f
# etc/socialtext/db/socialtext-schema.sql` prior to running this script.
#

my $input_file = (@ARGV && shift @ARGV) || '/home/stash/anon-user-graph2.www.yaml';

my %tables;
{
    die "no such file $input_file" unless (-r $input_file);
    my @tables = LoadFile($input_file);
    print "loaded yaml!\n";

    while (my $table = shift @tables) {
        my $name = $table->{aa_table};
        $tables{$name} = $table;
    }
}

my @table_order = qw(
    Role
    Account
    users
    Workspace
    groups
    user_account_role
    user_workspace_role
    user_group_role
    group_account_role
    group_workspace_role
);

my $dbh = get_dbh;
$dbh->{RaiseError} = 1;

sub prep {
    my ($table, $col_list) = @_;

    my $cols = join(',',@$col_list);
    my $phs = '?,' x scalar @$col_list;
    chop $phs;

    my $sql = qq{INSERT INTO "$table" ($cols) VALUES ($phs)};
    my $sth = $dbh->prepare($sql);
    return $sth;
}

for my $name (@table_order) {
    print "$name\n";
    my $table = $tables{$name};
    my $data = $table->{zz_data};
    my @cols = @{$table->{bb_names}};

    if (   $name eq 'Role'
        || $name eq 'group_account_role'
        || $name eq 'group_workspace_role'
        || $name eq 'user_group_role'
        || $name eq 'user_account_role'
        || $name eq 'user_workspace_role')
    {
        my $sth = prep($name => \@cols);
        while (my $row = shift @$data) {
            $sth->execute(@$row);
        }
    }
    elsif ($name eq 'Account') {
        my @ws_cols = qw(
            account_id
            name
            user_set_id
        );
        my $sth = prep($name => \@ws_cols);
        while (my $raw_row = shift @$data) {
            my $row = {zip @cols, @$raw_row};
            my $full_row = {
                account_id => $row->{account_id},
                name => "Account num $row->{account_id}",
                user_set_id => $row->{account_id} + 0x30000000,
            };
            $sth->execute(@$full_row{@ws_cols});
        }
    }
    elsif ($name eq 'Workspace') {
        my @ws_cols = qw(
            workspace_id
            name
            title
            account_id
            created_by_user_id
            user_set_id
        );
        my $sth = prep($name => \@ws_cols);
        while (my $raw_row = shift @$data) {
            my $row = {zip @cols, @$raw_row};
            my $full_row = {
                workspace_id => $row->{workspace_id},
                user_set_id => $row->{workspace_id} + 0x20000000,
                name => "wksp$row->{workspace_id}",
                title => "Workspace $row->{workspace_id}",
                account_id => $row->{account_id},
                created_by_user_id => 1,
            };
            $sth->execute(@$full_row{@ws_cols});
        }
    }
    elsif ($name eq 'users') {
        my @users_cols = qw(
            user_id
            driver_key
            driver_unique_id
            driver_username
            email_address
            display_name
        );
        my $sth = prep(users => \@users_cols);

        my @um_cols = qw(
            user_id
            email_address_at_import
            primary_account_id
        );
        my $um_sth = prep('UserMetadata' => \@um_cols);

        while (my $raw_row = shift @$data) {
            my $row = {zip @cols, @$raw_row};
            my $full_row = {
                user_id => $row->{user_id},
                driver_key => 'Default',
                driver_unique_id => $row->{user_id},
                driver_username => "user_$row->{user_id}",
                email_address => "user$row->{user_id}\@ken.socialtext.net",
                display_name => "user num $row->{user_id}",
            };
            $sth->execute(@$full_row{@users_cols});

            my $um_row = {
                user_id => $row->{user_id},
                email_address_at_import => $full_row->{email_address},
                primary_account_id => $row->{primary_account_id}
            };
            $um_sth->execute(@$um_row{@um_cols});
        }
    }
    elsif ($name eq 'groups') {
        my @grp_cols = qw(
            group_id
            user_set_id
            driver_key
            driver_unique_id
            driver_group_name
            primary_account_id
            created_by_user_id
        );
        my $sth = prep($name => \@grp_cols);
        while (my $raw_row = shift @$data) {
            my $row = {zip @cols, @$raw_row};
            my $full_row = {
                group_id => $row->{group_id},
                user_set_id => $row->{group_id} + 0x10000000,
                driver_key => 'Default',
                driver_unique_id => $row->{group_id},
                driver_group_name => "Group num $row->{group_id}",
                primary_account_id => $row->{primary_account_id},
                created_by_user_id => 1,
            };
            $sth->execute(@$full_row{@grp_cols});
        }
    }
}
