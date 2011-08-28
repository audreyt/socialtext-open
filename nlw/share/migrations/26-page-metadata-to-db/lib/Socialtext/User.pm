# @COPYRIGHT@
package Socialtext::User;
use strict;
use warnings;

our $VERSION = '0.01';

use Socialtext::Exceptions qw( data_validation_error param_error );
use Socialtext::Validate qw( validate SCALAR_TYPE BOOLEAN_TYPE ARRAYREF_TYPE WORKSPACE_TYPE USER_TYPE);
use Socialtext::AppConfig;
use Socialtext::MultiCursor;
use Socialtext::SQL 'sql_execute';
use Socialtext::TT2::Renderer;
use Socialtext::URI;
use Socialtext::UserMetadata;
use Socialtext::UserId;
use Socialtext::User::Deleted;
use Socialtext::User::EmailConfirmation;
use Socialtext::User::Default::Factory qw($SystemUsername $GuestUsername);
use Socialtext::Workspace;
use Email::Address;
use Class::Field 'field';
use Socialtext::l10n qw(system_locale loc);
use Socialtext::EmailSender::Factory;
use Socialtext::User::Cache;
use Socialtext::Timer;
use base qw( Socialtext::MultiPlugin );

use Readonly;

field 'homunculus';
field 'metadata';
field 'user_id', -init => '$self->_system_unique_id()';

my @user_store_interface =
    qw( username email_address password first_name last_name );
my @user_metadata_interface =
    qw( creation_datetime last_login_datetime email_address_at_import
        created_by_user_id is_business_admin is_technical_admin
        is_system_created);
my @minimal_interface
    = ( 'user_id', @user_store_interface, @user_metadata_interface );

sub minimal_interface {
    my $class = shift;
    return @minimal_interface;
}

sub base_package {
    return __PACKAGE__;
}

sub _drivers {
    my $class = shift;
    my $drivers = Socialtext::AppConfig->user_factories();
    return split /;/, $drivers;
}

sub _realize {
    # OVER-RIDDEN; we need an object-based plugin factory, not a class-based
    # one.
    my $class  = shift;
    my $driver = shift;
    my $method = shift;
    my ($driver_name, $driver_id) = split /:/, $driver;
    my $real_class = join '::', $class->base_package, $driver_name, 'Factory';
    eval "require $real_class";
    die "Couldn't load $real_class: $@" if $@;

    if ($real_class->can($method)) {
        return $real_class->new($driver_id);
    }

    return undef;
}

sub new_homunculus {
    my $class = shift;
    my $key = shift;
    my $val = shift;
    my $homunculus;

    # if we are passed in an email confirmation hash, we look up the user_id
    # associated with that hash
    if ($key eq 'email_confirmation_hash') {
        my $user_id = Socialtext::User::EmailConfirmation->id_from_hash($val);
        return undef unless defined $user_id;
        $key = 'user_id'; $val = $user_id;
    }

    $homunculus = Socialtext::User::Cache->Fetch($key, $val);
    return $homunculus if $homunculus;

    # if we pass in user_id, it will be one of the new system-wide
    # ids, we must short-circuit and immediately go to the driver
    # associated with that system id
    if ($key eq 'user_id') {
        my $system_id = Socialtext::UserId->new(system_unique_id => $val);
        return undef unless $system_id;
        my $driver_key = $system_id->driver_key;
        my $driver_username = $system_id->driver_username;
        my $driver = $class->_realize($driver_key, 'GetUser');
        if ($driver) {
            # if driver doesn't exist any more, we don't have an instance of
            # it to query.  e.g. customer removed an LDAP data store.
            $homunculus = $driver->GetUser( username => $driver_username );
        }
        $homunculus ||= Socialtext::User::Deleted->new(
            user_id    => $system_id->driver_unique_id,
            username   => $driver_username,
            driver_key => $driver_key,
        );
    }
    # searches by "driver_unique_id" get handled as searches for "user_id", but
    # mapped accordingly for each user factory driver.
    elsif ($key eq 'driver_unique_id') {
        $homunculus = $class->_first('GetUser', 'user_id' => $val );
    }
    # system generated users MUST come from the Default user store; we don't
    # allow for them to live anywhere else.
    #
    # this prevents possible conflict with other stores having their own
    # notion of what the "guest" or "system-user" is (e.g. Active Directory
    # and its "Guest" user)
    elsif (Socialtext::User::Default::Factory->IsDefaultUser($key => $val)) {
        my $factory = $class->_realize('Default', 'GetUser');
        $homunculus = $factory->GetUser($key => $val, @_);
    }
    else {
        $homunculus = $class->_first('GetUser', $key => $val, @_);
    }

    Socialtext::User::Cache->Store($key, $val, $homunculus);
    return $homunculus;
}

sub new {
    my $class = shift;
    my $user = bless {}, $class;

    Socialtext::Timer->Continue('user_new');

    my $homunculus = $class->new_homunculus(@_);
    Socialtext::Timer->Pause('user_new');
    return undef unless $homunculus;

    Socialtext::Timer->Continue('user_new');

    # ensure this user is present in our UserId table
    my $userid = Socialtext::UserId->create_if_necessary($homunculus);

    $user->homunculus($homunculus);
    $user->metadata(Socialtext::UserMetadata->create_if_necessary($user));

    # proactively cache the homunculus, but only if it's not already
    # cached
    Socialtext::User::Cache->MaybeStore(
        'user_id', $userid->system_unique_id => $homunculus
    );

    # store the user_id since we've got it at hand (preventing frequent
    # expensive lookups later)
    $user->user_id($userid->system_unique_id);

    Socialtext::Timer->Pause('user_new');

    return $user;
}

sub create {
    my $class = shift;

    # username email_address password first_name last_name
    my %p = @_;
    my $homunculus = $class->_first( 'create', %p );

    my $system_unique_id = Socialtext::UserId->create(
        driver_key       => $homunculus->driver_key,
        driver_unique_id => $homunculus->user_id,
        driver_username  => $homunculus->username,
    )->system_unique_id();

    if ( !exists $p{created_by_user_id} ) {
        if ( $homunculus->username ne $SystemUsername ) {
            my $s_u_homunculus = $class->new_homunculus( username => $SystemUsername );
            my $driver_key = $s_u_homunculus->driver_key;
            my $driver_unique_id = $s_u_homunculus->user_id;
            $p{created_by_user_id} = Socialtext::UserId->new(
                driver_key       => $driver_key,
                driver_unique_id => $driver_unique_id
            )->system_unique_id;
        }
    }
    my $user = bless {}, $class;
    $user->homunculus( $homunculus );
    # scribble UserMetadata
    my %metadata_p = map { $_ => $p{$_} } keys %p; #@user_metadata_interface;;
    $metadata_p{user_id}                 = $system_unique_id;
    $metadata_p{email_address_at_import} = $user->email_address;
    my $metadata = Socialtext::UserMetadata->create(%metadata_p);
    $user->metadata( $metadata );

    return $user;
}

sub SystemUser {
    return shift->new( username => $SystemUsername );
}

sub Guest {
    return shift->new( username => $GuestUsername );
}

