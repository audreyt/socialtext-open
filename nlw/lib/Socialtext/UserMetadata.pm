package Socialtext::UserMetadata;
# @COPYRIGHT@
use Moose;
use Socialtext::Cache;
use Socialtext::Exceptions qw( data_validation_error param_error );
use Socialtext::Role;
use Socialtext::SQL 'sql_execute';
use Socialtext::SQL::Builder qw(sql_insert);
use Socialtext::Validate qw( validate SCALAR_TYPE BOOLEAN_TYPE ARRAYREF_TYPE 
                             WORKSPACE_TYPE );
use DateTime;
use DateTime::Format::Pg;
use Readonly;
use namespace::clean -except => 'meta';

our $VERSION = '0.01';

has 'user_id'                 => (is => 'rw', isa => 'Int');
has 'creation_datetime'       => (is => 'rw', isa => 'Str');
has 'last_login_datetime'     => (is => 'rw', isa => 'Str');
has 'email_address_at_import' => (is => 'rw', isa => 'Maybe[Str]');
has 'created_by_user_id'      => (is => 'rw', isa => 'Maybe[Int]');
has 'is_business_admin'       => (is => 'rw', isa => 'Bool');
has 'is_technical_admin'      => (is => 'rw', isa => 'Bool');
has 'is_system_created'       => (is => 'rw', isa => 'Bool');
has 'primary_account_id'      => (is => 'rw', isa => 'Int');

Readonly our @fields => qw(
    user_id
    creation_datetime
    last_login_datetime
    email_address_at_import
    created_by_user_id
    is_business_admin
    is_technical_admin
    is_system_created
    primary_account_id
);

sub user_set_id { $_[0]->user_id }

sub create_if_necessary {
    my $class = shift;
    my $user = shift;

    my $md = $class->new(user_id => $user->user_id);
    return $md if $md;

    # If we're here, it's because either:
    #  - we've got authenticated user credentials from outside 
    #    our own system
    #  - we're bootstrapping the system with the system-user

    my $created_by_user_id = $user->username eq 'system-user'
        ? undef
        : Socialtext::User->SystemUser->user_id;

    return $class->create(
        user_id                 => $user->user_id,
        email_address_at_import => $user->email_address,
        created_by_user_id      => $created_by_user_id
    );
}

# turn a user into a hash suitable for JSON and
# such things.
sub to_hash {
    my $self = shift;
    my %hash = map { $_ => $self->$_ } qw(
        user_id
        creation_datetime
        last_login_datetime
        email_address_at_import
        created_by_user_id
        is_business_admin
        is_technical_admin
        is_system_created
        primary_account_id
    );
    return \%hash;
}

sub _cache {
    return Socialtext::Cache->cache('user_metadata');
}

sub new {
    my ( $class, %p ) = @_;

    my $cache = $class->_cache();
    my $key   = $p{user_id};

    my $metadata = $cache->get($key);
    my $got = defined $metadata;
    if (!$got) {
        my $sth = sql_execute(
            'SELECT * FROM "UserMetadata" WHERE user_id=?',
            $key
        );
        $metadata = $sth->fetchrow_hashref;
        return unless $metadata;
    }

    my $self = $class->meta->new_object(%$metadata);
    $cache->set($key, $metadata) unless $got;
    return $self;
}

sub create {
    my ( $class, %p ) = @_;

    require Socialtext::Account;        # lazy-load, to reduce startup impact

    $class->_validate_and_clean_data(%p);
    my %defaults = (
        primary_account_id => Socialtext::Account->Default->account_id,
        is_business_admin  => 0,
        is_technical_admin => 0,
        is_system_created  => 0,
    );
    my %insert_args =
        map  { $_ => $p{$_} }
        grep { exists $p{$_} }
        @fields;
    foreach my $key (keys %defaults) {
        $insert_args{$key} = $defaults{$key} unless defined $insert_args{$key};
    }

    sql_insert('"UserMetadata"', \%insert_args);

    # re-fetches out of the db
    my $self = $class->new(user_id => $insert_args{user_id});

    # Add the User to their Primary Account.
    #
    # Watch out, though... unit-tests may set up crazy scenarios where we've
    # got User Homunculus objects that have *no* UserMetadata, and that during
    # cleanup we try to instantiate a User object (which in turn tries to
    # create a new UserMetadata object for said User).  That User, though, may
    # have Roles in the Account already (so don't create a new one if the User
    # has one already).
    my $acct = Socialtext::Account->new(
        account_id => $self->primary_account_id);
    my $is_system_user = $insert_args{is_system_created};
    unless ($is_system_user or $acct->has_user($self, direct => 1)) {
        $acct->add_user(
            user  => $self,
            actor => $self->creator,
            role  => Socialtext::Role->Member(),
        );
    }

    my $adapter = Socialtext::Pluggable::Adapter->new;
    $adapter->make_hub(Socialtext::User->SystemUser(), undef);
    $adapter->hook('nlw.add_user_account_role', [$acct, $self]);

    return $self;
}

