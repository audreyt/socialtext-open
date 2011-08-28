package Socialtext::Group::Factory;
# @COPYRIGHT@
use Moose::Role;
use Carp qw(croak);
use List::Util qw(first);
use Socialtext::Date;
use Socialtext::UserSet qw/:const/;
use Socialtext::Exceptions qw(data_validation_error);
use Socialtext::Group::Homunculus;
use Socialtext::Log qw(st_log);
use Socialtext::Role;
use Socialtext::SQL qw(:exec :time sql_txn);
use Socialtext::SQL::Builder qw(:all);
use Socialtext::l10n qw(loc);
use Socialtext::Timer qw/time_scope/;
use namespace::clean -except => 'meta';

# Do *NOT* disable this unless you are testing!
our $CacheEnabled = 1;

# Do *NOT* disable this unless you know why you're doing a *SYNC* lookup
our $Asynchronous = 1;

with qw(Socialtext::SqlBuilder);

use constant Builds_sql_for => 'Socialtext::Group::Homunculus';

has 'driver_key' => (
    is => 'ro', isa => 'Str',
    required => 1,
);

has 'driver_name' => (
    is => 'ro', isa => 'Str',
    lazy_build => 1,
);

has 'driver_id' => (
    is => 'ro', isa => 'Maybe[Str]',
    lazy_build => 1,
);

has 'cache_lifetime' => (
    is => 'ro', isa => 'DateTime::Duration',
    lazy_build => 1,
);

# Methods we require downstream classes consuming this role to implement:
requires 'Create'; around 'Create' => \&sql_txn;
requires 'Update'; around 'Update' => \&sql_txn;
requires 'Available'; around 'Available' => \&sql_txn;
requires 'can_update_store';
requires 'is_cacheable';
requires '_build_cache_lifetime';
requires '_lookup_group';
requires '_update_group_members';

sub _build_driver_name {
    my $self = shift;
    my ($name, $id) = split /:/, $self->driver_key();
    return $name;
}

sub _build_driver_id {
    my $self = shift;
    my ($name, $id) = split /:/, $self->driver_key();
    return $id;
}

# Retrieves a Group from the DB, managed by this Factory instance, and returns
# a Group Homunculus object for the Group back to the caller.
sub GetGroupHomunculus {
    my ($self, %p) = @_;

    # Only concern ourselves with valid Db Columns
    my $where = $self->FilterValidColumns( \%p );

    return undef unless $self->_has_valid_column_data($where);

    # check DB for existing cached Group
    # ... if cached copy exists and is fresh, use that
    my $t = time_scope 'group_check_cache';
    my $proto_group = $self->_get_cached_group($where);
    if ($proto_group && $self->_cached_group_is_fresh($proto_group)) {
        return $self->NewGroupHomunculus($proto_group);
    }

    # cache non-existent or stale, refresh from data store
    # ... if unable to refresh, return empty-handed; we know nothing about
    # this Group.
    $t = time_scope 'group_lookup';
    my $refreshed = $self->_lookup_group($proto_group || $where);
    unless ($refreshed) {
# XXX: what if?... we had an old cached group, but couldn't find it now?
        return;
    }

    # validate the data we got from the underlying data store
    #
    # IF ...
    # ... we're adding a new Group to the system, this is a fatal error
    # ... we're updating an existing Group, log error and re-use old data
    eval {
        $self->ValidateAndCleanData($proto_group, $refreshed);
    };
    if (my $e = Exception::Class->caught('Socialtext::Exception::DataValidation')) {
        # data validation error; log as error and attempt to continue
        my $group_name = $proto_group->{driver_group_name}
            || $refreshed->{driver_group_name};
        st_log->warning("Unable to refresh LDAP Group '$group_name':");
        foreach my $err ($e->messages) {
            st_log->warning(" * $err");
        }
        # re-use the last known data we got from LDAP; refreshed data is bunk
        $refreshed = +{ };
    }
    elsif ($@) {
        # some other kind of error; re-throw it
        die $@;
    }

    # depending on whether or not the Group existed in the DB to begin with,
    # INSERT/UPDATE a record in the DB for the Group.
    if ($proto_group && %{$proto_group}) {
        # Had one in the DB before; UPDATE
        $proto_group = {
            %{$proto_group},
            %{$refreshed},
            cached_at => $self->Now(),
        };
        $self->UpdateGroupRecord( $proto_group );
    }
    else {
        # Wasn't in DB; INSERT
        $proto_group = $refreshed;
        sql_txn {
            $self->NewGroupRecord( $proto_group );
            $self->CreateInitialRelationships( $proto_group );
        };
    }

    # Re-index the freshly created/updated group.
    Socialtext::JobCreator->index_group($proto_group->{group_id});

    my $homey = $self->NewGroupHomunculus($proto_group);

    if ($Asynchronous) {
        $self->_make_me_a_job(
            group_id  => $proto_group->{group_id},
        );
    }
    else {
        my $t2 = time_scope 'group_membership_update';
        $self->_update_group_members($homey, $proto_group->{members});
    }

    return $homey;
}