sub can_update_store {
    my $self = shift;
    my $homunculus_class = $self->base_package() . "::" . $self->driver_name;
    return $homunculus_class->can('update') ? 1 : undef;
}

sub update_store {
    my $self = shift;
    my %p = @_;
    return $self->homunculus->update( %p );
}

sub recently_viewed_workspaces {
    my $self = shift;
    my $limit = shift || 10;
    Socialtext::Timer->Continue('user_ws_recent');
    my $sth = sql_execute(q{
        SELECT name as workspace_name,
               last_edit
        FROM (
            SELECT distinct page_workspace_id,
                   MAX(at) AS last_edit
              FROM event
             WHERE actor_id = ?
               AND event_class = 'page'
               AND action = 'view'
             GROUP BY page_workspace_id
             ORDER BY last_edit DESC
             LIMIT ?
        ) AS X
        JOIN "Workspace"
          ON workspace_id = page_workspace_id
        ORDER BY last_edit DESC
    }, $self->user_id, $limit);

    my @viewed;
    while (my $row = $sth->fetchrow_hashref) {
        push @viewed, [$row->{workspace_name}, $row->{workspace_title}];
    }
    Socialtext::Timer->Pause('user_ws_recent');
    return @viewed;
}

sub _system_unique_id {
    my $self = shift;
    return Socialtext::UserId->new(
        driver_key       => $self->homunculus->driver_key,
        driver_unique_id => $self->homunculus->user_id
    )->system_unique_id();
}

