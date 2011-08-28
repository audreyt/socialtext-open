# @COPYRIGHT@
package Socialtext::User::Default::Factory;
use strict;
use warnings;

use base qw(Socialtext::User::Factory);

use Class::Field qw(field const);
use Digest::SHA ();
use Socialtext::User::Cache;
use Socialtext::Data;
use Socialtext::SQL qw(sql_execute sql_singlevalue);
use Socialtext::User;
use Socialtext::UserMetadata;
use Socialtext::MultiCursor;
use Socialtext::User::Default::Users qw(:system-user :guest-user);

const 'driver_name' => 'Default';
const 'driver_key'  => 'Default';
const 'driver_id'   => undef;

our $CacheEnabled = 1; # only change this for test purposes

# FIXME: This belongs elsewhere, in fixture generation code, perhaps
sub _create_default_user {
    my $self = shift;
    my ($username, $email, $first_name, $created_by) = @_;

    my $id = $self->NewUserId();
    my $system_user = $self->create(
        driver_unique_id => $id,
        user_id          => $id,
        username         => $username,
        email_address    => $email,
        first_name       => $first_name,
        last_name        => 'User',
        password         => '*no-password*',
        no_crypt         => 1,
    );
    my $account = Socialtext::Account->Socialtext;
    Socialtext::UserMetadata->create(
        user_id            => $id,
        created_by_user_id => $created_by,
        is_system_created  => 1,
        primary_account_id => $account->account_id(),
    );

    return $id;
}

sub EnsureRequiredDataIsPresent {
    my $class = shift;

    # create a default instance of the User factory
    my $factory = $class->new();

    # set up the required data
    unless ($factory->GetUser(username => $SystemUsername)) {
        $factory->_create_default_user(
            $SystemUsername, $SystemEmailAddress,
            'System', undef
        );
    }

    unless ($factory->GetUser(username => $GuestUsername)) {
        my $system_user = Socialtext::User->new(username => $SystemUsername);
        $factory->_create_default_user(
            $GuestUsername, $GuestEmailAddress,
            'Guest', $system_user->user_id
        );
    }
}

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = { };
    bless $self, $class;
}

sub Count {
    my $self = shift;
    return sql_singlevalue(
        'SELECT COUNT(*) FROM users WHERE driver_key=?',
        $self->driver_key
    );
}

sub GetUser {
    my ($self, $id_key, $id_val, %opts) = @_;
    my $proto = $opts{preload};
    if ($proto && $proto->{driver_key} eq $self->driver_key) {
        $self->UpdateUserRecord({
            %$proto,
            cached_at => 'now',
        });
        return $self->NewHomunculus($proto);
    }
    return $self->get_homunculus($id_key, $id_val);
}

sub lookup {
    my ($self, $key, $val) = @_;
    return Socialtext::User->GetProtoUser(
        $key, $val, 
        driver_keys => [$self->driver_key],
    );
}

sub create {
    my ( $self, %p ) = @_;

    $self->ValidateAndCleanData(undef, \%p);

    $p{first_name}         ||= '';
    $p{middle_name}        ||= '';
    $p{last_name}          ||= '';
    $p{primary_account_id} ||= Socialtext::Account->Default()->account_id;

    $p{driver_key}       = $self->driver_key;
    $p{driver_unique_id} = $p{user_id};

    $p{driver_username} = delete $p{username};
    $self->NewUserRecord(\%p);
    $p{username} = delete $p{driver_username};

    return $self->new_homunculus(\%p);
}

# "update" methods: generic update?
sub update {
    my ( $self, $user, %p ) = @_;

    $self->ValidateAndCleanData($user, \%p);

    $p{cached_at} = DateTime::Infinite::Future->new();
    delete $p{driver_key}; # can't update, sorry

    $self->UpdateUserRecord( {
        %p,
        driver_username => $p{username},
        user_id => $user->user_id,
    } );

    while (my ($column, $value) = each %p) {
        $user->$column($value);
    }

    # update cache entry for user
    Socialtext::User::Cache->Store( user_id => $user->user_id, $user );

    return $user;
}


# Required Socialtext::User plugin methods

