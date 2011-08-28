package Test::Socialtext::Account;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Exporter';
use Socialtext::CLI;
use File::Temp qw(tempdir);
use File::Path qw(rmtree);
use Test::Socialtext::CLIUtils qw(expect_success);
use Test::Differences qw/eq_or_diff/;
use Test::Output qw(combined_from);

our @EXPORT_OK = qw/delete_recklessly import_account_ok export_account export_and_reimport_account/;

sub delete_recklessly {
    my ($class, $account) = @_;

    # Load classes on demand
    require Socialtext::SQL;
    require Socialtext::Account;

    # Null out parent_ids in gadgets referencing this account's gadgets
    Socialtext::SQL::sql_execute(q{
        UPDATE gadget_instance
           SET parent_instance_id = NULL
         WHERE parent_instance_id IN (
            SELECT gadget_instance_id
              FROM gadget_instance
             WHERE container_id IN (
                SELECT container_id
                  FROM container
                 WHERE user_set_id = ?
             )
         )
    }, $account->user_set_id);

    $account->delete;

    # Clear all caches (the Account, and anything that may have cached a copy
    # of our count of the Account)
    Socialtext::Cache->clear();
}

sub export_account {
    my $account = shift;
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $export_base = tempdir(CLEANUP => 1);
    my $export_dir   = File::Spec->catdir($export_base, 'account');

    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => [
                    '--account' => $account->name,
                    '--dir'     => $export_dir,
                ],
            )->export_account();
        },
        qr/account exported to/,
        'Account exported',
    );

    return $export_dir;
}

sub import_account_ok {
    my $export_dir = shift;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => ['--dir' => $export_dir],
            )->import_account();
        },
        qr/account imported/,
        '... Account re-imported',
    );
}

our $DumpRoles = 0;
sub export_and_reimport_account {
    my %args            = @_;
    my $acct            = $args{account};
    my @users           = $args{users} ? @{ $args{users} } : ();
    my @groups          = $args{groups} ? @{ $args{groups} } : ();
    my @workspaces      = $args{workspaces} ? @{ $args{workspaces} } : ();
    my $cb_after_export = $args{after_export} || $args{flush} || sub { };
    my $mangle          = $args{mangle};
    my $return_output   = $args{return_output} || 0;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $export_base = tempdir(CLEANUP => 1);
    my $export_dir  = File::Spec->catdir($export_base, 'account');
    my $account_yaml = File::Spec->catfile($export_dir, 'account.yaml');
    Socialtext::Cache->clear();

    # Build up the list of Roles that exist *before* the export/import
    my @gars = map { _dump_gars($_) } $acct;
    my @uars = map { _dump_uars($_) } $acct;
    my @uwrs = map { _dump_uwrs($_) } @workspaces;
    my @gwrs = map { _dump_gwrs($_) } @workspaces;
    my @ugrs = map { _dump_ugrs($_) } @groups;

    # Users should maintain their restrictions across export/import
    my %restrictions = map { $_->username => _dump_restrictions($_) } @users;

    # Export the Account
    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => ['--account', $acct->name, '--dir', $export_dir],
            )->export_account(),
        },
        qr/account exported to/,
        '... Account exported',
    );

    # Flush the system, cleaning out the test Users/Workspaces/Accounts.
    #
    # *DON'T* use a list traversal operation that could manipulate the
    # original list/objects, though; we're going to need them again in a
    # moment.
    $cb_after_export->();
    foreach my $user (@users) {
        Test::Socialtext::User->delete_recklessly($user);
    }
    foreach my $group (@groups) {
        Test::Socialtext::Group->delete_recklessly($group);
    }
    foreach my $ws (@workspaces) {
        Test::Socialtext::Workspace->delete_recklessly($ws);
    }
    Test::Socialtext::Account->delete_recklessly($acct);
    Socialtext::Cache->clear();

    if ($mangle) {
        require YAML;
        my $data = YAML::LoadFile($account_yaml);
        $mangle->($data);
        YAML::DumpFile($account_yaml, $data);
    }

    my $importer = sub {
        Socialtext::CLI->new(
            argv => ['--dir', $export_dir],
        )->import_account();
    };

    # Re-import the Account
    my $output = '';
    if ($return_output) {
        $output = combined_from { eval { $importer->() } };
    }
    else {
        expect_success(
            $importer,
            qr/account imported/,
            '... Account re-imported',
        );
    }

    # Load up copies of all of the Accounts/Workspaces/Groups that exist after
    # the export/import.  Yes, this is a bit ugly (especially for Groups,
    # where on re-import, the unique key is going to change for the Group;
    # primary_account_id changes).
    my $imported_acct = Socialtext::Account->new(name => $acct->name);

    my @imported_workspaces =
        map { Socialtext::Workspace->new(name => $_->name) }
        @workspaces;

    my @imported_groups;
    foreach my $group (@groups) {
        my $primary_account = Socialtext::Account->new(
            name => $group->primary_account->name,
        );
        my $primary_acct_id    = $primary_account->account_id;
        my $created_by_user_id = $group->created_by_user_id;
        my $group_name         = $group->driver_group_name;
        push @imported_groups, Socialtext::Group->GetGroup(
            primary_account_id => $primary_acct_id,
            created_by_user_id => $created_by_user_id,
            driver_group_name  => $group_name,
        );
    }

    # Get the list of Roles that exist *after* the export/import
    my @imported_gars = map { _dump_gars($_) } $imported_acct;
    my @imported_uars = map { _dump_uars($_) } $imported_acct;
    my @imported_uwrs = map { _dump_uwrs($_) } @imported_workspaces;
    my @imported_gwrs = map { _dump_gwrs($_) } @imported_workspaces;
    my @imported_ugrs = map { _dump_ugrs($_) } @imported_groups;

    # Role list *should* be the same after import
    eq_or_diff \@imported_gars, \@gars, '... Group/Account Roles preserved';
    eq_or_diff \@imported_uars, \@uars, '... User/Account Roles preserved';
    eq_or_diff \@imported_uwrs, \@uwrs, '... User/Workspace Roles preserved';
    eq_or_diff \@imported_gwrs, \@gwrs, '... Group/Workspace Roles preserved';
    eq_or_diff \@imported_ugrs, \@ugrs, '... User/Group Roles preserved';

    # (debugging) Dump the Roles
    if ($DumpRoles) {
        use Data::Dumper;
        Test::More::diag "Group/Account Roles: "   . Dumper(\@gars);
        Test::More::diag "User/Account Roles: "    . Dumper(\@uars);
        Test::More::diag "User/Workspace Roles: "  . Dumper(\@uwrs);
        Test::More::diag "Group/Workspace Roles: " . Dumper(\@gwrs);
        Test::More::diag "User/Group Roles: "      . Dumper(\@ugrs);
    }

    # Get the list of User Restrictions *after* the export/import
    my %i_restrictions =
        map {
            my $u = Socialtext::User->new(username => $_->username);
            ($u->username => _dump_restrictions($u));
        } @users;

    # User Restrictions should be the same after import
    eq_or_diff \%i_restrictions, \%restrictions, '... User Restrictions preserved';

    # CLEANUP: remove our temp directory
    rmtree([$export_base], 0);

    return $output;
}

