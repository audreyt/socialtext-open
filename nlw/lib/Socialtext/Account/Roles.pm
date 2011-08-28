package Socialtext::Account::Roles;
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::Role;
use Socialtext::SQL qw(:exec);

###############################################################################
# Get the list of Roles that this User has in the given Account (either
# directly as UARs, or indirectly as UGR+GARs)
sub RolesForUserInAccount {
    my $class   = shift;
    my %p       = @_;
    my $user    = $p{user};
    my $account = $p{account};
    my $direct  = defined $p{direct} ? $p{direct} : 0;

    my $uar_table = $direct
        ? 'user_set_include'
        : 'user_set_path';

    my $sql = qq{
        SELECT role_id
          FROM $uar_table
         WHERE from_set_id = ?
           AND into_set_id = ?
    };
    my $sth = sql_execute($sql, $user->user_id, $account->user_set_id);

    # turn the results into a list of Roles
    my @all_roles =
        map { Socialtext::Role->new(role_id => $_->[0]) }
        @{ $sth->fetchall_arrayref() };

    # sort it from highest->lowest effectiveness
    my @sorted =
        reverse Socialtext::Role->SortByEffectiveness(roles => \@all_roles);

    return wantarray ? @sorted : shift @sorted;
}

1;

=head1 NAME

Socialtext::Account::Roles - User/Account Role helper methods

=head1 SYNOPSIS

  use Socialtext::Account::Roles;

  # Most effective Role that User has in Account
  $role = Socialtext::Account::Roles->RolesForUserInAccount(
    user     => $user,
    account  => $account,
  );

  # List of all Roles that User has in Account
  @roles = Socialtext::Account::Roles->RolesForUserInAccount(
    user    => $user,
    account => $account,
  );

=head1 DESCRIPTION

C<Socialtext::Account::Roles> gathers together a series of helper methods to
help navigate the various types of relationships between "Users" and
"Accounts" under one hood.

Some of these relationships are direct (User->Account), while others are
indirect (User->Group->Account).  The methods in this module aim to help
flatten the relationships so you don't have to care B<how> the User has the
Role in the given Account, only that he has it.

=head1 METHODS

=over

=item B<Socialtext::Account::Roles-E<gt>RolesForUserInAccount(PARAMS)>

Returns the Roles that the User has in the given Account.

In a I<LIST> context, this is the complete list of Roles that the User has in
the Account (either explicit, or via Group membership).  List is ordered
from "highest effectiveness to lowest effectiveness", according to the rules
outlined in L<Socialtext::Role>.  List will have been de-duped; a given Role
will only appear I<once> in the list, regardless of how many times the User
may have been granted that Role in the Account.

In a I<SCALAR> context, this method returns the highest effective Role that
the User has in the Account.

C<PARAMS> must include:

=over

=item user

User object

=item account

Account object

=back

C<PARAMS> may also include:

=over

=item direct => 1|0

A boolean stating whether or not we should only be concerned about B<direct>
Roles in the Account.  By default, direct or indirect Roles are considered.

=back

=back

=head1 AUTHOR

Socialtext, Inc.,  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc.,  All Rights Reserved.

=cut