# Create the initial creator/account relationships for a Group
around 'CreateInitialRelationships' => \&sql_txn;
sub CreateInitialRelationships {
    my ($self, $proto_or_homey) = @_;

    # Upscale whatever we were given into an actual "Group" object
    my $homey = ref($proto_or_homey) eq 'HASH'
        ? $self->NewGroupHomunculus($proto_or_homey)
        : $proto_or_homey;
    my $group = Socialtext::Group->new(homunculus => $homey);

    # Add the creator as an Admin of the Group
    my $creator = $group->creator;
    unless ($creator->is_system_created) {
        # call add_role directly, we already know the object is a user and
        # add_user will not passthru the `force` param.
        $group->add_role(
            role   => Socialtext::Role->Admin,
            object => $creator,
            actor  => $creator,
            force  => 1,
        );
    }

    # Make sure the Group has a Role in its Primary Account, *BYPASSING*
    # logging and event generation.
    my $pri_account = $group->primary_account;
    $pri_account->user_set->add_object_role($group, Socialtext::Role->Member);

    # Make sure that the Group is properly added to any AUW that exists in the
    # Account.
    my $adapter = Socialtext::Pluggable::Adapter->new;
    $adapter->make_hub(Socialtext::User->SystemUser);
    $adapter->hook(
        'nlw.add_group_account_role',
        [$pri_account, $group, Socialtext::Role->Member],
    );
}

# Please refer to t/live-ldap/Groups-refresh-as-jobs.t for test coverage of
# this job.
sub _make_me_a_job {
    my $self = shift;
    my %p    = @_;

    # Make this high priority, group membership updates are important.
    my $rc = Socialtext::JobCreator->insert(
        'Socialtext::Job::GroupRefresh',
        {
            %p, # pass through args.
            job => {
                priority => 50,
                uniqkey  => 'group_id:' . $p{group_id},
            },
        }
    );
}

# Looks up a Group in the DB, to see if we have a cached copy of it already.
sub _get_cached_group {
    my ($self, $where) = @_;

    # XXX: This is a secret public method, so we have to do this
    # check here, too. We should probably promote this in the future.
    return undef unless $self->_has_valid_column_data($where);

    # fetch the Group from the DB
    my $sth = $self->SqlSelectOneRecord( {
        where => {
            %{$where},
            driver_key  => $self->driver_key,
        },
    } );

    my $row = $sth->fetchrow_hashref();
    return $row;
}

# Validate user supplied data for lookups
sub _has_valid_column_data {
    my $self = shift;
    my $data = shift;

    if ( my $group_id = $data->{group_id} ) {
        return 0 unless $group_id =~ qr/^\d+$/;
    }

    return 1;
}

# Checks to see if the cached Group data is fresh, using the cache lifetime
# for this Group Factory.
sub _cached_group_is_fresh {
    my ($self, $proto_group) = @_;

    # If the Factory doesn't support caching, then items are *always*
    # considered fresh.
    return 1 unless $self->is_cacheable();

    # Allow for the cache to be en/disabled for testing purposes
    return 0 unless $CacheEnabled;

    # Check to see if the cached proto_group is fresh
    my $now       = $self->Now();
    my $ttl       = $self->cache_lifetime();
    my $cached_at = sql_parse_timestamptz($proto_group->{cached_at});
    if (($cached_at + $ttl) > $now) {
        return 1;
    }
    return 0;
}

