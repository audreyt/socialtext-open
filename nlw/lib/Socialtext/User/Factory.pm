package Socialtext::User::Factory;
# @COPYRIGHT@
use strict;
use warnings;

use Class::Field qw(field);
use Socialtext::Date;
use Socialtext::SQL qw(:exec :time);
use Socialtext::SQL::Builder qw(:all);
use Socialtext::Exceptions qw( data_validation_error );
use Socialtext::String;
use Socialtext::Data;
use Socialtext::User::Base;
use Socialtext::User::Default::Users qw(:system-user :guest-user);
use Socialtext::l10n qw(loc);
use Email::Valid;
use Readonly;
use Scalar::Util qw/blessed/;
use Carp qw/confess/;

field 'driver_name';
field 'driver_id';
field 'driver_key';

sub new_homunculus {
    my $self = shift;
    my $p = shift;
    $p->{driver_key} = $self->driver_key;
    return $self->NewHomunculus($p);
}

sub get_homunculus {
    my $self = shift;
    my $id_key = shift;
    my $id_val = shift;
    return $self->GetHomunculus($id_key, $id_val, $self->driver_key);
}

sub NewHomunculus {
    my $class = shift;
    my $p = shift;

    # create a copy of the parameters for our new User homunculus object
    my %user = %$p;

    confess "homunculi need to have a user_id, driver_key and driver_unique_id"
        unless ($user{user_id} && $user{driver_key} && $user{driver_unique_id});

    # fix up any botched DB/object mappings (why, oh why didn't we get right
    # the very first time)
    $user{username} = delete $user{driver_username} if ($user{driver_username});

    # What kind of User Homunculus object do we need to create?
    # - generally based on the driver
    # - "missing" Users are turned into a "ST::U::Deleted" homunculus to
    #   denote that they've gone missing and aren't valid Users any more.
    my ($driver_name, $driver_id) = split( /:/, $p->{driver_key} );
    $driver_name = 'Deleted' if ($p->{missing});
    require Socialtext::User;
    my $driver_class = join '::', Socialtext::User->base_package, $driver_name;
    eval "require $driver_class";
    die "Couldn't load ${driver_class}: $@" if $@;

    # Assumes a non-strict constructor
    my $homunculus = $driver_class->new(\%user);

    if ($p->{extra_attrs} && $homunculus->can('extra_attrs')) {
        $homunculus->extra_attrs($p->{extra_attrs});
    }

    # Remove password fields for users, where the password is over-ridden by
    # the User driver (Default, LDAP, etc) and where the resulting password is
    # *NOT* of any use.  No point keeping a bunk/bogus/useless password
    # around.
    if ($homunculus->password eq '*no-password*' &&
        $p->{password} && $p->{password} ne '*no-password*')
    {
        $homunculus->password(undef);
    }

    # return the new homunculus; we're done.
    return $homunculus;
}

sub NewUserId {
    return sql_nextval('users___user_id');
}

my @resolve_id_order = (
    [ driver_username  => 'LOWER(driver_username) = LOWER(?)' ],
    [ driver_unique_id => 'driver_unique_id = ?' ],
    [ email_address    => 'LOWER(email_address) = LOWER(?)' ],
);
sub ResolveId {
    my $class = shift;
    my $p = (@_==1) ? shift(@_) : {@_};

    # HACK: map "object -> DB"
    # - ideally we get rid of this thing having two names at different levels
    # of the system, but for now this is needed to address Bug #2658
    if ($p->{username} and not $p->{driver_username}) {
        $p->{driver_username} = $p->{username};
    }

    foreach my $r (@resolve_id_order) {
        my ($field,$sql_suffix) = @$r;
        my $user_id = sql_singlevalue(
            "SELECT user_id FROM users WHERE driver_key = ? AND $sql_suffix",
            $p->{driver_key}, $p->{$field}
        );
        return $user_id if $user_id;
    }

    # nope, couldn't find the user.
    return;
}

sub Now {
    return Socialtext::Date->now(hires=>1);
}