# "update" methods: set_technical_admin, set_business_admin,
# set_primary_account_id
sub set_technical_admin {
    my ($self, $value) = @_;
    $self->_update_field('is_technical_admin=?', $value);
    $self->is_technical_admin( $value );
    return $self;
}

sub set_business_admin {
    my ( $self, $value ) = @_;
    $self->_update_field('is_business_admin=?', $value);
    $self->is_business_admin( $value );
    return $self;
}

sub set_primary_account_id {
    my ($self,$value) = @_;
    $self->_update_field('primary_account_id=?', $value);
    $self->primary_account_id($value);
    return $self;
}

before 'set_business_admin', 'set_technical_admin' => sub {
    my $self = shift;
    die "Cannot give system-admin privileges to a system user!\n"
        if $self->is_system_created;
};

sub record_login { shift->_update_field('last_login_datetime=CURRENT_TIMESTAMP') }

sub _update_field {
    my $self = shift;
    my $field = shift;
    $self->_cache->remove($self->user_id);
    sql_execute(
        qq{UPDATE "UserMetadata" SET $field WHERE user_id=?},
        @_, $self->user_id );
}

sub creation_datetime_object {
    my $self = shift;

    return DateTime::Format::Pg->parse_timestamptz( $self->creation_datetime );
}

sub last_login_datetime_object {
    my $self = shift;

    return DateTime::Format::Pg->parse_timestamptz( $self->last_login_datetime );
}

sub creator {
    my $self = shift;

    my $created_by_user_id = $self->created_by_user_id;

    unless (defined $created_by_user_id) {
        return Socialtext::User->SystemUser;
    }

    return Socialtext::User->new( user_id => $created_by_user_id );
}

sub _validate_and_clean_data {
    my $self = shift;
    my $p = shift;
    my $metadata;

    my $is_create = ref $self ? 0 : 1;

    my @errors;
    if ( not $is_create and $p->{is_system_created} ) {
        push @errors,
            "You cannot change is_system_created for a user after it has been created.";
    }

    data_validation_error errors => \@errors if @errors;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

__END__

=head1 NAME

Socialtext::UserMetadata - A storage object for user metadata

=head1 SYNOPSIS

  use Socialtext::UserMetadata;

  my $md = Socialtext::UserMetadata->new( user_id => 5 );

  my $md = Socialtext::UserMetadata->create_if_necessary( $user );

  my $md = Socialtext::UserMetadata->create( );

=head1 DESCRIPTION

This class provides methods for dealing with data from the UserMetadata
table. Each object represents a single row from the table.

=head1 METHODS

=head2 Socialtext::UserMetadata->new(PARAMS)

Looks for existing user metadata matching PARAMS and returns a
C<Socialtext::UserMetadata> object representing that metadata if it
exists.

=head2 Socialtext::UserMetadata->create(PARAMS)

Attempts to create a user metadata record with the given information and
returns a new C<Socialtext>::UserMetadata object.

PARAMS can include:

=over 4

=item * user_id - required

=item * email_address_at_import - required

=item * created_by_user_id - defaults to Socialtext::User->SystemUser()->user_id()

=back

=head2 Socialtext::UserMetadata->create_if_necessary( $user )

Attempt to retrieve metadata information for $user, if it exists, otherwise,
use information obtained from $user to satisfy a newly created row, and return
it. This is particularly useful when user information is obtained outside the
RDBMS.

$user is typically an instance of one of the Socialtext::User user factories.

=head2 $md->creation_datetime()

=head2 $md->last_login_datetime()

=head2 $md->created_by_user_id()

=head2 $md->is_business_admin()

=head2 $md->is_technical_admin()

=head2 $md->is_system_created()

Returns the corresponding attribute for the user metadata.

=head2 $md->to_hash()

Returns a hash reference representation of the metadata, suitable for using
with JSON, YAML, etc.  

=head2 $md->set_technical_admin($value)

Updates the is_technical_admin for the metadata to $value (0 or 1).

=head2 $md->set_business_admin($value)

Updates the is_business_admin for the metadata to $value (0 or 1).

=head2 $md->record_login()

Updates the last_login_datetime for the metadata to the current datetime.

=head2 $md->creation_datetime_object()

Returns a new C<DateTime.pm> object for the user's creation datetime.

=head2 $md->last_login_datetime_object()

Returns a new C<DateTime.pm> object for the user's last login
datetime. This may be a C<DateTime::Infinite::Past> object if the user
has never logged in.

=head2 $md->creator()

Returns a C<Socialtext::User> object for the user which created this
user.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc., All Rights Reserved.

=cut