# Delete a Group object from the local DB.
around 'Delete' => \&sql_txn;
sub Delete {
    my $self = shift;
    my $group = shift;
    $self->DeleteGroupRecord( $group->primary_key(), @_ );
}

# Deletes a Group record from the local DB.
around 'DeleteGroupRecord' => \&sql_txn;
sub DeleteGroupRecord {
    my ($self, $proto_group, $actor) = @_;
    $actor ||= Socialtext::User->SystemUser;

    # Delete any copy of this Group in the *in-memory* cache
    Socialtext::Group->cache->remove($proto_group->{group_id});

    # Only concern ourselves with valid Db Columns
    my $where = $self->FilterValidColumns( $proto_group );

    # DELETE the record in the DB
    my $sth = $self->SqlDeleteOneRecord( $where );
    my $rows = $sth->rows();

    st_log->info("DELETE,GROUP,group:$proto_group->{group_id},actor:"
                . $actor->username);

    return $rows;
}

# Updates the local DB using the provided Group information
around 'UpdateGroupRecord' => \&sql_txn;
sub UpdateGroupRecord {
    my ($self, $proto_group) = @_;

    # Delete any copy of this Group in the *in-memory* cache
    Socialtext::Group->cache->remove($proto_group->{group_id});

    $proto_group->{cached_at} ||= $self->Now();

    # Only concern ourselves with valid Db Columns
    my $valid = $self->FilterValidColumns( $proto_group );

    # Update is done against the primary key
    my $pkey = $self->FilterPrimaryKeyColumns( $valid );

    # Don't allow for primary key fields to be updated
    my $values = $self->FilterNonPrimaryKeyColumns( $valid );

    # If there's nothing to update, *don't*.
    return unless %{$values};

    # UPDATE the record in the DB
    my $sth = $self->SqlUpdateOneRecord( {
        values => $values,
        where  => $pkey,
    } );
}

# Expires a Group record in the local DB store
sub ExpireGroupRecord {
    my ($self, %p) = @_;
    return $self->UpdateGroupRecord( {
        %p,
        'cached_at' => '-infinity',
    } );
}

# Current date/time, as DateTime object
sub Now {
    return Socialtext::Date->now(hires=>1);
}

# Creates a new Group Homunculus
sub NewGroupHomunculus {
    my ($self, $proto_group) = @_;

    # determine type of Group Homunculus to create, and make sure that we've
    # got the appropriate module loaded.
    my ($driver_name, $driver_id) = split /:/, $proto_group->{driver_key};
    my $driver_class = join '::', Socialtext::Group->base_package, $driver_name;
    eval "require $driver_class";
    die "Couldn't load ${driver_class}: $@" if $@;

    # instantiate the homunculus, and return it back to the caller
    my $homey = $driver_class->new($proto_group);
    return $homey;
}

# Returns the next available Group Id
sub NewGroupId {
    return sql_nextval('groups___group_id');
}

# Creates a new Group object in the local DB store
around 'NewGroupRecord' => \&sql_txn;
sub NewGroupRecord {
    my ($self, $proto_group) = @_;

    # make sure that the Group has a "group_id"
    $proto_group->{group_id} ||= $self->NewGroupId();

    # force a 1:1 relationship between group_id and user_set_id
    $proto_group->{user_set_id} = $proto_group->{group_id} + GROUP_OFFSET;

    # new Group records default to being cached _now_.
    $proto_group->{cached_at} ||= $self->Now();
    $proto_group->{description} = ''
        unless defined $proto_group->{description};

    # Only concern ourselves with valid Db Columns
    my $valid = $self->FilterValidColumns( $proto_group );

    # SANITY CHECK: need all required attributes
    my $missing =
        first { not defined $valid->{$_} }
        map   { $_->name }
        grep  { $_->is_required }
        $self->Sql_columns;
    die "need a $missing attribute to create a Group" if $missing;

    # INSERT the new record into the DB
    $self->SqlInsert( $valid );
}