sub username {
    $_[0]->homunculus->username( @_[ 1 .. $#_ ] );
}

sub password {
    $_[0]->homunculus->password( @_[ 1 .. $#_ ] );
}

sub email_address {
    $_[0]->homunculus->email_address( @_[ 1 .. $#_ ] );
}

sub first_name {
    my $firstname = $_[0]->homunculus->first_name( @_[ 1 .. $#_ ] );
    Encode::_utf8_on($firstname) unless Encode::is_utf8($firstname);
    return $firstname;
}

sub last_name {
    my $lastname = $_[0]->homunculus->last_name( @_[ 1 .. $#_ ] );
    Encode::_utf8_on($lastname) unless Encode::is_utf8($lastname);
    return $lastname;
}

sub password_is_correct {
    $_[0]->homunculus->password_is_correct( @_[ 1 .. $#_ ] );
}

sub has_valid_password {
    $_[0]->homunculus->has_valid_password( @_[ 1 .. $#_ ] );
}

sub driver_name {
    $_[0]->homunculus->driver_name( @_[ 1 .. $#_ ] );
}

# Metadata delegates

sub email_address_at_import {
    $_[0]->metadata->email_address_at_import( @_[ 1 .. $#_ ] );
}

sub creation_datetime {
    $_[0]->metadata->creation_datetime( @_[ 1 .. $#_ ] );
}

sub last_login_datetime {
    $_[0]->metadata->last_login_datetime( @_[ 1 .. $#_ ] );
}

sub created_by_user_id {
    $_[0]->metadata->created_by_user_id( @_[ 1 .. $#_ ] );
}

sub is_business_admin {
    $_[0]->metadata->is_business_admin( @_[ 1 .. $#_ ] );
}

sub is_technical_admin {
    $_[0]->metadata->is_technical_admin( @_[ 1 .. $#_ ] );
}

sub is_system_created {
    $_[0]->metadata->is_system_created( @_[ 1 .. $#_ ] );
}

sub set_technical_admin {
    $_[0]->metadata->set_technical_admin( @_[ 1 .. $#_ ] );
}

sub set_business_admin {
    $_[0]->metadata->set_business_admin( @_[ 1 .. $#_ ] );
}

sub record_login {
    $_[0]->metadata->record_login( @_[ 1 .. $#_ ] );
}

sub creation_datetime_object {
    $_[0]->metadata->creation_datetime_object( @_[ 1 .. $#_ ] );
}

sub last_login_datetime_object {
    $_[0]->metadata->last_login_datetime_object( @_[ 1 .. $#_ ] );
}

sub creator {
    $_[0]->metadata->creator( @_[ 1 .. $#_ ] );
}

sub accounts {
    my $self = shift;
    my %p = @_;
    my $plugin = delete $p{plugin};

    require Socialtext::Account;
    my @args = ($self->user_id);
    my $sql;

    Socialtext::Timer->Continue('user_accts');

    if ($plugin) {
        $sql = q{
            SELECT DISTINCT account_id 
            FROM account_user JOIN account_plugin USING (account_id)
            WHERE user_id = ? AND plugin = ?
        };
        push @args, $plugin;
    }
    else {
        $sql = q{
            SELECT DISTINCT account_id 
            FROM account_user WHERE user_id = ?
        };
    }

    my $sth = sql_execute($sql, @args);
    my @accounts;
    while (my ($account_id) = $sth->fetchrow_array()) {
        push @accounts, Socialtext::Account->new(account_id => $account_id);
    }
    @accounts = sort {$a->name cmp $b->name} @accounts;

    Socialtext::Timer->Pause('user_accts');

    return (wantarray ? @accounts : \@accounts);
}

sub shared_accounts {
    my ($self, $user) = @_;
    my %mine = map { $_->account_id => 1 } $self->accounts;
    return grep { $mine{$_->account_id} } $user->accounts;
}

{
    # REVIEW - maybe this is overkill and can be handled through good
    # documentation saying "you probably don't want to delete users,
    # we mean it."
    Readonly my $spec => { force => BOOLEAN_TYPE( default => 0 ) };
    sub delete {
        my $self = shift;
        my %p = validate( @_, $spec );

        Socialtext::Exception->throw( error => 'You cannot delete a user.' )
            unless $p{force};

        # We have three things to delete: Our store, our metadata, and our id.
        #
        # User stores should implement a delete method, even if it is a noop.
        #
        Socialtext::UserId->new( system_unique_id => $self->user_id )
            ->delete();
        $self->homunculus->delete();
        $self->metadata->delete();
    }
}

sub to_hash {
    my $self = shift;
    my $hash = {};
    foreach my $attr ( @minimal_interface ) {
        my $value = $self->$attr;
        $value = "" unless defined $value;
        $hash->{$attr} = "$value";
    }
    $hash->{creator_username} = $self->creator->username;

    return $hash;
}

sub Create_user_from_hash {
    my $class = shift;
    my $info = shift;

    my $creator
        = Socialtext::User->new( username => $info->{creator_username} );
    $creator ||= Socialtext::User->SystemUser();

    my %create;
    for my $c (@minimal_interface) {
        $create{$c} = $info->{$c}
            if exists $info->{$c};
    }

    # Bug 342 - some backups have been created with users
    # that don't have usernames.  We shouldn't let this
    # break the import
    if ($create{first_name} eq 'Deleted') {
        $create{username} ||= 'deleted-user';
    }

    my $user = Socialtext::User->create(
        %create,
        created_by_user_id => $creator->user_id,
        no_crypt           => 1,
    );
    return $user;
}

sub _get_full_name {
    my $full_name;
    my $first_name = shift;
    my $last_name = shift;

    if (system_locale() eq 'ja') {
        $full_name = join ' ', grep { defined and length }
            $last_name, $first_name;
    }
    else {
        $full_name = join ' ', grep { defined and length }
        $first_name, $last_name;
    }
    return $full_name;
}


{
    Readonly my $spec => { workspace => WORKSPACE_TYPE( default => undef ) };
    sub best_full_name {
        my $self = shift;
        my %p = validate( @_, $spec );

        my $name = _get_full_name($self->first_name, $self->last_name);

        return $name if length $name;

        return $self->email_address 
            unless ($p{workspace} && $p{workspace}->workspace_id != 0);

        return $self->_masked_email_address($p{workspace});
    }
}

{
    Readonly my $spec => {
        workspace => WORKSPACE_TYPE( default => undef ),
        user => USER_TYPE( default => undef ),
    };
    sub masked_email_address {
        my $self = shift;
        my %p = validate( @_, $spec );
        my $workspace = $p{workspace};
        my $user = $p{user};

        die "Either workspace or user is required"
            unless $user or $workspace && $workspace->real;

        my $email = $self->email_address;
        my $hidden = 1;

        if ($user) {
            if ($user->user_id == $self->user_id) {
                $hidden = 0;
            }
            else {
                my @accounts = $self->shared_accounts($user);
                for my $account (@accounts) {
                    $hidden = 0 unless $account->email_addresses_are_hidden;
                }
            }
        }
        
        # Reset hidden based on workspace permissions if the domain doesn't
        # match the unmasked domain param
        if ($workspace) {
            my $unmasked_domain = $workspace->unmasked_email_domain;
            unless ($unmasked_domain and $email =~ /\@\Q$unmasked_domain\E/) {
                $hidden = 1 if $workspace->email_addresses_are_hidden;
            }
        }

        $email =~ s/\@.+$/\@hidden/ if $hidden;
        return $email;
    }
}

# REVIEW - in the old code, this always returned the unmasked address
# if the viewing user was a workspace admin
sub _masked_email_address {
    my $self = shift;
    my $workspace = shift;

    return $self->MaskEmailAddress( $self->email_address, $workspace );
}

sub MaskEmailAddress {
    my ( $class, $email, $workspace ) = @_;

    return $email unless $workspace->email_addresses_are_hidden;

    my $unmasked_domain = $workspace->unmasked_email_domain;
    unless ( $unmasked_domain &&
             $email =~ /\@\Q$unmasked_domain\E/ ) {
        $email =~ s/\@.+$/\@hidden/;
    }

    return $email;
}

sub name_and_email {
    my $self = shift;

    return __PACKAGE__->FormattedEmail( $self->first_name, $self->last_name,
        $self->email_address );
}

sub FormattedEmail {
    my ( $class, $first_name, $last_name, $email_address ) = @_;

    my $name = _get_full_name($first_name, $last_name);

    # Dave suggested this improvement, but many of our templates anticipate
    # the previous format, so is being temporarily reverted
    # return Email::Address->new($name, $email_address)->format;

    if ( length $name ) {
            return $name . ' <' . $email_address . '>';
    }
    else {
            return $email_address;
    }
}

sub guess_sortable_name {
    my $self = shift;
    my $name;

    my $fn = $self->first_name || '';
    my $ln = $self->last_name || '';
    if ($self->email_address eq $fn) {
        $fn =~ s/\@.+$//;
    }

    # Desired result: sort is caseless and alphabetical by first name -- {bz: 1246}
    $name = "$fn $ln";
    $name =~ s/^\s+//;
    $name =~ s/\s+$//;
    # TODO: unicode casefolding?
    return $name if length $name;

    return $self->_guess_nonreal_name;
}

sub guess_real_name {
    my $self = shift;
    my $name;

    my $fn = $self->first_name;
    if ($self->email_address eq $fn) {
        $fn =~ s/\@.+$//;
    }

    $name = _get_full_name($fn, $self->last_name);
    $name =~ s/^\s+//;
    $name =~ s/\s+$//;
    return $name if length $name;
    return $self->_guess_nonreal_name;
}

sub _guess_nonreal_name {
    my $self = shift;
    my $name = $self->username || '';
    $name =~ s/\@.+$//;
    $name =~ s/[[:punct:]]+/ /g;
    $name =~ s/^\s+//;
    $name =~ s/\s+$//;
    return $name if length $name;

    $name = $self->email_address;
    $name =~ s/\@.+$//;
    $name =~ s/[[:punct:]]+/ /g;
    $name =~ s/^\s+//;
    $name =~ s/\s+$//;
    return $name;
}

sub workspace_count {
    my $self = shift;

    my $sth = sql_execute(
        'SELECT count(distinct(workspace_id))'
        . ' FROM "UserWorkspaceRole"'
        . ' WHERE user_id=?',
        $self->user_id );

    return $sth->fetchall_arrayref->[0][0];
}

sub workspaces_with_selected {
    my $self = shift;

    my $sth = sql_execute(<<EOSQL, $self->user_id);
SELECT uwr.workspace_id
    FROM "UserWorkspaceRole" uwr, "Workspace" w
    WHERE uwr.user_id=? AND uwr.workspace_id = w.workspace_id
    ORDER BY w.name
EOSQL

    return Socialtext::MultiCursor->new(
        iterables => [ $sth->fetchall_arrayref ],
        apply     => sub {
            my $row          = shift;
            my $workspace_id = $row->[0];

            return undef unless defined $workspace_id;

            return [
                Socialtext::Workspace->new( workspace_id => $workspace_id ),
                Socialtext::UserWorkspaceRole->new(
                    user_id      => $self->user_id,
                    workspace_id => $workspace_id
                    )
            ];
        }
    );
}

{
    Readonly my $spec => { workspace => WORKSPACE_TYPE };
    sub workspace_is_selected {
        my $self = shift;
        my %p = validate( @_, $spec );

        my $sth = sql_execute(
            'SELECT is_selected'
            . ' FROM "UserWorkspaceRole"'
            . ' WHERE user_id=? AND workspace_id=?',
            $self->user_id, $p{workspace}->workspace_id );

        return $sth->fetchall_arrayref->[0][0];
    }
}

{
    Readonly my $spec => { workspaces => ARRAYREF_TYPE };
    sub set_selected_workspaces {
        my $self = shift;
        my %p = validate( @_, $spec );

        my $workspaces = $self->workspaces();

        my %selected = map { $_->workspace_id => 1 } @{ $p{workspaces} };
        while ( my $ws = $workspaces->next ) {
            sql_execute(
                'UPDATE "UserWorkspaceRole"'
                . ' SET is_selected=?'
                . ' WHERE user_id=? AND workspace_id=?',
                $selected{ $ws->workspace_id } ? 1 : 0,
                $self->user_id, $ws->workspace_id );
        }
    }
}

{
    Readonly my $spec => {
        selected_only => BOOLEAN_TYPE( default => 0 ),
        exclude => ARRAYREF_TYPE( default => [] ),
    };
    sub workspaces {
        my $self = shift;
        my %p = validate( @_, $spec );

        my $selected_only_clause
            = $p{selected_only} ? 'AND is_selected = TRUE' : '';

        my $exclude_clause = '';
        if (@{ $p{exclude} }) {
            my $wksps = join(',', @{ $p{exclude} });
            $exclude_clause = "AND workspace_id NOT IN ($wksps)";
        }

        my $sth = sql_execute(<<EOSQL, $self->user_id);
SELECT workspace_id
    FROM "UserWorkspaceRole" LEFT OUTER JOIN "Workspace" USING (workspace_id)
    WHERE user_id=?
    $selected_only_clause
    $exclude_clause
    ORDER BY name
EOSQL

        return Socialtext::MultiCursor->new(
            iterables => [ $sth->fetchall_arrayref ],
            apply => sub {
                my $row = shift;
                return Socialtext::Workspace->new( workspace_id => $row->[0] );
            }
        );
    }
}

sub is_authenticated {
    my $self = shift;

    return 1
        if $self->username() ne $GuestUsername
           and $self->has_valid_password()
            and not $self->requires_confirmation();

    return 0;
}

sub is_guest {
    return not $_[0]->is_authenticated()
}

sub is_deleted {
    return ref $_[0]->homunculus eq 'Socialtext::User::Deleted';
}

sub default_role {
    my $self = shift;

    return Socialtext::Role->AuthenticatedUser()
        if $self->is_authenticated();

    return Socialtext::Role->Guest();
}

# Class methods

{
    Readonly my $spec => { password => SCALAR_TYPE };
    sub ValidatePassword {
        shift;
        my %p = validate( @_, $spec );

        return ( loc("Passwords must be at least 6 characters long.") )
            unless length $p{password} >= 6;

        return;
    }
}

# helper apply functions
# by workspace count apply
my $by_workspace_count_apply = sub {
    my $rows             = shift;
    my $system_unique_id = $rows->[0];

    # short circuit to not hand back undefs in a list context
    return ( defined $system_unique_id )
      ?  Socialtext::User->new( user_id => $system_unique_id )
        : undef;
};

# by creator apply
my $by_creator_apply = sub {
    my $rows             = shift;
    my $system_unique_id = $rows->[0];

    # short circuit to not hand back undefs in a list context
    return ( defined $system_unique_id )
      ?  Socialtext::User->new( user_id => $system_unique_id )
        : undef;
};

# by workspace with roles apply
my $by_workspace_with_roles_apply = sub {
    my $rows     = shift;
    my $user_row = $rows->[0];
    my $role_row = $rows->[1];

    # short circuit to not hand back undefs in a list context
    return undef if !$user_row;

    return [
        Socialtext::User->new(
            user_id => $user_row->select('system_unique_id')
        ),
        Socialtext::Role->new(
            role_id => $role_row->select('role_id')
        )
    ];
};

# by workspace with roles apply, ordered by creator
my $by_workspace_with_roles_ordered_by_creator_apply = sub {
    my $rows     = shift;
    my $user_id = $rows->[0];
    my $role_id = $rows->[1];

    # short circuit to not hand back undefs in a list context
    return undef if !$user_id;

    return [
        Socialtext::User->new(
            user_id => $user_id
        ),
        Socialtext::Role->new(
            role_id => $role_id
        )
    ];
};

sub Search {
    my $class = shift;
    my $search_term = shift;

    return $class->_aggregate('Search', $search_term);
}

sub Resolve {
    my $class = shift;
    my $maybe_user = shift;
    my $user;

    die "no user identifier specified" unless $maybe_user;

    if (ref($maybe_user) && $maybe_user->can('user_id')) {
        return $maybe_user;
    }
    elsif ($maybe_user =~ /^\d+$/) {
        $user = Socialtext::User->new(user_id => $maybe_user) 
    }

    $user ||= Socialtext::User->new(username => $maybe_user);
    $user ||= Socialtext::User->new(email_address => $maybe_user);

    die "no such user '$maybe_user'" unless defined $user;
    return $user;
}

my $standard_apply = sub {
    my $row = shift;
    return Socialtext::User->new( user_id => $row->[0] );
};

sub _UserCursor {
    my ( $class, $sql, $interpolations, %p ) = @_;

    Socialtext::Timer->Continue('user_cursor');

    my $sth = sql_execute( $sql, @p{@$interpolations} );
    my $mc = Socialtext::MultiCursor->new(
        iterables => [ $sth->fetchall_arrayref ],
        apply => $p{apply} || sub {
            my $row = shift;
            return $class->new( user_id => $row->[0] );
        }
    );

    Socialtext::Timer->Pause('user_cursor');

    return $mc;
}

my %LimitAndSortSpec = (
    limit      => SCALAR_TYPE( default => undef ),
    offset     => SCALAR_TYPE( default => 0 ),
    order_by   => SCALAR_TYPE(
        regex   => qr/^(?:username|workspace_count|creation_datetime|creator)$/,
        default => 'username',
    ),
    sort_order => SCALAR_TYPE(
        regex   => qr/^(?:ASC|DESC)$/i,
        default => undef,
    ),
);
{
    Readonly my $spec => { %LimitAndSortSpec };
    sub All {
        # Returns an iterator of Socialtext::User objects
        my $class = shift;
        my %p = validate( @_, $spec );

        # We're supposed to default to DESCending if we're creation_datetime.
        $p{sort_order} ||= $p{order_by} eq 'creation_datetime' ? 'DESC' : 'ASC';

        Readonly my %SQL => (
            creation_datetime => <<EOSQL,
SELECT user_id
    FROM "UserMetadata"
    ORDER BY creation_datetime $p{sort_order}
    LIMIT ? OFFSET ?
EOSQL
            creator => <<EOSQL,
SELECT user_id
    FROM "UserId" LEFT OUTER JOIN (
        SELECT user_id, driver_username AS "creator_username"
            FROM "UserMetadata" LEFT OUTER JOIN "UserId"
                ON "UserMetadata".created_by_user_id = "UserId".system_unique_id
    ) AS "X" ON "X".user_id = "UserId".system_unique_id
    ORDER BY creator_username, driver_username
    LIMIT ? OFFSET ?
EOSQL
            username => <<EOSQL,
SELECT system_unique_id
    FROM "UserId"
    ORDER BY driver_username $p{sort_order}
    LIMIT ? OFFSET ?
EOSQL
            workspace_count => <<EOSQL,
SELECT "UserId".system_unique_id,
        COUNT(DISTINCT("UserWorkspaceRole".workspace_id)) AS workspace_count
    FROM "UserId" LEFT OUTER JOIN "UserWorkspaceRole"
        ON "UserId".system_unique_id = "UserWorkspaceRole".user_id
    GROUP BY "UserId".system_unique_id, "UserId".driver_username
    ORDER BY workspace_count $p{sort_order},
             "UserId".driver_username ASC
    LIMIT ? OFFSET ?
EOSQL
            system_unique_id => <<EOSQL,
SELECT system_unique_id
    FROM "UserId"
    ORDER BY system_unique_id $p{sort_order}
    LIMIT ? OFFSET ?
EOSQL
        );

        return $class->_UserCursor(
            $SQL{ $p{order_by} },
            [qw( limit offset )], %p
        );
    }
}

{
    Readonly my $spec => {
        %LimitAndSortSpec,
        order_by   => SCALAR_TYPE(
            regex   => qr/^(?:username|creation_datetime|creator|role_name)$/,
            default => 'username',
        ),
        workspace_id => SCALAR_TYPE,
    };

    sub ByWorkspaceIdWithRoles {
        # Returns an iterator of [Socialtext::User, Socialtext::Role] arrays
        my $class = shift;
        my %p = validate( @_, $spec );

        # We're supposed to default to DESCending if we're creation_datetime.
        $p{sort_order} ||= $p{order_by} eq 'creation_datetime' ? 'DESC' : 'ASC';

        Readonly my %SQL => (
            username => <<EOSQL,
SELECT DISTINCT "UserId".system_unique_id AS system_unique_id,
                "Role".role_id AS role_id,
                "UserId".driver_key AS driver_key,
                "UserId".driver_unique_id AS driver_unique_id,
                "UserId".driver_username AS driver_username,
                "Role".name AS name,
                "Role".used_as_default AS used_as_default,
                "UserId".driver_username AS driver_username
    FROM "UserId" AS "UserId",
         "UserWorkspaceRole" AS "UserWorkspaceRole",
         "Role" AS "Role"
    WHERE ("UserId".system_unique_id = "UserWorkspaceRole".user_id
            AND "UserWorkspaceRole".role_id = "Role".role_id)
        AND ("UserWorkspaceRole".workspace_id = ? )
    ORDER BY "UserId".driver_username $p{sort_order}
    LIMIT ? OFFSET ?
EOSQL
            creation_datetime => <<EOSQL,
SELECT DISTINCT "UserId".system_unique_id AS system_unique_id,
                "Role".role_id AS role_id,
                "UserId".driver_key AS driver_key,
                "UserId".driver_unique_id AS driver_unique_id,
                "UserId".driver_username AS driver_username,
                "Role".name AS name,
                "Role".used_as_default AS used_as_default,
                "UserMetadata".creation_datetime AS creation_datetime,
                "UserId".driver_username AS driver_username
    FROM "UserId" AS "UserId",
         "UserWorkspaceRole" AS "UserWorkspaceRole",
         "Role" AS "Role",
         "UserMetadata" AS "UserMetadata"
    WHERE ("UserId".system_unique_id = "UserWorkspaceRole".user_id
            AND "UserWorkspaceRole".role_id = "Role".role_id
            AND "UserId".system_unique_id = "UserMetadata".user_id)
        AND ("UserWorkspaceRole".workspace_id = ? )
    ORDER BY "UserMetadata".creation_datetime $p{sort_order},
        "UserId".driver_username ASC
    LIMIT ? OFFSET ?
EOSQL
            creator => <<EOSQL,
SELECT DISTINCT ("UserId".system_unique_id) AS aaaaa10000,
                "Role".role_id AS role_id,
                "UserId".driver_username AS driver_username,
                "UserId000000003".driver_username AS driver_username
    FROM "UserMetadata" AS "UserMetadata"
        LEFT OUTER JOIN "UserId" AS "UserId000000003"
            ON "UserMetadata".created_by_user_id
                    = "UserId000000003".system_unique_id,
                "UserId" AS "UserId",
                "UserWorkspaceRole" AS "UserWorkspaceRole",
                "Role" AS "Role"
    WHERE ("UserId".system_unique_id = "UserWorkspaceRole".user_id
            AND "UserWorkspaceRole".role_id = "Role".role_id
            AND "UserId".system_unique_id = "UserMetadata".user_id )
        AND  ("UserWorkspaceRole".workspace_id = ? )
    ORDER BY "UserId000000003".driver_username $p{sort_order},
       "UserId".driver_username ASC
    LIMIT ? OFFSET ?
EOSQL
            role_name => <<EOSQL,
SELECT DISTINCT "UserId".system_unique_id AS system_unique_id,
                "Role".role_id AS role_id,
                "UserId".driver_key AS driver_key,
                "UserId".driver_unique_id AS driver_unique_id,
                "UserId".driver_username AS driver_username,
                "Role".name AS name,
                "Role".used_as_default AS used_as_default,
                "Role".name AS name,
                "UserId".driver_username AS driver_username
    FROM "UserId" AS "UserId",
        "UserWorkspaceRole" AS "UserWorkspaceRole",
        "Role" AS "Role"
    WHERE ("UserId".system_unique_id = "UserWorkspaceRole".user_id
            AND "UserWorkspaceRole".role_id = "Role".role_id )
        AND  ("UserWorkspaceRole".workspace_id = ? )
    ORDER BY "Role".name $p{sort_order},
        "UserId".driver_username ASC
    LIMIT ? OFFSET ?
EOSQL
        );

        return $class->_UserCursor(
            $SQL{ $p{order_by} },
            [qw( workspace_id limit offset )], %p,
            apply => sub {
                my $rows    = shift;
                my $user_id = $rows->[0];
                my $role_id = $rows->[1];

                # short circuit to not hand back undefs in a list context
                return undef if !$user_id;

                return [
                    Socialtext::User->new( user_id => $user_id ),
                    Socialtext::Role->new( role_id => $role_id )
                ];
            },
        );
    }
}

{
    Readonly my $spec => {
        %LimitAndSortSpec,
        username => SCALAR_TYPE( regex => qr/\S/ ),
    };
    sub ByUsername {
        # Returns an iterator of Socialtext::User objects
        my $class = shift;
        my %p = validate( @_, $spec );

        # We're supposed to default to DESCending if we're creation_datetime.
        $p{sort_order} ||= $p{order_by} eq 'creation_datetime' ? 'DESC' : 'ASC';

        Readonly my %SQL => (
            username => <<EOSQL,
SELECT DISTINCT "UserId".system_unique_id AS system_unique_id,
                "UserId".driver_key AS driver_key,
                "UserId".driver_unique_id AS driver_unique_id,
                "UserId".driver_username AS driver_username,
                "UserId".driver_username AS driver_username
    FROM "UserId" AS "UserId"
    WHERE "UserId".driver_username LIKE ?
    ORDER BY "UserId".driver_username $p{sort_order}
    LIMIT ? OFFSET ?
EOSQL
            workspace_count => <<EOSQL,
SELECT "UserId".system_unique_id AS system_unique_id,
        COUNT(DISTINCT("UserWorkspaceRole".workspace_id)) AS aaaaa10000
    FROM "UserId" AS "UserId"
        LEFT OUTER JOIN "UserWorkspaceRole" AS "UserWorkspaceRole"
            ON "UserId".system_unique_id = "UserWorkspaceRole".user_id
    WHERE "UserId".driver_username LIKE ?
    GROUP BY "UserId".system_unique_id, "UserId".driver_username
    ORDER BY aaaaa10000 ASC, "UserId".driver_username $p{sort_order}
    LIMIT ? OFFSET ?
EOSQL
            creation_datetime => <<EOSQL,
SELECT DISTINCT "UserId".system_unique_id AS system_unique_id,
                "UserId".driver_key AS driver_key,
                "UserId".driver_unique_id AS driver_unique_id,
                "UserId".driver_username AS driver_username,
                "UserMetadata".creation_datetime AS creation_datetime,
                "UserId".driver_username AS driver_username
    FROM "UserId" AS "UserId", "UserMetadata" AS "UserMetadata"
    WHERE ("UserId".system_unique_id = "UserMetadata".user_id )
        AND  ("UserId".driver_username LIKE ? )
    ORDER BY "UserMetadata".creation_datetime $p{sort_order},
        "UserId".driver_username ASC
    LIMIT ? OFFSET ?
EOSQL
            creator => <<EOSQL,
SELECT DISTINCT("UserId".system_unique_id) AS aaaaa10000,
        "UserId".driver_username AS driver_username,
        "UserId000000004".driver_username AS driver_username
    FROM "UserMetadata" AS "UserMetadata"
        LEFT OUTER JOIN "UserId" AS "UserId000000004"
            ON "UserMetadata".created_by_user_id
                    = "UserId000000004".system_unique_id,
               "UserId" AS "UserId"
    WHERE ("UserId".system_unique_id = "UserMetadata".user_id )
        AND ("UserId".driver_username LIKE ? )
    ORDER BY "UserId000000004".driver_username $p{sort_order},
        "UserId".driver_username ASC
    LIMIT ? OFFSET ?
EOSQL
        );

        $p{username} = '%' . $p{username} . '%';

        return $class->_UserCursor(
            $SQL{ $p{order_by} },
            [ qw( username limit offset )], %p
        );
    }
}


{
    Readonly my $spec => { username => SCALAR_TYPE( regex => qr/\S/ ) };
    sub CountByUsername {
        my $class = shift;
        my %p = validate( @_, $spec );

        my $sth = sql_execute(
            'SELECT COUNT(*) FROM "UserId"'
            . ' WHERE driver_username LIKE ?',
            '%' . lc $p{username} . '%' );
        return $sth->fetchall_arrayref->[0][0];
    }
}

sub Count {
    my ( $class, %p ) = @_;

    my $sth = sql_execute('SELECT COUNT(*) FROM "UserId"');
    return $sth->fetchall_arrayref->[0][0];
}

# Confirmation methods

{
    my $spec = { is_password_change => BOOLEAN_TYPE( default => 0 ) };

    sub set_confirmation_info {
        my $self = shift;
        my %p    = validate( @_, $spec );

        Socialtext::User::EmailConfirmation->create_or_update(
            user_id => $self->user_id,
            %p,
        );
    }
}

sub confirmation_hash {
    my $self = shift;
    return $self->email_confirmation->hash;
}

sub confirmation_is_for_password_change {
    my $self = shift;
    return $self->email_confirmation->is_password_change;
}

# REVIEW - does this belong in here, or maybe a higher level library
# like one for all of our emails? I dunno.
sub send_confirmation_email {
    my $self = shift;

    return unless $self->email_confirmation();

    my $renderer = Socialtext::TT2::Renderer->instance();

    my $uri = $self->confirmation_uri();

    my %vars = (
        confirmation_uri => $uri,
        appconfig        => Socialtext::AppConfig->instance(),
    );

    my $text_body = $renderer->render(
        template => 'email/email-address-confirmation.txt',
        vars     => \%vars,
    );

    my $html_body = $renderer->render(
        template => 'email/email-address-confirmation.html',
        vars     => \%vars,
    );

    # XXX if we add locale per workspace, we have to get the locale from hub.
    my $locale = system_locale();
    my $email_sender = Socialtext::EmailSender::Factory->create($locale);
    $email_sender->send(
        to        => $self->name_and_email(),
        subject   => loc('Please confirm your email address to register with Socialtext'),
        text_body => $text_body,
        html_body => $html_body,
    );
}

sub send_confirmation_completed_email {
    my $self = shift;

    return if $self->email_confirmation();

    my $renderer = Socialtext::TT2::Renderer->instance();

    my $ws = $self->workspaces->next();

    my %vars;
    my $subject;
    # A user who self-registers may not be a member of any workspaces.
    if ($ws) {
        %vars = (
            title => $ws->title(),
            uri   => $ws->uri(),
        );

        $subject = loc('You can now login to the [_1] workspace', $ws->title());
    }
    else {
        # REVIEW - duplicated form ST::UserSettingsPlugin - where does
        # this belong, maybe AppConfig?
        my $app_name =
            Socialtext::AppConfig->is_appliance()
            ? 'Socialtext Appliance'
            : 'Socialtext';

        %vars = (
            title => $app_name,
            uri   => Socialtext::URI::uri( path => '/nlw/login.html' ),
        );

        $subject = loc("You can now login to the [_1] application", $app_name);
    }

    $vars{user}      = $self;
    $vars{appconfig} = Socialtext::AppConfig->instance();

    my $text_body = $renderer->render(
        template => 'email/email-address-confirmation-completed.txt',
        vars     => \%vars,
    );

    my $html_body = $renderer->render(
        template => 'email/email-address-confirmation-completed.html',
        vars     => \%vars,
    );
    my $locale = system_locale();
    my $email_sender = Socialtext::EmailSender::Factory->create($locale);
    $email_sender->send(
        to        => $self->name_and_email(),
        subject   => $subject,
        text_body => $text_body,
        html_body => $html_body,
    );
}

sub send_password_change_email {
    my $self = shift;

    return unless $self->email_confirmation();

    my $renderer = Socialtext::TT2::Renderer->instance();

    my $uri = $self->confirmation_uri();

    my %vars = (
        appconfig        => Socialtext::AppConfig->instance(),
        confirmation_uri => $uri,
    );

    my $text_body = $renderer->render(
        template => 'email/password-change.txt',
        vars     => \%vars,
    );

    my $html_body = $renderer->render(
        template => 'email/password-change.html',
        vars     => \%vars,
    );
    my $locale = system_locale();
    my $email_sender = Socialtext::EmailSender::Factory->create($locale);
    $email_sender->send(
        to        => $self->name_and_email(),
        subject   => loc('Please follow these instructions to change your Socialtext password'),
        text_body => $text_body,
        html_body => $html_body,
    );
}

sub confirmation_uri {
    my $self = shift;

    return unless $self->requires_confirmation;

    return Socialtext::URI::uri(
        path  => '/nlw/submit/confirm_email',
        query => { hash => $self->confirmation_hash() },
    );
}

sub requires_confirmation {
    my $self = shift;

    return $self->email_confirmation ? 1 : 0;
}

sub confirmation_has_expired {
    my $self = shift;

    return $self->email_confirmation->has_expired;
}

sub confirm_email_address {
    my $self = shift;

    my $uce = $self->email_confirmation;
    return unless $uce;

    $uce->delete;
    $self->send_confirmation_completed_email unless $uce->is_password_change;
}

sub email_confirmation {
    my $self = shift;
    return Socialtext::User::EmailConfirmation->new( $self->user_id );
}

sub can_use_plugin {
    my ($self, $plugin_name) = @_;

    my $authz = ($self->hub && $self->hub->authz)
        ? $self->hub->authz 
        : Socialtext::Authz->new();
    return $authz->plugin_enabled_for_user(
        plugin_name => $plugin_name,
        user => $self
    );
}

sub can_use_plugin_with {
    my ($self, $plugin_name, $buddy) = @_;

    if ($buddy && $self->user_id == $buddy->user_id) {
        return $self->can_use_plugin($plugin_name);
    }

    my $authz = ($self->hub && $self->hub->authz)
        ? $self->hub->authz 
        : Socialtext::Authz->new();
    return $authz->plugin_enabled_for_users(
        plugin_name => $plugin_name,
        actor => $self,
        user => $buddy
    );
}

# This addresses some basic concerns about whether or not the user's avatar is
# visible to other users.
#
# * Does the user have people enabled? 
# * If so, do they have a picture that is not hidden?
#
# If this is the case, return 1
sub avatar_is_visible {
    my $self = shift;

    if ( $self->can_use_plugin('people') ) {
        my $profile;
        eval {
            require Socialtext::People::Profile;
            $profile = Socialtext::People::Profile->GetProfile($self);
        };

        return ( $profile && ! $profile->is_hidden );
    }

    return 0;
}

# Address whether or not the user's profile should be visible to another user.
#
# * Do the users share a common account where people is enabled?
# * Does the user have an account that is not hidden?
#
# If these are the case, return 1
sub profile_is_visible_to {
    my $self   = shift;
    my $viewer = shift;

    if ( $self->can_use_plugin_with( 'people', $viewer ) ) {
        my $profile;
        eval {
            require Socialtext::People::Profile;
            $profile = Socialtext::People::Profile->GetProfile($self);
        };

        return ( $profile && ! $profile->is_hidden );
    }

    return 0;
}

1;

__END__

=head1 NAME

Socialtext::User - A Socialtext user object

=head1 SYNOPSIS

  use Socialtext::User;

  my $user = Socialtext::User->new( user_id => $user_id );

  my $user = Socialtext::User->new( username => $username );

  my $user = Socialtext::User->new( email_address => $email_addres );

=head1 DESCRIPTION

This class provides methods for dealing with abstract users.

=head1 METHODS

=head2 Socialtext::User->new(PARAMS)

Looks for an existing user matching PARAMS and returns a
C<Socialtext::User> object representing that user if it exists.

The user object comprises two hashes: a homunculus, representing the user's
credential data (username, password, email address, first name, and last
name), and application-specific C<Socialtext::UserMetadata> (last login time,
creation time, who created the user, &c).

PARAMS can be I<one> of:

=over 4

=item * user_id => $user_id

=item * username => $username

=item * email_address => $email_address

=back

=head2 Socialtext::User->new_homunculus(PARAMS)

Looks for an existing user matching PARAMS and returns just the homunculus
object (an instance of the particular class which authenticated the
credentials).

PARAMS can be I<one> of:

=over 4

=item * user_id => $user_id

=item * username => $username

=item * email_address => $email_address

=item * driver_unique_id => $driver_unique_id

=back

=head2 Socialtext::User->create(PARAMS)

Attempts to create a user with the given information and returns a new
C<Socialtext>::User object representing the new user.

PARAMS can include:

=over 4

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

=item * last_name

=item * creation_datetime - defaults to CURRENT_TIMESTAMP

=item * last_login_datetime

=item * email_address_at_import - defaults to "email_address"

=item * created_by_user_id - defaults to SystemUser()->user_id()

=item * is_business_admin - defaults to false

=item * is_technical_admin - defaults to false

=item * is_system_created - defaults to false

=back

=head2 $class->base_package

Returns the name of the package (used by the Socialtext::MultiPlugin base when
determining driver classes

=head2 $user->can_update_store()

Returns true if the user factory supports updates.

=head2 $user->update_store(PARAMS)

Updates the user's information with the new key/val pairs passed in.

=head2 $user->recently_viewed_workspaces($limit)

Returns a list of the workspaces that this user has most recently viewed.
Restricted to the most recent C<$limit> (default 10) workspaces.

Returned as a list of list-refs that contain the "name" and "title" of the
workspace.

=head2 $user->user_id()

=head2 $user->username()

=head2 $user->email_address()

=head2 $user->first_name()

=head2 $user->last_name()

=head2 $user->driver_name()

=head2 $user->creation_datetime()

=head2 $user->last_login_datetime()

=head2 $user->created_by_user_id()

=head2 $user->is_business_admin()

=head2 $user->is_technical_admin()

=head2 $user->is_system_created()

Returns the corresponding attribute for the user.

=head2 $user->delete()

By default, this method simply throws an exception. In almost all
cases, users should not be deleted, as they are foreign keys for too
many other tables, and even if a user is no longer active, they are
still likely to be needed when looking up page authors and other
information.

If you pass C<< force => 1 >> this will force the deletion through.

As an alternative to deletion, you can block a user from logging in by
setting their password to some string and passing C<< no_crypt => 1 >>
to C<update()>

=head2 $user->accounts()

Returns a list of the accounts associated with the user.  Returns a
list reference in scalar context.

=head2 $user->shared_accounts( $user2 )

Returns a list of the accounts where both $user and $user2 are members.
Returns a list reference in scalar context.

=head2 $user->to_hash()

Returns a hash reference representation of the user, suitable for using with
JSON, YAML, etc.  B<WARNING:> The encryted password is included in this hash,
and should usually be removed before passing the hash over the threshold.

=head2 $user->password_is_correct($pw)

Returns a boolean indicating whether or not the given password is
correct.

=head2 $user->has_valid_password()

Returns true if the user has a valid password.

For now, this is defined as any password not matching "*none*".

=head2 Socialtext::User->ValidatePassword( password => $pw )

Given a password, this returns a list of error messages if the
password is invalid.

=head2 $user->set_technical_admin($value)

Updates the is_technical_admin for the user to $value (0 or 1).

=head2 $user->set_business_admin($value)

Updates the is_business_admin for the user to $value (0 or 1).

=head2 $user->record_login()

Updates the last_login_datetime for the user to the current datetime.

=head2 $user->name_and_email()

Returns the user's name and email address in a format suitable for use
in email headers, such as C<< "John Doe" <john@example.com> >>.

=head2 $user->best_full_name( workspace => $workspace )

If the user has a first name and/or last name in the DBMS, then this
method returns the two fields separated by a single space. If neither
is set, then this returns the user's email address.

The "workspace" argument is optional, but if it is given, then the
email address will be masked according to the settings of the given
workspace.

=head2 $user->masked_email_address( workspace => $workspace )

Not implemented

=head2 $user->masked_email_address( user => $other_user )

Returns the masked email address if $user and $other_user are not 
members of any common accounts where email_addresses_are_masked is 0

=head2 $user->name_for_email()

Returns the user's name and email, in a format suitable for use in
email headers.

=head2 $user->guess_sortable_name()

Returns a guess at the user's sortable name, using the first name and/or last
name from the DBMS if possible.  Goal is to end up with a name for the user
that can be sorted alphabetically by last name, then first name.

=head2 $user->guess_real_name()

Returns the a guess at the user's real name, using the first name
and/or last name from the DBMS if possible. Otherwise it simply uses
the portion of the email address up to the at (@) symbol.

=head2 $user->creation_datetime_object()

Returns a new C<DateTime.pm> object for the user's creation datetime.

=head2 $user->last_login_datetime_object()

Returns a new C<DateTime.pm> object for the user's last login
datetime. This may be a C<DateTime::Infinite::Past> object if the user
has never logged in.

=head2 $user->creator()

Returns a C<Socialtext::User> object for the user which created this
user.

=head2 $user->workspace_count()

Returns the number of workspaces of which the user is a member.

=head2 $user->workspaces(PARAMS)

Returns a cursor of the workspaces of which the user is a member,
ordered by workspace name.

PARAMS can include:

=over 4

=item * selected_only

If this is true, then only workspaces for which UserWorkspaceRole.is_selected
is true are returned.

=back

=head2 $user->workspaces_with_selected()

Returns a cursor of the C<Socialtext::Workspace> and
C<Socialtext::UserWorkspaceRole> object for the workspace of which the
user is a member, ordered by workspace name.

REVIEW - better name needed

=head2 $user->workspace_is_selected( workspace => $workspace )

Returns a boolean indicating whether or not the given workspace is
selected.

=head2 $user->set_selected_workspaces( workspaces => [ $ws1, $ws2 ] );

Given an array reference of C<Socialtext::Workspace> objects, this
sets UserWorkspaceRole.is_selected for each workspace to true, and
false for all other workspaces of which the user is a member.

=head2 $user->is_authenticated()

Returns a boolean indicating whether the user is an authenticated user
(not the guest user).

=head2 $user->is_guest()

Returns a boolean indicating whether the user is the guest user.

=head2 $user->is_deleted()

Returns a boolean indicating whether the user is present in our
system, but cannot be looked up for some reason.

=head2 $user->default_role()

Returns the default role for the user absent an explicit role
assignment. This will be either "guest" or "authenticated_user".

=head2 $user->can_use_plugin( $name )

Returns a boolean indicating whether the user can use the given plugin.
See also C<Socialtext::Account::is_plugin_enabled>

=head2 $user->can_use_plugin_with( $name => $buddy )

Returns a boolean indicating whether the user can use the given plugin to interact with another user, C<$buddy>.

=head2 $user->avatar_is_visible()

Returns a boolean indicating whether the user's avatar should be hidden or visible.

=head2 $user->profile_is_visible_to( $viewer )

Returns a boolean indicating whether the user's profile should be visible to
the specified viewer.

=head2 Socialtext::User->minimal_interface()

Returns the minimal keys necessary for User Factory plugins to implement.

=head2 Socialtext::User->Guest()

Returns the user object for the "guest user", which is used when an
end user comes to the application without authentication.

=head2 Socialtext::User->SystemUser()

Returns the user object for the "system user", which should be used as
the user for operations where a user is needed but there is no end
user, like operations done from the CLI (creating a workspace, for
example).

=head2 Socialtext::User->FormattedEmail($first_name, $last_name, $email_address)

Returns a formatted email address from the parameters passed in. Will attempt
to construct a "pretty" presentation:

=over 4

=item "Zachery Bir" <zac.bir@socialtext.com>

=item "Zachery" <zac.bir@socialtext.com>

=item "Bir" <zac.bir@socialtext.com>

=item <zac.bir@socialtext.com>

=back

=head2 Socialtext::User->MaskEmailAddress($email_address, $workspace)

If appropriate for C<$workspace> (based on the C<email_addresses_are_hidden>
workspace configuration setting), return a masked version of the given email
address.  Otherwise return the email address unaltered.

=head2 Socialtext::User->All(PARAMS)

Returns a cursor for all the users in the system. It accepts the
following parameters:

=over 4

=item * limit and offset

These parameters can be used to add a C<LIMIT> clause to the query.

=item * order_by - defaults to "username"

This must be one "username", "workspace_count", "creation_datetime",
or "creator".

=item * sort_order - "ASC" or "DESC"

This defaults to "ASC" except when C<order_by> is "creation_datetime",
in which case it defaults to "DESC".

=back

=head2 Socialtext::User->ByAccountId(PARAMS)

Returns a cursor for all the users in a specified account.

This method accepts the same parameters as C<< Socialtext::User->All()
>>, but requires an additional "account_id" parameter. The C<order_by>
parameter cannot be "workspace_count".

=head2 Socialtext::User->ByWorkspaceIdWithRoles(PARAMS)

This method returns a cursor that of the user and their role in the
specified workspace.

This accepts the same parameters as C<< Socialtext::User->All() >>,
but requires an additional "workspace_id" parameter. When this method
is called, the C<order_by> parameter may also be "role_name". The
C<order_by> parameter cannot be "workspace_count".

=head2 Socialtext::User->ByUsername(PARAMS)

Returns a cursor for all the users matching the specified string.

This accepts the same parameters as C<< Socialtext::User->All() >>,
but requires an additional "username" parameter. Any users containing
the specified string anywhere in their username will be returned.

=head2 Socialtext::User->Count()

Returns a count of all users.

=head2 Socialtext::User->CountByUsername( username => $username )

Returns the number of users in the system containing the
specified string anywhere in their username.

=head2 Socialtext::User->Search( $search_string )

Returns an aggregated cursor of Socialtext::User objects which match
$search_string on any of username, email_address, first_name, or
last_name.

=head2 Socialtext::User->Resolve( $thingy )

Given something that might be a Socialtext::User or an identifier for a user
(system-unique-id, username, or e-mail address), try to resolve it to a
Socialtext::User object.

Throws an exception if C<$thingy> can't be resolved to a User.

=head2 Socialtext::User->Create_user_from_hash( $hashref )

Create a user from the data in the specified hash.  This routine is used
by import/export scripts.

=head2 $user->set_confirmation_info()

Creates a confirmation hash and an expiration date for this user.
When this exists, the C<< $user->requires_confirmation() >> will return true.

This method accepts a single boolean argument, "is_password_change",
which defaults to false. Set this to true if the confirmation is being
set to allow a user to change their password.

Confirmations expire fourteen days after they are created.

If the user already has an existing confirmation row, then its
expiration datetime is updated to one day after the datetime at which
the method was called.

=head2 $user->requires_confirmation()

This returns true if there is a row for this user in the
UseEmailConfirmation table.

=head2 $user->confirmation_is_for_password_change()

This returns true if the user requires confirmation, and this is for
the purpose of allow them to change their password.

=head2 $user->confirmation_hash()

Returns the hash value which will confirm this user's email address,
if one exists.

=head2 $user->confirmation_uri()

This is the URI to confirm the user's email address. If the user is
already confirmation, it returns false.

=head2 $user->confirmation_has_expired()

Returns a boolean indicating whether or not the user's confirmation
hash has expired.

=head2 $user->send_confirmation_email()

If the user has a EmailConfirmation object, this method sends them
an email with a link they can use to confirm their email address.

=head2 $user->send_confirmation_completed_email()

If the user I<does not> have a EmailConfirmation object, this
method sends them an email saying that their email confirmation has
been completed.

=head2 $user->send_password_change_email()

If the user has a EmailConfirmation object, this method sends them
an email with a link they can use to change their password.

=head2 $user->confirm_email_address()

Marks the user's email address as confirmed by deleting the row for
the user in UserConfirmationEmail.

=head2 $user->email_confirmation()

Create and return an Socialtext::User::EmailConfirmation object for the user.

=head2 $user->avatar_is_visible()

Return whether the user's avatar should be displayed when viewing information
about this user. 

=head2 $user->profile_is_visible_to()

Return whether a link to the user's profile should be displayed when viewing
information about this user. 

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc., All Rights Reserved.


=cut