sub GetHomunculus {
    my $class = shift;
    my $id_key = shift;
    my $id_val = shift;
    my $driver_key = shift;

    my $deleted;
    my %opts;
    if ($driver_key && $id_key ne 'user_id') {
        if (ref($driver_key) eq 'ARRAY') {
            $opts{driver_keys} = $driver_key;
            $opts{exclude_driver_keys} = 1;
        }
        else {
            $opts{driver_keys} = [$driver_key];
        }
    }

    my $proto_user = Socialtext::User->GetProtoUser($id_key, $id_val, %opts);
    return unless $proto_user;

    $proto_user->{username} = delete $proto_user->{driver_username};
    return $class->NewHomunculus($proto_user);
}

sub NewUserRecord {
    my $class = shift;
    my $proto_user = shift;

    $proto_user->{user_id} ||= $class->NewUserId();
    $proto_user->{missing} ||= 0;
    $proto_user->{is_profile_hidden} ||= 0;

    # always need a cached_at during INSERT, default it to 'now'
    $proto_user->{cached_at} = $class->Now()
        if (!$proto_user->{cached_at} or 
            !ref($proto_user->{cached_at}) &&
            $proto_user->{cached_at} eq 'now');

    die "cached_at must be a DateTime object"
        unless (ref($proto_user->{cached_at}) && 
                $proto_user->{cached_at}->isa('DateTime'));

    my %insert_args
        = map { $_ => $proto_user->{$_} } @Socialtext::User::Base::all_fields;
    $insert_args{first_name}  ||= '';
    $insert_args{middle_name} ||= '';
    $insert_args{last_name}   ||= '';

    $insert_args{driver_username} = $proto_user->{driver_username};
    delete $insert_args{username};

    $insert_args{cached_at} = 
        sql_format_timestamptz($proto_user->{cached_at});

    sql_insert('users' => \%insert_args);
}

sub UpdateUserRecord {
    my $class = shift;
    my $proto_user = shift;

    die "must have a user_id to update a user record"
        unless $proto_user->{user_id};
    die "must supply a cached_at parameter (undef means 'leave db alone')"
        unless exists $proto_user->{cached_at};

    $proto_user->{cached_at} = $class->Now()
        if ($proto_user->{cached_at} && 
            !ref($proto_user->{cached_at}) &&
            $proto_user->{cached_at} eq 'now');

    my %update_args = map { $_ => $proto_user->{$_} } 
                      grep { exists $proto_user->{$_} }
                      @Socialtext::User::Base::all_fields;

    if ($proto_user->{driver_username}) {
        $update_args{driver_username} = $proto_user->{driver_username};
    }
    delete $update_args{username};

    if (!$update_args{cached_at}) {
        # false/undef means "don't change cached_at in the db"
        delete $update_args{cached_at};
    }
    else {
        die "cached_at must be a DateTime object"
            unless (ref($proto_user->{cached_at}) && 
                    $proto_user->{cached_at}->isa('DateTime'));

        $update_args{cached_at} = 
            sql_format_timestamptz($update_args{cached_at});
    }

    sql_update('all_users' => \%update_args, 'user_id');

    # flush cache; updated User in DB
    require Socialtext::User::Cache;
    Socialtext::User::Cache->Remove( user_id => $proto_user->{user_id} );
}

sub ExpireUserRecord {
    my $self = shift;
    my %p = @_;
    return unless $p{user_id};
    sql_execute(q{
            UPDATE users 
            SET cached_at = '-infinity'
            WHERE user_id = ?
        }, $p{user_id});
    require Socialtext::User::Cache;
    Socialtext::User::Cache->Remove( user_id => $p{user_id} );
}