# Validates a hash-ref of Group data, cleaning it up where appropriate.  If
# the data isn't valid, this method throws a
# Socialtext::Exception::Datavalidation exception.
sub ValidateAndCleanData {
    my ($self, $group, $p) = @_;
    my @errors;
    my @buffer;

    # are we "creating a new group", or "updating an existing group"
    my $is_create = defined $group ? 0 : 1;

    # figure out which attributes are required; they're marked as required but
    # *DON'T* include any attributes that we build lazily (our convention is
    # that lazily built attrs depend on the value of some other attr, so
    # they're not inherently required on their own; they're derived)
    my @required_fields =
        map { $_->name }
        grep { $_->is_required and !$_->is_lazy_build }
        $self->Builds_sql_for->meta->get_all_attributes;

    # new Groups *have* to have a Group Id
    $self->_validate_assign_group_id($p) if ($is_create);

    # new Groups *have* to have a creation date/time
    $self->_validate_assign_creation_datetime($p) if ($is_create);

    # new Groups *have* to have a creating User; default to a system-created
    # Group unless we've been told otherwise.
    $self->_validate_assign_created_by($p) if ($is_create);

    # new Groups *have* to have a primary Account; default unless we've been
    # told otherwise.
    $self->_validate_assign_primary_account($p) if ($is_create);

    # trim fields, removing leading/trailing whitespace
    $self->_validate_trim_values($p);

    $p->{permission_set} ||= 'private' if ($is_create);
    delete $p->{permission_set} unless defined $p->{permission_set};
    if (defined($p->{permission_set}) &&
        $p->{permission_set} !~ /^(?:private|request-to-join|self-join)$/)
    {
        push @errors,
            loc('error.invalid-permission=name', $p->{permission_set});
    }

    # check for presence of required attributes
    foreach my $field (@required_fields) {
        # field is required if either (a) we're creating a new Group record,
        # or (b) we were given a value to update it with
        if ($is_create or exists $p->{$field}) {
            @buffer= $self->_validate_check_required_field($field, $p);
            push @errors, @buffer if (@buffer);
        }
    }

    ### IF DATA FAILED TO VALIDATE, THROW AN EXCEPTION!
    if (@errors) {
        data_validation_error errors => \@errors;
    }
}

sub _validate_assign_group_id {
    my ($self, $p) = @_;
    $p->{group_id} ||= $self->NewGroupId();
    return;
}

sub _validate_assign_creation_datetime {
    my ($self, $p) = @_;
    $p->{creation_datetime} ||= $self->Now();
    return;
}