sub _sort_roles {
    sort { return join(',', values %$a) cmp join(',', values %$b) } @_;
}

sub _dump_gars {
    my $account = shift;
    my @gars;
    if ($account) {
        my $cursor  = $account->groups(direct => 0);
        while (my $group = $cursor->next) {
            push @gars, {
                group   => $group->driver_group_name,
                account => $account->name,
                role    => $account->role_for_group($group)->name,
            };
        }
    }
    return _sort_roles @gars;
}

sub _dump_uars {
    my $account = shift;
    my @uars;
    if ($account) {
        my $cursor = $account->users();

        while (my $user = $cursor->next) {
            push @uars, {
                user    => $user->username,
                account => $account->name,
                role    => $account->role_for_user($user)->name,
            };
        }
    }
    return _sort_roles @uars;
}

sub _dump_uwrs {
    my $workspace = shift;
    my @uwrs;
    if ($workspace) {
        my $cursor = $workspace->users();
        while (my $user = $cursor->next) {
            push @uwrs, {
                user      => $user->username,
                workspace => $workspace->name,
                role      => $workspace->role_for_user($user)->name,
            };
        }
    }
    return _sort_roles @uwrs;
}

sub _dump_gwrs {
    my $workspace = shift;
    my @gwrs;
    if ($workspace) {
        my $cursor = $workspace->groups();
        while (my $group = $cursor->next) {
            push @gwrs, {
                group     => $group->driver_group_name,
                workspace => $workspace->name,
                role      => $workspace->role_for_group($group)->name,
            };
        }
    }
    return _sort_roles @gwrs;
}

sub _dump_ugrs {
    my $group = shift;
    my @ugrs;
    if ($group) {
        my $cursor = $group->users();
        while (my $user = $cursor->next) {
            push @ugrs, {
                user  => $user->username,
                group => $group->driver_group_name,
                role  => $group->role_for_user($user)->name,
            };
        }
    }
    return _sort_roles @ugrs;
}

sub _dump_restrictions {
    my $user = shift;
    my @restrictions = map { $_->to_hash } $user->restrictions->all;
    return \@restrictions;
}

1;