sub Search {
    my $self = shift;
    my $search_term = shift;

    # SANITY CHECK: have inbound parameters
    return unless $search_term;

    # build/execute the search
    my $splat_term = lc "\%$search_term\%";

    my $sth = sql_execute(q{
            SELECT first_name, middle_name, last_name, email_address
              FROM users
             WHERE (
                     LOWER( driver_username ) LIKE ? OR
                     LOWER( email_address ) LIKE ? OR
                     LOWER( first_name ) LIKE ? OR
                     LOWER( last_name ) LIKE ?
                   )
                   AND ( driver_key = ? )
                   AND ( driver_username NOT IN (?, ?) )
        },
        $splat_term, $splat_term, $splat_term, $splat_term,
        $self->driver_key,
        $SystemUsername, $GuestUsername
    );

    return Socialtext::MultiCursor->new(
        iterables => [ $sth->fetchall_arrayref ],
        apply => sub {
            my $row = shift;
            my $name = Socialtext::User->FormattedEmail(@$row);
            return {
                driver_name    => $self->driver_key,
                email_address  => $row->[3],
                name_and_email => $name,
            };
        },
    )->all;
}

sub cache_is_enabled { return $CacheEnabled; }

sub db_cache_ttl {
    my $self       = shift;
    my $proto_user = shift;

    my $ttl = Socialtext::AppConfig->default_user_ttl;
    return DateTime::Duration->new(seconds => $ttl);
}

1;

__END__

=head1 NAME

Socialtext::User::Default::Factory - A Socialtext RDBMS User Factory

=head1 SYNOPSIS

  use Socialtext::User::Default::Factory;

  # instantiate default RDBMS factory
  $factory = Socialtext::User::Default::Factory->new();

  # instantiate user
  $user = $factory->GetUser( user_id => $user_id );
  $user = $factory->GetUser( username => $username );
  $user = $factory->GetUser( email_address => $email_address );

    # user search
  @results = $factory->Search( 'foo' );

=head1 DESCRIPTION

C<Socialtext::User::Default::Factory> provides a a User factory for users that
live in our "users" table.  Each object represents a single row from the table.

=head1 METHODS

=over

=item B<Socialtext::User::Default::Factory-E<gt>new()>

Creates a new RDBMS user factory.

=item B<driver_name()>

The name of this factory, always returns 'Default'

=item B<driver_key()>

The name of this factory, always returns 'Default' since only one Default
factory can be configured per system.

=item B<driver_id()>

Returns undef since only one Default factory can be configured per system.

=item B<< Socialtext::User::Default::Factory->EnsureRequiredDataIsPresent() >>

Inserts required users into the DBMS if they are not present.  See
L<Socialtext::Data> fo rmore details on required data.

=item B<< Socialtext::User::Default::Factory->Count() >>

Returns the number of User records in the database.

=item B<GetUser($key, $val)>

Searches for the specified user in the RDBMS data store and returns a new
C<Socialtext::User::Default> object representing that user if it exists.

For Default users, C<user_id == driver_unique_id>.

User lookups can be performed by I<one> of:

=over

=item * user_id => $user_id

=item * driver_unique_id => $driver_unique_id

=item * username => $username

=item * email_address => $email_address

=back

=item B<lookup($key, $val)>

Looks up a user in the Default data store and returns a hash-ref of data on
that user.

Lookups can be performed using the same criteria as listed for C<GetUser()>
above.

=item B<create(%params)>

Attempts to create a user with the given information and returns a new
C<Socialtext::User::Default> object representing the new user.

Valid C<%params> include:

=over

=item * username - required

=item * email_address - required

=item * password - see below for default

Normally, the value for "password" should be provided in unencrypted
form.  It will be stored in the DBMS in C<crypt()>ed form.  If you
must pass in a crypted password, you can also pass C<< no_crypt => 1
>> to the method.

The password must be at least six characters long.

If no password is specified, the password will be stored as the string
"*none*", unencrypted. This will cause the C<<
$user->has_valid_password() >> method to return false for this user.

=item * require_password - defaults to false

If this is true, then the absence of a "password" parameter is
considered an error.

=item * first_name

=item * middle_name

=item * last_name

=back

=item B<update($user, %params)>

Updates the user's information with the new key/val pairs passed in.  You
cannot change username or email_address for a row where is_system_created is
true.

=item B<Socialtext::User::Default::Factory-E<gt>Search($term)>

Search for user records where the given search C<$term> is found in any one
of the following fields:

=over

=item * username

=item * email_address

=item * first_name

=item * last_name

=back

The search will return back to the caller a list of hash-refs containing the
following key/value pairs:

=back

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005-2008 Socialtext, Inc., All Rights Reserved.

=cut