sub _validate_trim_values {
    my ($self, $p) = @_;

    ($p->{$_} = ($_ eq 'driver_group_name')
        ? Socialtext::String::scrub($p->{$_})
        : Socialtext::String::trim($p->{$_}))
            for grep { !ref($p->{$_}) }
                grep { defined $p->{$_} }
                map  { $_->name }
                $self->Sql_columns;
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

sub _validate_assign_created_by {
    my ($self, $p) = @_;
    # unless we were told who is creating this Group, presume that it's being
    # created by the System-User
    $p->{created_by_user_id} ||= Socialtext::User->SystemUser()->user_id();
    return;
}

sub _validate_assign_primary_account {
    my ($self, $p) = @_;
    # unless we were told which Account this Group was being placed in,
    # presume that its going into the default Account
    $p->{primary_account_id} ||= Socialtext::Account->Default()->account_id();
    return;
}

no Moose::Role;
1;

=head1 NAME

Socialtext::Group::Factory - Group Factory Role

=head1 SYNOPSIS

  use Socialtext::Group;

  # instantiating a Group Factory
  $factory = Socialtext::Group->Factory(driver_key => $driver_key);

=head1 DESCRIPTION

C<Socialtext::Group::Factory> provides an I<abstract> Group Factory Role,
which can be consumed by your own Group Factory implementation.

=head1 METHODS

=over

=item B<$factory-E<gt>driver_key()>

The unique driver key for the Group factory.

=item B<$factory-E<gt>driver_name()>

The driver name, which is calculated from the C<driver_key>.

The driver name indicates which Group Factory type is instantiated (e.g.
"Default", "LDAP", etc).

=item B<$factory-E<gt>driver_id()>

The driver id for the Group Factory, which is calculated from the
C<driver_key>.

The driver id indicates a specific instance of this type of Group Factory.

=item B<$factory-E<gt>cache_lifetime()>

The cache TTL for Groups being managed by this Group Factory, as a
C<DateTime::Duration> object.

No default cache lifetime is provided or defined; you must implement the
C<_build_cache_lifetime()> builder method in your concrete Factory
implementation.

=item B<$factory-E<gt>Available(PARAMS)>

Returns a list-of-hash-refs containing information on the Groups that are
available in the factories underlying data store.  The Groups I<aren't>
instantiated into Group objects, they're I<not> vivified into the system, you
B<just> get a data structure about Groups that exist.  Group data returned is
ordered by "driver_group_name".

By default, this method only returns Groups that have I<already> been loaded
into Socialtext and are known to the system.  Use C<all=E<gt>1> to have the
list also include Groups that exist in the underlying data store but that are
I<not> yet known to Socialtext.

This method accepts the following C<PARAMS>:

=over

=item all => 1

Includes data on Groups that aren't yet known to Socialtext, but that do exist
in the underlying data store.  By default, C<Available()> only returns Groups
that I<have> been loaded into Socialtext.

=back

The hash-refs returned will have the following structure:

=over

=item driver_key

The C<driver_key> for the Factory that contains the Group.

=item driver_group_name

The display name for the Group.

=item driver_unique_id

The unique identifier for the Group as it exists in the underlying data store.
You can later use this C<driver_unique_id> to instantiate the Group.

=item already_created

True if the Group has already been vivified/loaded into Socialtext, false if
the Group I<only> lives within the underlying data store (and has not yet been
loaded into Socialtext).

Unless you have specified C<all=E<gt>1> in your PARAMS, this will always be
true.

=item member_count

The number of Users that exist in the Group in the underlying data store.

For externally sourced Groups, this count may differ from the number of Users
found in the locally cached copy of the Group; the member count returned here
is the count according to the external store, I<not> the locally cached count.

=back

=item B<$factory-E<gt>Create(\%proto_group)>

Attempts to create a new Group object in the data store, using the information
provided in the given C<\%proto_group> hash-ref.

Factories consuming this Role B<MUST> implement this method, and are
responsible for ensuring that they are doing proper validation/cleaning of the
data prior to creating the Group.

If your Factory is read-only and is not updateable, simply implement a stub
method which throws an exception to indicate error.

=item B<$factory-E<gt>CreateInitialRelationships($proto_or_homey)>

Creates the initial Account/Creator relationships for the Group defined by the
provided C<$proto_or_homey> (which is either a C<$proto_group> or a Group
Homunculus object).

This method is called I<automatically> by:

=over

=item *

C<Socialtext::Group-E<gt>Create()>, when creating a new Group object, to
handle cases where the Group is explicitly created in a data store.

=item *

C<Socialtext::Group::Factory-E<gt>GetGroupHomunculus()>, when auto-vivifying a
Group that lives in an external store.

=back

As such, there should be B<NO> need for you to call this method directly.

=item B<$factory-E<gt>Update($group, \%proto_group)>

Updates the C<$group> with the information provided in the C<\%proto_group>
hash-ref.

Factories consuming this Role B<MUST> implement this method, and are
responsible for ensuring that they are doing proper validation/cleaning of the
data prior to updating the underlying data store.

If your Factory is read-only and is not updateable, simply implement a stub
method which throws an exception to indicate error.

=item B<$factory-E<gt>can_update_store()>

Returns true if the data store behind this Group Factory is updateable,
returning false if the data store is read-only.

Factories consuming this Role B<MUST> implement this method to indicate if
they're updateable or not.

=item B<$factory-E<gt>is_cacheable()>

Returns true if we should be caching Group data fetched from the underlying
data store.

Factories consuming this Role B<MUST> implement this method to indicate if
they should be cached or not.

=item B<$factory-E<gt>GetGroupHomunculus(%proto_group)>

Retrieves the Group record from the local DB, turns it into a Group Homunculus
object, and returns that Group Homunculus back to the caller.

The Group record found in the DB is subject to freshness checks, and if it is
determined that the Group data is stale the Factory will be asked to refresh
the Group from its underlying data store (and the local cached copy will be
updated accordingly).

=item B<$factory-E<gt>UpdateGroupRecord(\%proto_group)>

Updates an existing Group record in the local DB store, based on the
information provided in the C<\%proto_group> hash-ref.

This C<\%proto_group> hash-ref B<MUST> contain the C<group_id> of the Group
record that we are updating in the DB.

The C<cached_at> time for the record will be updated to "now" by default.  If
you wish to preserve the existing C<cached_at> time, be sure to pass that in
as part of the data in C<\%proto_group>.

=item B<$factory-E<gt>Delete($group)>

Deletes a Group object from the local DB store.

This is just a helper method which calls C<$factory-E<gt>DeleteGroupRecord()>
under the hood.

=item B<$factory-E<gt>DeleteGroupRecord(\%proto_group)>

Deletes a Group record from the local DB store, based on the informaiton
provided in the C<\%proto_group> hash-ref.

This C<\%proto_group> hash-ref B<MUST> contain the C<group_id> of the Group
record that we are deleting in the DB.

Deletion is B<ONLY> performed for the local DB representation of the Group.
In the case of externally sourced Groups (e.g. LDAP), B<no> deletion is pushed
out to the external data store.  This allows for us to delete the local
representation of the Group, without actually destroying the original external
Group definition.

This method returns true on success, false on failure.

=item B<$factory-E<gt>ExpireGroupRecord(group_id =E<gt> $group_id)>

Expires the Group in our local DB.  Next time the Group is instantiated, the
Factory managing for the Group will refresh the Group information from its
data store.

=item B<$factory-E<gt>Now()>

Returns the current date/time in hi-res, as a C<DateTime> object.

=item B<$factory-E<gt>NewGroupHomunculus(\%proto_group)>

Creates a new Group Homunculus object based on the information provided in the
C<\%proto_group> hash-ref.

The C<\%proto_group> B<must> contain all of the attributes required for the
Group Homunculus to be instantiated, for that specific Homunculus type.

=item B<$factory-E<gt>NewGroupId()>

Returns a new unique Group Id.  Id returned is B<guaranteed> to be unique.

=item B<$factory-E<gt>NewGroupRecord(\%proto_group)>

Creates a new Group record in the local DB store, based on the information
provided in the C<\%proto_group> hash-ref.

A unique C<group_id> will be calculated for the Group if one is not available
in the C<\%proto_group>.

Groups default to being C<cached_at> "now", unless specified otherwise in the
C<\%proto_group>.

=item B<$factory-E<gt>ValidateAndCleanData($group, \%proto_group)>

Validates the data provided in the C<\%proto_group> hash-ref, with respect to
any existing C<$group> that we may (or may not) be updating.

If a C<$group> is provided, validation is performed as "we are updating that
Group with the data provided in the C<\%proto_group>".

If no C<$group> is provided, validation is performed as "we are validating
data for the purpose of creating a new Group".

In the event of error, this method throws a
C<Socialtext::Exception::DataValidation> error.

Validation/cleanup performed:

=over

=item *

New Groups must have a C<group_id>, and a unique Group Id is calculated
automatically if it is not provided.

Only applicable if you are I<creating> a new Group; if you are updating a
Group it is presumed that you already have a unique Group Id for the Group.

=item *

New Groups must have a <creation_datetime>, which defaults to "now" unless
provided.

Only applicable if you are I<creating> a new Group.

=item *

New Groups must have a <created_by_user_id>, which defaults to "the System
User" unless provided.

Only applicable if you are I<creating> a new Group.

=item *

All attributes are trimmed of leading/trailing whitespace.

=item *

Check for presence of all required attributes, as defined by the Group
Homunculus.

When creating a new Group, validation is performed against the baseline set of
attributes as defined in C<Socialtext::Group::Homunculus>.

When updating an existing Group, validation is performed against the
attributes defined by the provided Group Homunculus object.

=back

=back

=head1 IMPLEMENTING A GROUP FACTORY

In order to consume this Group Factory Role and implement a concrete Group
Factory, you need to provide implementations for the following methods:

=over

=item Available(PARAM)

=item Create(\%proto_group)

=item Update($group, \%proto_group)

=item can_update_store()

=item is_cacheable()

=item _build_cache_lifetime()

=item _lookup_group(\%proto_group)

=back

Please refer to the L</METHODS> section above for more information on how
these methods are intended to behave.

=head1 AUTHOR

Socialtext, Inc.,  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc.,  All Rights Reserved.

=cut