# Validates a hash-ref of User data, cleaning it up where appropriate.  If the
# data isn't valid, this method throws a Socialtext::Exception::DataValidation
# exception.
{
    Readonly my @required_fields   => qw(username email_address);
    Readonly my @unique_fields     => qw(username email_address private_external_id);
    Readonly my @lowercased_fields => qw(username email_address);
    Readonly my @optional_fields   => qw(private_external_id middle_name);
    sub ValidateAndCleanData {
        my ($self, $user, $p) = @_;
        my @errors;

        # are we "creating a new user", or "updating an existing user"?
        my $is_create = defined $user ? 0 : 1;

        # New user's *have* to have a User Id
        $self->_validate_assign_user_id($p) if ($is_create);

        # Lower-case any fields that require it
        $self->_validate_lowercase_values($p);

        # Trim fields, removing leading/trailing whitespace
        $self->_validate_trim_values($p);

        # Check for presence of required fields
        foreach my $field (@required_fields) {
            # field is required if either (a) we're creating a new User
            # record, or (b) we were given a value to update with
            if ($is_create or exists $p->{$field}) {
                push @errors, $self->_validate_check_required_field($field, $p);
            }
        }

        # Set optional fields explicitly to "undef", so internal hash
        # structures are equivalent regardless of whether this was a newly
        # created User or one that was being pulled up out of the DB.
        if ($is_create) {
            foreach my $field (@optional_fields) {
                unless (defined $p->{$field}) {
                    $p->{$field} = undef;
                }
            }
        }

        # Make sure that unique fields are in fact unique
        foreach my $field (@unique_fields) {
            # value has to be unique if either (a) we're creating a new User,
            # or (b) we're changing the value for an existing User.
            if (defined $p->{$field}) {
                if (   $is_create
                    or !defined $user->{$field}
                    or ($p->{$field} ne $user->{$field})) {
                    push @errors, $self->_validate_check_unique_value($field, $p);
                }
            }
        }

        # Ensure that any provided e-mail address is valid
        push @errors, $self->_validate_email_is_valid($p);

        # Ensure that any provided password is valid
        push @errors, $self->_validate_password_is_valid($p);

        # When creating a new User, we MAY require that a password be provided
        if (delete $p->{require_password} and $is_create) {
            push @errors, $self->_validate_password_is_required($p);
        }

        # Can't change the username/email for a system-created User
        unless ($is_create) {
            require Socialtext::UserMetadata;
            my $metadata = Socialtext::UserMetadata->new(
                user_id => $user->{user_id},
            );
            if ($metadata->is_system_created) {
                push @errors,
                    loc("error.set-system-user-name")
                    if $p->{username};

                push @errors,
                    loc("error.set-system-user-email")
                    if $p->{email_address};
            }
        }

        ### IF DATA FAILED TO VALIDATE, THROW AN EXCEPTION!
        if (@errors) {
            data_validation_error errors => \@errors;
        }

        # when creating a new User, assign a placeholder password unless one
        # was provided.
        $self->_validate_assign_placeholder_password($p) if ($is_create);

        # encrypt any provided password
        $self->_validate_encrypt_password($p);

        # ensure that we're noting who created this User
        $self->_validate_assign_created_by($p) if ($is_create);
        $self->_recreate_display_name($user, $p);
    }

    sub _recreate_display_name {
        my $self = shift;
        my $user = shift;
        my $p    = shift;
        if ($user) {
            # Have a User, so get their Real Name (which will include their
            # Preferred Name if its enabled and they have one set).
            #
            # BUT... we want to take the given "$p" data into consideration,
            # so localize that when we Guess the User's Real Name.
            local $user->{first_name}    = $p->{first_name}    if (defined $p->{first_name});
            local $user->{middle_name}   = $p->{middle_name}   if (defined $p->{middle_name});
            local $user->{last_name}     = $p->{last_name}     if (defined $p->{last_name});
            local $user->{email_address} = $p->{email_address} if (defined $p->{email_address});
            $p->{display_name} = $user->guess_real_name();
        }
        else {
            # No User, so calculate it as best we can from the data provided.
            my $first_name  = $p->{first_name};
            my $middle_name = $p->{middle_name};
            my $last_name   = $p->{last_name};
            my $email       = $p->{email_address};
            {
                no warnings 'uninitialized';
                my $name = join ' ', grep {length} $first_name, $middle_name, $last_name;
                ($name = $email) =~ s/@.+// unless $name;
                $p->{display_name} = $name;
            }
        }
    }

    sub _validate_assign_user_id {
        my ($self, $p) = @_;
        $p->{user_id} ||= $self->NewUserId();
        return;
    }
    sub _validate_lowercase_values {
        my ($self, $p) = @_;
        map { $p->{$_} = lc($p->{$_}) }
            grep { defined $p->{$_} }
            @lowercased_fields;
        return;
    }
    sub _validate_trim_values {
        my ($self, $p) = @_;
        map { $p->{$_} = Socialtext::String::trim($p->{$_}) }
            grep { defined $p->{$_} }
            @Socialtext::User::Base::all_fields;
        return;
    }
    sub _validate_check_required_field {
        my ($self, $field, $p) = @_;
        unless ((defined $p->{$field}) and (length($p->{$field}))) {
            return loc('error.required=field',
                ucfirst Socialtext::Data::humanize_column_name($field)
            );
        }
        return;
    }
    sub _validate_check_unique_value {
        my ($self, $field, $p) = @_;
        my $value = $p->{$field};
        my $isnt_unique = eval {
            Socialtext::User->_first('lookup', $field => $value);
        };
        if ($isnt_unique) {
            # User lookup found _something_.
            # 
            # If what we found wasn't "us" (the User data we're checking for
            # unique-ness), fail.
            my $driver_uid   = $p->{driver_unique_id};
            my $existing_uid = $isnt_unique->{driver_unique_id};
            if (!$driver_uid || ($driver_uid ne $existing_uid)) {
                return loc("error.user-exists=field,value",
                        Socialtext::Data::humanize_column_name($field), $value
                    );
            }
        }
        return;
    }
    sub _validate_email_is_valid {
        my ($self, $p) = @_;
        my $email = $p->{email_address};
        if (defined $email) {
            unless (length($email) and Email::Valid->address($email)) {
                return loc('error.invalid=email', $email);
            }
        }
        return;
    }
    sub _validate_password_is_valid {
        my ($self, $p) = @_;
        my $password = $p->{password};
        if (defined $password) {
            require Socialtext::User::Default;
            return Socialtext::User::Default->ValidatePassword(
                password => $password,
            );
        }
        return;
    }
    sub _validate_password_is_required {
        my ($self, $p) = @_;
        unless (defined $p->{password}) {
            return loc('error.no-password-for-new-user');
        }
        return;
    }
    sub _validate_assign_placeholder_password {
        my ($self, $p) = @_;
        my $password = $p->{password};
        unless (defined $password and length($password)) {
            $p->{password} = '*none*';
            $p->{no_crypt} = 1;
        }
        return;
    }
    sub _validate_encrypt_password {
        my ($self, $p) = @_;
        if ((exists $p->{password}) and (not delete $p->{no_crypt})) {
            require Socialtext::User::Default;
            $p->{password} =
                Socialtext::User::Default->_encode_password($p->{password});
        }
        return;
    }
    sub _validate_assign_created_by {
        my ($self, $p) = @_;
        if ($p->{username} ne $SystemUsername) {
            # unless we were told who is creating this User, presume that it's
            # being created by the System-User.
            $p->{created_by_user_id} ||= Socialtext::User->SystemUser()->user_id;
        }
        return;
    }
}

