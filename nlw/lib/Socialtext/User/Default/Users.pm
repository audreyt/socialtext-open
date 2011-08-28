package Socialtext::User::Default::Users;
# @COPYRIGHT@

use strict;
use warnings;
use base qw(Exporter);

our @EXPORT_OK = qw(
    $SystemUsername
    $SystemEmailAddress
    $GuestUsername
    $GuestEmailAddress
);
our %EXPORT_TAGS = (
    'system-user'   => [qw($SystemUsername $SystemEmailAddress)],
    'guest-user'    => [qw($GuestUsername $GuestEmailAddress)],
);

our $SystemUsername = 'system-user';
our $SystemEmailAddress = 'system-user@socialtext.net';

our $GuestUsername  = 'guest';
our $GuestEmailAddress = 'guest@socialtext.net';

{
    # optimized for hash-lookup; it'll be done on every user instantiation, so
    # make it fast.
    my %RequiredDefaultUsers = (
        username => {
            $SystemUsername => 1,
            $GuestUsername  => 1,
        },
        email_address => {
            $SystemEmailAddress => 1,
            $GuestEmailAddress  => 1,
        },
    );

    sub IsDefaultUser {
        my ( $class, $key, $val ) = @_;
        return $RequiredDefaultUsers{$key}{lc($val)};
    }

    sub CanImportUser {
        my ($class, $user_hash) = @_;
        # Silently refuse to import the two special system users
        return if $user_hash->{username}
            =~ m/^(?:$SystemUsername|$GuestUsername)$/;
        return if $user_hash->{email_address}
            =~ m/^(?:$SystemEmailAddress|$GuestEmailAddress)$/;

        # Do not import the is_system_created flag.
        if (delete $user_hash->{is_system_created}) {
            warn "$user_hash->{username} was system created. "
                . "Importing as regular user.\n";
        }
        return 1;
    }
}

1;

=head1 NAME

Socialtext::User::Default::Users - information on default Users

=head1 SYNOPSIS

  use Socialtext::User::Default::Users qw(:system-user :guest-user);

  $is_default = Socialtext::User::Default::Users->IsDefaultUser(
      username => $username,
  )

=head1 DESCRIPTION

C<Socialtext::User::Default::Users> exports information on the username and
e-mail address for the "out of the box" set of Default Users that should be
created in the system; the "system user" and the "guest user".

These Users aren't created or set up here, we're just defining the information on those Users so it can be consumed by other modules.

=head1 METHODS

=over

=item B<< Socialtext::User::Default::Users->IsDefaultUser($key, $val) >>

Checks to see if the user defined by the given C<%args> is one of the users
that B<must> reside in the Default data store (the system-level user records).
This method returns true if the user must reside in the Default store,
returning false otherwise.

Lookups can be performed by I<one> of:

=over

=item * username => $username

=item * email_address => $email_address

=back

=back

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Socialtext, Inc., All Rights Reserved.

=cut