sub is_cached_proto_user_valid {
    my $self       = shift;
    my $proto_user = shift;

    return 0 unless $self->cache_is_enabled;
    return 0 unless $proto_user;
    return 0 unless $proto_user->{cached_at};
    return 0 unless $proto_user->{driver_key} eq $self->driver_key;

    my $ttl = $self->db_cache_ttl($proto_user);
    my $cutoff    = $self->Now() - $ttl;
    my $cached_at = sql_parse_timestamptz($proto_user->{cached_at});

    return $cached_at gt $cutoff;
}

1;

=head1 NAME

Socialtext::User::Factory - Abstract base class for User factories.

=head1 DESCRIPTION

C<Socialtext::User::Factory> provides class methods that factories should use when retrieving/storing users in the system database.

Subclasses of this module *MUST* be named C<Socialtext::User::${driver_name}::Factory>

A "Driver" is the code used to instantiate Homunculus objects.  A "Factory" is an instance of a driver (C<Socialtext::User::LDAP::Factory> can have multiple factories configured, while C<Socialtext::User::Default::Factory> can only have one instance).

=head1 METHODS

=over

=item B<driver_name()>

The driver_name is a name that identifies this factory class.  Code will use
this name to initialize a driver instance ("factory").

=item B<driver_id()>

Returns the unique ID for the instance of the data store ("factory") this user
was found in.  This unique ID is internal and likely has no meaning to a user.
e.g. "0deadbeef0".

=item B<driver_key()>

Returns the fully qualified driver key in the form ("name:id") of this factory (driver instance).

The database will use this key to map users to their owning factories.  This
key is internal and likely has no meaning to an end-user.  e.g.
"LDAP:0deadbeef0".

=item B<new_homunculus(\%proto_user)>

Calls C<NewHomunculus(\%proto_user)>, overriding the driver_key field of the proto_user with the result of C<$self->driver_key>.

=item B<get_homunculus($id_key => $id_val)>

Calls C<GetHomunculus()>, passing in the driver_key of this factory.

=back

=head2 CLASS METHODS

=over

=item B<NewHomunculus(\%proto_user)>

Helper method that will instantiate a Homunculus based on the driver_key field
contained in the C<\%proto_user> hashref.

Homunculi need to have a user_id, driver_key and driver_unique_id to be created.

=item B<NewUserId()>

Returns a new unique identifier for use in creating new users.

=item B<ResolveId(\%params)>

Attempts to resolve the C<user_id> for the User represented by the given
C<\%params>.

Resolution is limited to B<just> the C<driver_key> specified in the params;
we're I<not> doing cross-driver resolution.

Default implementation here attempts resolution by looking for a matching
C<driver_unique_id>.

=item B<Now()>

Creates a DateTime object with the current time from C<Time::HiRes::time> and
returns it.

=item B<GetHomunculus($id_key,$id_val,$driver_key)>

Retrieves a new user record from the system database and uses C<NewHomunculus()> to instantiate it.

Given an identifying key, it's value, and the driver key, dip into the
database and return a C<Socialtext::User::Base> homunculus.  For example, if
given a 'Default' driver key, the returned object will be a
C<Socialtext::User::Default> homunculus.

If C<$id_key> is 'user_id', the C<$driver_key> is ignored as a parameter.

=item B<NewUserRecord(\%proto_user)>

Creates a new user record in the system database.

Uses the specified hashref to obtain the necessary values.

The 'cached_at' field must be a valid C<DateTime> object.  If it is missing or
set to the string "now", the current time (with C<Time::HiRes> accuracy) is
used.

If a user_id is not supplied, a new one will be created with C<NewUserId()>.

=item B<UpdateUserRecord(\%proto_user)>

Updates an existing user record in the system database.  

A 'user_id' must be present in the C<\%proto_user> argument for this update to
work.

Uses the specified hashref to obtain the necessary values.  'user_id' cannot
be updated and will be silently ignored.

If the 'cached_at' parameter is undef, that field is left alone in the
database.  Otherwise, 'cached_at' must be a valid C<DateTime> object.  If it
is missing or set to the string "now", the current time (with C<Time::HiRes>
accuracy) is used.

Fields not specified by keys in the C<\%proto_user> will not be changed.  Any
keys who's value is undef will be set to NULL in the database.

=item B<ExpireUserRecord(user_id => 42)>

Expires the specified user.

The `cached_at` field of the specified user is set to '-infinity' in the
database.

=item B<ValidateAndCleanData($user, \%p)>

Validates and cleans the given hashref of data, which I<may> be an update for
the provided C<$user> object.

If a C<Socialtext::User> object is provided for C<$user>, this method
validates the data as if we were performing an B<update> to the information in
that User object.

If no value is provided for C<$user>, this method validates the data as if we
were creating a B<new> User object.

On success, this method returns.  On validation error, it throws a
C<Socialtext::Exception::DataValidation> exception.

=back

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
