package Socialtext::User;
# @COPYRIGHT@
use 5.12.0;
use Moose;

our $VERSION = '0.01';

use Socialtext::Exceptions qw(data_validation_error);
use Socialtext::Validate qw( validate SCALAR_TYPE BOOLEAN_TYPE ARRAYREF_TYPE WORKSPACE_TYPE USER_TYPE SCALAR UNDEF CODEREF);
use Socialtext::AppConfig;
use Socialtext::Log qw(st_log);
use Socialtext::MultiCursor;
use Socialtext::Permission 'ST_READ_PERM';
use Socialtext::SQL qw(sql_execute sql_selectrow sql_singlevalue sql_txn);
use Socialtext::SQL::Builder qw(sql_abstract);
use Socialtext::TT2::Renderer;
use Socialtext::URI;
use Socialtext::UserMetadata;
use Socialtext::User::Deleted;
use Socialtext::User::Factory;
use Socialtext::UserSet qw/:const/;
use Socialtext::User::Default::Users qw(:system-user :guest-user);
use Socialtext::User::Restrictions;
use Email::Address;
use Socialtext::l10n qw(:all);
use Socialtext::EmailSender::Factory;
use Socialtext::User::Cache;
use Socialtext::Cache;
use Socialtext::Timer qw/time_scope/;
use Carp qw/croak/;
use Try::Tiny;
use Readonly;
use Scalar::Util qw/blessed/;
use List::MoreUtils qw(any);

BEGIN {
    extends 'Socialtext::Base','Socialtext::MultiPlugin';
}

has 'homunculus' => (
    is => 'rw', isa => 'Socialtext::User::Base',
    writer => '_set_homunculus',
    required => 1,
    handles => [qw(
        user_id
        user_set_id
        username
        password
        email_address
        first_name
        middle_name
        last_name
        display_name
        password_is_correct
        has_valid_password
        is_profile_hidden
        driver_name
        driver_unique_id
        cached_at
        missing
        private_external_id

        can_use_plugin
        profile
        clear_profile
        proper_name
        preferred_name
        guess_real_name
        guess_sortable_name
        name_and_email
        update_display_name
        update_private_external_id
    )],
);

has 'metadata' => (
    is => 'rw', isa => 'Socialtext::UserMetadata',
    writer => '_set_metadata',
    lazy_build => 1,
    handles => [qw(
        email_address_at_import
        creation_datetime
        last_login_datetime
        created_by_user_id
        is_business_admin
        is_technical_admin
        is_system_created
        set_technical_admin
        set_business_admin
        record_login
        creation_datetime_object
        last_login_datetime_object
        creator
        primary_account_id
    )],
);
sub _build_metadata {
    my $self = shift;
    my $meta = Socialtext::UserMetadata->create_if_necessary($self);
    return $meta;
}

with 'Socialtext::UserSetContained';

our @public_interface = qw(
    user_id username email_address password first_name middle_name last_name
    display_name creation_datetime last_login_datetime
    email_address_at_import created_by_user_id is_business_admin
    is_technical_admin is_system_created primary_account_id
);
our @private_interface = qw(
    private_external_id
);

sub base_package { return __PACKAGE__ }

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
    die "ST::User->_realize: Couldn't load $real_class -- $@" if $@;

    if ($real_class->can($method)) {
        return $real_class->new($driver_id);
    }

    return undef;
}

sub deleted_user {
    my $class = shift;
    my $proto_user = shift;

    $proto_user->{missing} = 1;

    require Socialtext::User::Deleted;
    my $homunculus = Socialtext::User::Deleted->new($proto_user);

    return $homunculus;
}

sub new_homunculus {
    my $class = shift;
    my $key = shift;
    my $val = shift;

    my $homunculus = Socialtext::User::Cache->Fetch($key, $val);
    return $homunculus if $homunculus;

    my $proto_user = $class->GetProtoUser($key => $val, collection=>'all');
    if ($proto_user) {
        if ($proto_user->{is_deleted}) {
            my $homunculus = return $class->deleted_user($proto_user);
            Socialtext::User::Cache->Store($key, $val, $homunculus);
            return $homunculus;
        }

        my $factory = eval {
            $class->_realize($proto_user->{driver_key}, 'NewHomunculus');
        };
        if (!$factory) {
            my $homunculus = $class->deleted_user($proto_user);
            Socialtext::User::Cache->Store($key, $val, $homunculus);
            return $homunculus
        }

        if ($factory->is_cached_proto_user_valid($proto_user)) {
            $homunculus = $factory->NewHomunculus($proto_user);
            die "couldn't find user from ok cache" unless $homunculus;
            st_log->debug("Returned cached user, $key => $val");
            Socialtext::User::Cache->Store($key, $val, $homunculus);
            return $homunculus;
        }
    }

    # The user_id key does not exist in LDAP, so map to username
    if ($key eq 'user_id') {
        return undef unless $proto_user;

        $key = 'username';
        $val = $proto_user->{driver_username};
    }
    # Weed out system users (called 'Default' users here).
    if (Socialtext::User::Default::Users->IsDefaultUser($key => $val)) {
        my $factory = $class->_realize('Default', 'GetUser');
        return $factory->GetUser($key => $val);
    }

    $homunculus = eval {
        $class->_first('GetUser', $key => $val, preload => $proto_user)
    };
    if (my $e = $@) {
        st_log->error($e);
            
        if ($e =~ /no suitable LDAP response/) {
            return $proto_user
                ? Socialtext::User::Factory->NewHomunculus($proto_user)
                : undef;
        }
        elsif ($e =~ /LDAP error while finding user/) {
            return $proto_user
                ? Socialtext::User::Factory->NewHomunculus($proto_user)
                : undef;
        }
        elsif ($e =~ /found multiple matches for user/) {
            return undef;
        }
        else {
            die $e;
        }
    }
    
    if ($proto_user && !$homunculus) {
        $proto_user->{missing} = 1;
        $proto_user->{cached_at} = 'now';
        Socialtext::User::Factory->UpdateUserRecord($proto_user);
        st_log->info("User '$proto_user->{driver_unique_id}' missing");

        $proto_user->{username} = $proto_user->{driver_username};
        return $class->deleted_user($proto_user);
    }

    Socialtext::User::Cache->Store($key, $val, $homunculus);
    return $homunculus;
}

sub GetProtoUser {
    my $class = shift;
    my $key = shift;
    my $value = shift;
    my %opts = @_;
    my $collection = $opts{collection} || 'active';

    my @binds;
    my @where;
    if ($opts{driver_keys}) {
        push @binds, @{$opts{driver_keys}};
        my $filter = $opts{exclude_driver_keys} ? 'NOT IN' : 'IN';
        push @where, "driver_key $filter (" . join(",", map {'?'} @binds) .")";
    }

    if (any { $key eq $_ } qw/user_id driver_unique_id private_external_id/) {
        return undef if ($key eq 'user_id' && $value !~ /^\d+$/);

        push @where, "$key = ?";
    }
    elsif ($key eq 'username' || $key eq 'email_address') {
        $value = Socialtext::String::trim(lc $value);
        $key = 'driver_username' if $key eq 'username';
        push @where, "LOWER($key) = ?";
    }
    else {
        warn "invalid user ID lookup key '$key'";
        return undef;
    }
    push @binds, $value;

    my $where_clause = join(' AND ', @where);
    if ($collection eq 'active') {
        $where_clause .= ' AND NOT is_deleted';
    }
    elsif ($collection eq 'deleted') {
        $where_clause .= ' AND is_deleted';
    }

    my $sth = sql_execute(qq{
        SELECT * FROM all_users WHERE $where_clause
    }, @binds);
    my $rows = $sth->fetchall_arrayref({});

    if ($collection eq 'all' and scalar(@$rows) > 1) {
        if ( any { ! $_->{is_deleted} } @$rows ) {
            $rows = [ grep { ! $_->{is_deleted} } @$rows ];
        }
    }

    die "found more than one record for $key => $value" if scalar(@$rows) > 1;
    return $rows->[0];
}

sub _update_profile_with_extra_attrs {
    my $self  = shift;
    my $homey = $self->homunculus;
    return unless $homey->can('extra_attrs');

    my $attrs = $homey->extra_attrs;
    $homey->extra_attrs(undef);
    return unless ($attrs && %$attrs);

    my $people = Socialtext::Pluggable::Adapter->plugin_class('people');
    $people->UpdateProfileFields($self => $attrs, {source => 'directory'})
        if $people;
}

sub new {
    my $class = shift;
    my $t = time_scope('user_new');

    my $homunculus = $class->new_homunculus(@_);
    return unless $homunculus;

    return $class->new_from_homunculus($homunculus);
}

sub new_from_homunculus {
    my $class      = shift;
    my $homunculus = shift;
    my $self       = $class->meta->new_object(homunculus => $homunculus);
    $self->_update_profile_with_extra_attrs();

    return $self;
}

sub create {
    my $class = shift;
    my $t = time_scope('user_create');

    # username email_address password first_name last_name
    my %p = @_;
    my $id = Socialtext::User::Factory->NewUserId();
    $p{user_id} = $id;

    my $homunculus = $class->_first( 'create', %p );

    if (!exists $p{created_by_user_id}) {
        if ($homunculus->username ne $SystemUsername) {
            $p{created_by_user_id} = Socialtext::User->SystemUser()->user_id;
        }
    }

    my $metadata = Socialtext::UserMetadata->create(
        email_address_at_import => $homunculus->email_address,
        %p,
    );

    my $user = $class->meta->new_object(
        homunculus => $homunculus,
        metadata   => $metadata,
    );

    $user->_update_profile_with_extra_attrs();
    $user->_index();

    $user->_call_hook('nlw.user.create');

    return $user;
}

sub reload {
    my $self    = shift;
    my $user_id = $self->user_id;

    # Forcably remove ourselves from the cache first; we explicitly *don't*
    # want the cached copy of this User
    Socialtext::User::Cache->Remove(user_id => $user_id);
    $self->metadata->_cache->remove($user_id);

    # Refresh the Homunculus and Metadata for the User.
    my $homey = $self->new_homunculus(user_id => $user_id);
    $self->_set_homunculus($homey);

    my $meta = Socialtext::UserMetadata->new(user_id => $user_id);
    $self->_set_metadata($meta);

    return $self;
}

sub SystemUser {
    state $sysuser = shift->new( username => $SystemUsername );
    return $sysuser;
}

sub Guest {
    state $guser = shift->new( username => $GuestUsername );
    return $guser;
}

sub can_update_store {
    my $self = shift;
    my $homunculus_class = $self->base_package() . "::" . $self->driver_name;
    return $homunculus_class->can('update') ? 1 : undef;
}

sub update_store {
    my $self = shift;
    my %p = @_;
    my $old_name = $self->display_name;

    if ($p{password} && $self->is_system_created) {
        data_validation_error errors => [
            "cannot change the password of a system-created user.\n"];
    }

    my $rv = $self->homunculus->update( %p );
    my $new_name = $self->display_name;
    $self->_index(name_is_changing => ($old_name ne $new_name));
    return $rv;
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

sub shares_account {
    my $self = shift;
    my %p = @_;
    my $intersect_with = delete $p{intersect_with};

    my $t = time_scope 'user_shares_acct';

    my $sql = q{
        SELECT into_set_id 
        FROM user_set_path 
        WHERE from_set_id = ?
          AND into_set_id }.PG_ACCT_FILTER.q{
          AND into_set_id in (
            SELECT DISTINCT into_set_id 
            FROM user_set_path 
            WHERE from_set_id = ?
              AND into_set_id }.PG_ACCT_FILTER
          . ') 
          LIMIT 1';
    my @args = ($self->user_id, $intersect_with);

   return sql_singlevalue($sql, @args);
}

sub accounts {
    my $self = shift;
    my %p = @_;
    my $plugin = delete $p{plugin};
    my $intersect_user = delete $p{intersect_with};

    require Socialtext::Account;
    my @args = ($self->user_id);
    my $sql;

    my $t = time_scope 'user_accts';

    if ($plugin) {
        $sql = q{
            SELECT DISTINCT user_set_id
            FROM user_set_plugin plug
            JOIN user_set_path path
                ON (plug.user_set_id = path.into_set_id)
            WHERE path.from_set_id = ?
              AND plug.plugin = ?
              AND plug.user_set_id }.PG_ACCT_FILTER;
        push @args, $plugin;
    }
    else {
        $sql = q{
            SELECT DISTINCT into_set_id 
            FROM user_set_path 
            WHERE from_set_id = ?
              AND into_set_id }.PG_ACCT_FILTER;
    }
    if ($intersect_user) {
        $sql .= q{ AND into_set_id in (
            SELECT DISTINCT into_set_id 
            FROM user_set_path 
            WHERE from_set_id = ?
              AND into_set_id }.PG_ACCT_FILTER
          . ')';
        push @args, $intersect_user;
    }

    my $cache_string = join "\0", @args;
    my $acct_ids;
    my $cache = $self->_user_acct_cache;
    if ($acct_ids = $cache->get($cache_string)){
        require Clone;
        # ensure callers don't modify the cache:
        $acct_ids = Clone::clone $acct_ids unless wantarray;
    }
    else {
        my $sth = sql_execute($sql, @args);
        $acct_ids = [map {$_->[0] - ACCT_OFFSET} @{$sth->fetchall_arrayref()}];
        $cache->set($cache_string, $acct_ids);
    }
    if ($p{ids_only}) {
        return (wantarray ? @$acct_ids : $acct_ids);
    }
    else {
        my @accounts = lsort_by name =>
                       map {
                           Socialtext::Account->new(account_id => $_)
                       } @$acct_ids;
        return (wantarray ? @accounts : \@accounts);
    }
}

sub _user_acct_cache { Socialtext::Cache->cache('user_accts') }

sub clear_cache {
    shift->_user_acct_cache->clear;
}

sub is_in_account {
    my $self = shift;
    my $account = shift;
    return $account->has_user($self);
}

sub shared_accounts {
    my ($self, $user) = @_;
    my %mine = map { $_->account_id => 1 } $self->accounts;
    my @accounts = grep { $mine{$_->account_id} } $user->accounts;
    return (wantarray ? @accounts : \@accounts);
}

sub shared_groups {
    my $self          = shift;
    my $user          = shift;
    my $inc_self_join = shift || 1; # defaults to true
    my $ignore_badmin = shift || 0;

    my $group_cursor = $self->groups;
    
    my @shared_groups;
    while (my $g = $group_cursor->next) {
        my $is_shared = $inc_self_join
            ? $g->user_can(
                user => $user,
                permission => ST_READ_PERM,
                ignore_badmin => $ignore_badmin)
            : $g->has_user($user);

        push @shared_groups, $g if $is_shared;
    }
    return (wantarray ? @shared_groups : \@shared_groups);
}

sub group_count {
    my $self = shift;
    my %p = @_;

    my @bind = ($self->user_set_id);
    my $add_where = '';
    if ($p{plugin}) {
        $add_where = q{
          AND user_set_id IN (
            SELECT user_set_id
              FROM user_set_plugin_tc
             WHERE plugin = ?
          )
        };
        push @bind, $p{plugin};
    }

    return sql_singlevalue(qq{
        SELECT COUNT(DISTINCT(into_set_id))
          FROM user_set_path
         WHERE into_set_id }.PG_GROUP_FILTER.qq{
           AND from_set_id = ? $add_where
    },@bind);
}

sub groups {
    my $self = shift;
    my %p = @_;

    my $t = time_scope 'groups_4user';

    my @bind = ($self->user_set_id);

    # discoverable: exclude   - groups i'm a member of (CURRENT)
    # discoverable: include   - non-private groups + groups i'm a member of
    # discoverable: only      - non-private groups - groups i'm a member of
    # discoverable: public    - non-private groups

    my $conditions = '0 = 1';
    my $path_sub_query = q{
        SELECT into_set_id
          FROM user_set_path
         WHERE from_set_id = ?
    };

    # Using an EXISTS with a join happening in the subquery seems to be
    # reasonably fast so long as the into_set_ids are bounded with the account
    # filter.  On staging, this is about 30% faster than using a second nested
    # EXISTS, but staging doesn't have that many groups.  On prod, the cost of
    # the sub-query is a bit higher initially but should be more "stable" as
    # the number of groups grow.
    #
    # Ideally this should be targetting the "groups_permission_set_non_priv"
    # index in the 'discoverable=public' case and the "groups_permission_set"
    # index in the 'only' and 'include' cases.  For systems with small numbers
    # of groups (<1000) Pg will probably do a seq-scan since the whole table
    # fits into cache.
    my $discoverable_clause = q{(
        permission_set <> 'private'
        AND EXISTS (
            -- an account is shared by this user and the group:
            SELECT 1
            FROM user_set_path g_path, user_set_path u_path
            WHERE g_path.from_set_id = g.user_set_id
              AND g_path.into_set_id }.PG_ACCT_FILTER.q{
              AND u_path.from_set_id = ?
              AND u_path.into_set_id }.PG_ACCT_FILTER.q{
              AND u_path.into_set_id = g_path.into_set_id
        )
    )};

    my $d = $p{discoverable};
    if (not $d or $d eq 'exclude') {
        $conditions = qq{user_set_id IN ($path_sub_query)}
    }
    elsif ($d eq 'only') {
        $conditions =
            qq{user_set_id NOT IN ($path_sub_query) AND $discoverable_clause};

        push @bind, $self->user_set_id;
    }
    elsif ($d eq 'include') {
        $conditions = 
            qq{user_set_id IN ($path_sub_query) OR $discoverable_clause};

        push @bind, $self->user_set_id;
    }
    elsif ($d eq 'public') {
        $conditions = $discoverable_clause;
    }
    else {
        die "unknown 'discoverable' filter: '$d'\n";
    }

    my $plugin_condition = '1=1';
    if ($p{plugin}) {
        # The plugin check used to be part of the IN clauses above as its own
        # "user_set_id IN ( ... ) condition.  It was moved to the top of the
        # query, and made an EXISTS condition, so that we could filter
        # discoverable groups by plugins as well.
        $plugin_condition = q{
            EXISTS (
                SELECT 1 FROM user_set_plugin_tc ustp
                WHERE plugin = ? AND g.user_set_id = ustp.user_set_id
            )
        };
        push @bind, $p{plugin};
    }

    my $limit = '';
    my $offset = '';

    if ($p{limit}) {
        $limit = 'LIMIT ?';
        push @bind, $p{limit};
    }

    if ($p{offset}) {
        $offset = 'OFFSET ?';
        push @bind, $p{offset};
    }

    my $order_by = $p{no_order} ? '' : 'ORDER BY lower(driver_group_name)';

    my $sth = sql_execute(qq{
        SELECT group_id, driver_group_name
          FROM groups g
         WHERE $conditions
           AND $plugin_condition
         $order_by $limit $offset
    },@bind);

    my $apply = $p{ids_only}
        ? sub { $_[0][0] }
        : $p{minimal}
            ? sub { { group_id => $_[0][0], name => $_[0][1] } }
            : sub { Socialtext::Group->GetGroup( group_id => $_[0][0] ) };

    return Socialtext::MultiCursor->new(
        iterables => [ $sth->fetchall_arrayref ],
        apply => $apply,
    );
}

sub prefs {
    my $self = shift;
    require Socialtext::Prefs::User;
    return Socialtext::Prefs::User->new(user=>$self);
}

sub to_hash {
    my $self = shift;
    my %args = @_;
    my $t = time_scope 'user_to_hash';

    if ($args{minimal}) {
        return {
            user_id        => $self->user_id,
            username       => $self->username,
            best_full_name => $self->display_name,
            display_name   => $self->display_name,
        };
    }

    my @fields = @public_interface;
    push @fields, @private_interface if ($args{want_private_fields});

    my $hash = {};
    foreach my $attr (@fields) {
        my $value = $self->$attr;
        $value = "" unless defined $value;
        $hash->{$attr} = "$value";
    }
    $hash->{creator_username} = $self->creator->username;

    # There is a _tiny_ possiblilty that there will not be a primary account.
    $hash->{primary_account_name} = ( $self->primary_account_id ) 
        ? $self->primary_account->name
        : undef;

    # This field should never default to ''
    delete $hash->{private_external_id} unless $hash->{private_external_id};
    delete $hash->{password} if ($args{no_password});

    return $hash;
}

sub Create_user_from_hash {
    my $class = shift;
    my $info = shift;

    my $creator
        = Socialtext::User->new( username => $info->{creator_username} );
    $creator ||= Socialtext::User->SystemUser();

    my %create;
    for my $attr (@public_interface, @private_interface) {
        $create{$attr} = Encode::encode_utf8( $info->{$attr} )
            if exists $info->{$attr};
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
    st_log->notice( "created user: $create{email_address}" );
    return $user;
}

{
    Readonly my $spec => { workspace => WORKSPACE_TYPE( default => undef ) };
    sub best_full_name {
        my $self = shift;
        my %p = validate( @_, $spec );

        my $preferred = $self->preferred_name;
        return $preferred if ($preferred);

        my $name = $self->proper_name;
        return $name if length $name;

        return $self->guess_real_name
            unless ($p{workspace} && $p{workspace}->workspace_id != 0);

        return $self->MaskEmailAddress(
            $self->email_address,
            $p{workspace},
        );
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

        croak "Either workspace or user is required"
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

sub FormattedEmail {
    my $class         = shift;
    my $first_name    = shift;
    my $middle_name   = shift;
    my $last_name     = shift;
    my $email_address = shift;

    my $name = Socialtext::User::Base->FormatFullName(
        $first_name, $middle_name, $last_name,
    );

    if (length $name) {
        return $name . ' <' . $email_address . '>';
    }
    else {
        return $email_address;
    }
}

sub workspace_count {
    my $self = shift;
    my %p = (@_==1) ? %{+shift} : @_;
    $p{user_id} = $self->user_id;
    require Socialtext::Workspace;      # lazy-load, to reduce startup impact
    return Socialtext::Workspace::Roles->CountWorkspacesByUserId(%p);
}

sub workspaces {
    my $self = shift;
    require Socialtext::Workspace;      # lazy-load, to reduce startup impact
    return Socialtext::Workspace::Roles->WorkspacesByUserId(
        @_,
        user_id => $self->user_id,
        order_by => 'alpha',
    );
}

sub is_authenticated {
    my $self = shift;
    my $username = $self->username;

    # Yes, this is a whole lot wordier than it needs to be, but it leaves us a
    # breadcrumb for helping figure out why users are having trouble accessing
    # the system.

    # Guest user isn't an authenticated user (they're the *Guest*)
    return 0 if ($username eq $GuestUsername);

    # If they don't have a valid password, we don't treat them as
    # Authenticated.
    unless ($self->has_valid_password()) {
        st_log->info( "user $username has invalid password; not treating as authenticated" );
        return 0;
    }

    # If the User has been de-activated, we never treat them as Authenticated.
    if ($self->is_deactivated) {
        st_log->info( "user $username is deactivated; not treating as authenticated" );
        return 0;
    }

    # If they have any outstanding restrictions (e.g. e-mail confirmation,
    # password change), we don't treat them as Authenticated.
    my @restrictions = map { $_->restriction_type } $self->restrictions->all;
    if (@restrictions) {
        map {
            st_log->info("user $username has outstanding '$_' restriction; not treating as authenticated");
        } @restrictions;
        return 0;
    }

    # Looks good.
    return 1;
}

sub is_guest {
    return not $_[0]->is_authenticated()
}

sub is_deleted {
    my $self = shift;
    return $self->homunculus->isa('Socialtext::User::Deleted');
}

sub default_role {
    my $self = shift;

    return Socialtext::Role->AuthenticatedUser()
        if $self->is_authenticated();

    return Socialtext::Role->Guest();
}

sub is_deactivated {
    my $self = shift;
    require Socialtext::Account;
    my $accts_match = 
        $self->primary_account_id == Socialtext::Account->Deleted()->account_id;

    return $accts_match || $self->is_deleted;
}

# is User data sourced internally (eg. Default), or externally (eg. LDAP)
sub is_externally_sourced {
    my $self = shift;
    return ($self->driver_name eq 'Default') ? 0 : 1;
}

# revoke a user's access to everything
around 'deactivate' => \&sql_txn;
sub deactivate {
    my $self = shift;

    croak 'You may not deactivate ' . $self->username
        if $self->is_system_created;

    if ($self->can_update_store) {
        # disable login
        $self->update_store( password => '*no-password*', no_crypt => 1 );
    }
    else {
        warn loc("user.deactivated") . "\n";
        warn loc("info.login-admin=driver", $self->driver_name) . "\n\n";
    }

    # leaves things referencing this user in place
    my $accounts = $self->accounts;
    try {
        Socialtext::UserSet->new->remove_set($self->user_id, roles_only => 1);
        require Socialtext::Pluggable::Adapter;
        my $adapter = Socialtext::Pluggable::Adapter->new;
        $adapter->make_hub($self);
        foreach my $acct (@$accounts) {
            $adapter->hook(
                'nlw.remove_user_account_role' => [$acct, $self, undef]
            );
        }
    }
    catch {
        die $_ unless (/^node \d+ doesn't exist/);
    };

    # remove them from control and console
    $self->set_business_admin(0);
    $self->set_technical_admin(0);

    # side-effect: re-indexes the profile (which should remove it), adds a
    # "member" Role to the Deleted account.
    require Socialtext::Account;
    $self->primary_account(Socialtext::Account->Deleted());

    $self->_call_hook('nlw.user.deactivate');

    return $self;
}

sub reactivate {
    my $self    = shift;
    my %p       = @_;

    require Socialtext::Account;
    my $deleted = Socialtext::Account->Deleted();

    die "Account is required" unless $p{account} or $p{account_id};
    $p{account_id} ||= $p{account}->account_id;

    # Add the user to a new primary _before_ deleting the old
    $self->primary_account( $p{account_id} );
    $deleted->remove_user( user => $self );

    unless ($self->is_externally_sourced) {
        $self->create_password_change_confirmation;
    }
    $self->_call_hook('nlw.user.activate');
}

sub _index {
    my $self = shift;
    require Socialtext::JobCreator;
    Socialtext::JobCreator->index_person($self, @_);

    $self->_call_hook('nlw.profile.changed');
}

sub _call_hook {
    my $self = shift;
    my $hclass = shift;
    require Socialtext::Pluggable::Adapter;
    my $adapter = Socialtext::Pluggable::Adapter->new;
    $adapter->make_hub($self);
    $adapter->hook($hclass => [$self]);
}

# Class methods

{
    Readonly my $spec => { password => SCALAR_TYPE };
    sub ValidatePassword {
        shift;
        my %p = validate( @_, $spec );

        return ( loc("error.password-too-short") )
            unless length $p{password} >= 6;

        return;
    }
}

sub Search {
    my $class = shift;
    my $search_term = shift;

    return $class->_aggregate('Search', $search_term);
}

sub Resolve {
    my $class = shift;
    my $maybe_user = shift;
    my $user;

    croak "no user identifier specified" unless $maybe_user;

    if (blessed($maybe_user) && $maybe_user->can('user_id')) {
        return $maybe_user;
    }

    # Note to developers fixing this method:
    # I (Luke) think the order should be:
    # email address short circuit
    # check if it's a username
    # check if it's an email
    # otherwise assume it's a user_id

    # SHORT-CIRCUIT: if it looks like a User ID, look that up *first*
    if ($maybe_user =~ /^\d+$/) {
        $user = Socialtext::User->new(user_id => $maybe_user) 
    }
    # SHORT-CIRCUIT: if it looks like an e-mail address, look that up *first*
    elsif ($maybe_user =~ /@/) {
        $user = Socialtext::User->new(email_address => $maybe_user);
    }

    # Search for User if we haven't found him yet.  Common case for lookup is
    # "username" so do that search first.
    $user ||= Socialtext::User->new(username => $maybe_user);
    $user ||= Socialtext::User->new(email_address => $maybe_user);

    croak "no such user '$maybe_user'" unless defined $user;
    return $user;
}

sub ResolveId {
    my $class = shift;
    my $p = (@_==1) ? shift(@_) : {@_};

    foreach my $driver ($class->_drivers) {
        my $subclass = $class->_realize($driver, 'ResolveId');
        if ($subclass) {
            my $res = $subclass->ResolveId( {
                %{$p},
                driver_key => $subclass->driver_key,
            } );
            return $res if $res;
        }
    }
    return;
}

sub Query {
    my $class  = shift;
    my $params = shift;
    my $t      = time_scope('user_query');

    my ($sql, @bind) = sql_abstract->select('users', [qw(user_id)], $params);
    my $sth = sql_execute($sql, @bind);
    my $mc  = Socialtext::MultiCursor->new(
        iterables => [ $sth->fetchall_arrayref ],
        apply     => sub {
            my $row = shift;
            $class->new(user_id => $row->[0]);
        },
    );
    return $mc;
}

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
        regex   => qr/^(?:username|workspace_count|creation_datetime|creator|primary_account)$/,
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
SELECT my.user_id
    FROM users my 
    JOIN "UserMetadata" my_meta ON (my.user_id = my_meta.user_id)
    LEFT JOIN users creator 
        ON (my_meta.created_by_user_id = creator.user_id)
    ORDER BY creator.driver_username $p{sort_order}, 
             my.driver_username $p{sort_order}
    LIMIT ? OFFSET ?
EOSQL
            username => <<EOSQL,
SELECT user_id
    FROM users
    ORDER BY driver_username $p{sort_order}
    LIMIT ? OFFSET ?
EOSQL
            workspace_count => qq!
SELECT users.user_id, COALESCE(workspace_count,0) AS workspace_count
    FROM users
    LEFT JOIN (
        SELECT from_set_id AS user_id,
            COUNT(DISTINCT(into_set_id)) AS workspace_count
          FROM user_set_path
         WHERE into_set_id ! . PG_WKSP_FILTER . qq!
        GROUP BY from_set_id
    ) temp1 USING (user_id)
    ORDER BY workspace_count $p{sort_order},
             users.driver_username ASC
    LIMIT ? OFFSET ?
!,
            user_id => <<EOSQL,
SELECT user_id
    FROM users
    ORDER BY user_id $p{sort_order}
    LIMIT ? OFFSET ?
EOSQL
            primary_account => <<EOSQL,
SELECT user_id
  FROM "UserMetadata"
  JOIN "Account" ON "Account".account_id = "UserMetadata".primary_account_id
 ORDER BY "Account".name $p{sort_order}, user_id ASC
 LIMIT ? OFFSET ?
EOSQL
        );

        return $class->_UserCursor(
            $SQL{ $p{order_by} },
            [qw( limit offset )], %p
        );
    }
}

sub AllTechnicalAdmins {
    my $class = shift;

    my $sql = <<EOSQL;
SELECT user_id
    FROM "UserMetadata"
    WHERE is_technical_admin
EOSQL

    return $class->_UserCursor( $sql, [] );
}

sub AllBusinessAdmins {
    my $class = shift;
    my $sql   = qq{SELECT user_id FROM "UserMetadata" WHERE is_business_admin};
    return $class->_UserCursor($sql, []);
}

{
    Readonly my $spec => {
        %LimitAndSortSpec,
        order_by => SCALAR_TYPE(
            regex =>
                qr/^(?:username|creation_datetime|creator|primary_account)$/,
            default => 'username',
        ),
        account_id            => SCALAR_TYPE,
        direct                => BOOLEAN_TYPE(default => 0),
        exclude_hidden_people => BOOLEAN_TYPE(default => 0),
        ids_only              => BOOLEAN_TYPE(default => 0),
    };
    sub ByAccountId {
        # Returns an iterator of Socialtext::User objects
        my $class = shift;
        my %p = validate( @_, $spec );

        croak 'ByAccountId primary_only flag has been removed. Update the code.'
            if exists $p{primary_only};

        $p{apply} = $p{ids_only}
            ? sub { shift->[0] }
            : sub { Socialtext::User->new(user_id => shift->[0]) };

        # We're supposed to default to DESCending if we're creation_datetime.
        $p{sort_order} ||= $p{order_by} eq 'creation_datetime' ? 'DESC' : 'ASC';

        my @bind = qw( user_set_id limit offset );
        $p{user_set_id} = $p{account_id} + ACCT_OFFSET;
        my $uar_table = $p{direct}
            ? 'user_set_include'
            : 'user_set_path';

        my $exclude_hidden_clause = '';
        if ($p{exclude_hidden_people}) {
            $exclude_hidden_clause = 'WHERE NOT is_profile_hidden';
        }

        Readonly my %SQL => (
            creation_datetime => <<EOSQL,
SELECT DISTINCT(user_id), creation_datetime, driver_username
  FROM users
  JOIN (
      SELECT from_set_id AS user_id
        FROM $uar_table
       WHERE into_set_id = ?
  ) uar USING (user_id)
  JOIN "UserMetadata" USING (user_id)
  $exclude_hidden_clause
 ORDER BY creation_datetime $p{sort_order}, driver_username ASC
 LIMIT ? OFFSET ?
EOSQL
            creator => <<EOSQL,
SELECT DISTINCT u.user_id, u2.driver_username AS creator_name, u.driver_username
  FROM users u
  JOIN (
      SELECT from_set_id AS user_id
        FROM $uar_table
       WHERE into_set_id = ?
  ) uar USING (user_id)
  JOIN "UserMetadata" um USING (user_id)
  LEFT JOIN users u2 ON (um.created_by_user_id = u2.user_id)
  $exclude_hidden_clause
 ORDER BY u2.driver_username $p{sort_order}, u.driver_username ASC
 LIMIT ? OFFSET ?
EOSQL
            username => qq{
SELECT DISTINCT(user_id), driver_username
  FROM users
  JOIN (
      SELECT from_set_id AS user_id
        FROM $uar_table
       WHERE into_set_id = ?
  ) uar USING (user_id)
  $exclude_hidden_clause
 ORDER BY driver_username $p{sort_order}
 LIMIT ? OFFSET ?
},
            primary_account => <<EOSQL,
SELECT DISTINCT u.user_id, acct.name, u.driver_username
  FROM users u
  JOIN (
      SELECT from_set_id AS user_id, into_set_id AS account_set_id
        FROM $uar_table
       WHERE into_set_id = ?
  ) uar USING (user_id)
  JOIN "Account" acct ON (acct.user_set_id = account_set_id)
  $exclude_hidden_clause
 ORDER BY acct.name $p{sort_order}, u.driver_username ASC
 LIMIT ? OFFSET ?
EOSQL
        );

        return $class->_UserCursor( $SQL{ $p{order_by} }, \@bind, %p );
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
        direct => BOOLEAN_TYPE(default => undef),
        apply => { type => CODEREF, optional => 1 },
        ids_only => BOOLEAN_TYPE( default => 0),
    };

    sub ByWorkspaceId {
        # Returns an iterator of [Socialtext::User, Socialtext::Role] arrays
        my $class = shift;
        my %p = validate( @_, $spec );

        # We're supposed to default to DESCending if we're creation_datetime.
        $p{sort_order} ||= $p{order_by} eq 'creation_datetime' ? 'DESC' : 'ASC';

        my $columns = q{
SELECT DISTINCT user_id,
                role_id,
                driver_username,
                "Role".name as role_name
        };

        my $uwr_table = $p{direct}
            ? 'user_set_include'
            : 'user_set_path';
        my $from = qq{
            users
            JOIN (
                SELECT from_set_id AS user_id,
                       into_set_id - }.PG_WKSP_OFFSET.qq{ AS workspace_id,
                       role_id
                  FROM $uwr_table
                 WHERE into_set_id }.PG_WKSP_FILTER.qq{
            ) uwr USING (user_id)
            JOIN "Role" USING (role_id)
        };

        Readonly my %SQL => (
            username => <<EOSQL,
$columns
    FROM $from
    WHERE workspace_id = ?
    ORDER BY driver_username $p{sort_order}, role_name ASC
    LIMIT ? OFFSET ?
EOSQL
            creation_datetime => <<EOSQL,
$columns, creation_datetime
    FROM $from
    JOIN "UserMetadata" USING (user_id)
    WHERE workspace_id = ?
    ORDER BY creation_datetime $p{sort_order}, driver_username ASC,
        role_name ASC
    LIMIT ? OFFSET ?
EOSQL
            creator => <<EOSQL,
$columns, creator_username
    FROM $from
    JOIN "UserMetadata" USING (user_id)
    JOIN (
        SELECT user_id as creator_id, driver_username as creator_username
        FROM users
    ) creator ON (creator_id = created_by_user_id)
    WHERE workspace_id = ?
    ORDER BY creator_username $p{sort_order}, driver_username ASC,
        role_name ASC
    LIMIT ? OFFSET ?
EOSQL
            role_name => <<EOSQL,
$columns
    FROM $from
    WHERE workspace_id = ?
    ORDER BY role_name $p{sort_order}, driver_username ASC
    LIMIT ? OFFSET ?
EOSQL
        );

        $p{apply} ||= sub {
            my $rows    = shift;
            my $user_id = $rows->[0];
            my $role_id = $rows->[1];

            # short circuit to not hand back undefs in a list context
            return undef if !$user_id;

            return $p{ids_only}
                ? $user_id
                : Socialtext::User->new( user_id => $user_id );
        };

        return $class->_UserCursor(
            $SQL{ $p{order_by} },
            [qw( workspace_id limit offset )],
            %p,
        );
    }
}

sub ByWorkspaceIdWithRoles {
    my ($class, %args) = @_;
    return $class->ByWorkspaceId(
        %args,
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

sub ByUserIds {
    my $class = shift;
    my $ids   = shift;
    return Socialtext::MultiCursor->new(
        iterables => $ids,
        apply     => sub {
            my $id = shift;
            return $class->new( user_id => $id );
        }
    );
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
SELECT DISTINCT users.user_id AS user_id,
                users.driver_key AS driver_key,
                users.driver_unique_id AS driver_unique_id,
                users.driver_username AS driver_username,
                users.driver_username AS driver_username
    FROM users AS users
    WHERE users.driver_username LIKE ?
    ORDER BY users.driver_username $p{sort_order}
    LIMIT ? OFFSET ?
EOSQL
            workspace_count => qq{
SELECT users.user_id AS user_id, workspace_count
    FROM users AS users
    LEFT JOIN (
        SELECT from_set_id AS user_id,
            COUNT(DISTINCT(into_set_id)) AS workspace_count
          FROM user_set_path
         WHERE into_set_id } . PG_WKSP_FILTER . qq{
        GROUP BY from_set_id
    ) temp1 USING (user_id)
    WHERE users.driver_username LIKE ?
    ORDER BY workspace_count $p{sort_order}, users.display_name ASC
    LIMIT ? OFFSET ?
    },
            creation_datetime => <<EOSQL,
SELECT DISTINCT users.user_id AS user_id,
                users.driver_key AS driver_key,
                users.driver_unique_id AS driver_unique_id,
                users.driver_username AS driver_username,
                "UserMetadata".creation_datetime AS creation_datetime,
                users.driver_username AS driver_username
    FROM users AS users, "UserMetadata" AS "UserMetadata"
    WHERE (users.user_id = "UserMetadata".user_id )
        AND  (users.driver_username LIKE ? )
    ORDER BY "UserMetadata".creation_datetime $p{sort_order},
        users.driver_username ASC
    LIMIT ? OFFSET ?
EOSQL
            creator => <<EOSQL,
SELECT DISTINCT(users.user_id) AS aaaaa10000,
        users.driver_username AS driver_username,
        creator.driver_username AS driver_username
    FROM "UserMetadata" AS "UserMetadata"
        LEFT OUTER JOIN users AS creator
            ON "UserMetadata".created_by_user_id
                    = creator.user_id,
               users AS users
    WHERE (users.user_id = "UserMetadata".user_id )
        AND (users.driver_username LIKE ? )
    ORDER BY creator.driver_username $p{sort_order},
        users.driver_username ASC
    LIMIT ? OFFSET ?
EOSQL
            primary_account => <<EOSQL,
SELECT DISTINCT(users.user_id) AS aaaaa10000,
        users.driver_username AS driver_username,
        acct.name AS acct_name
    FROM users
        LEFT JOIN "UserMetadata" USING (user_id)
        LEFT JOIN "Account" acct ON "UserMetadata".primary_account_id = acct.account_id
    WHERE users.driver_username LIKE ? 
    ORDER BY acct.name $p{sort_order},
        users.driver_username ASC
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
            'SELECT COUNT(*) FROM users WHERE driver_username LIKE ?',
            '%' . lc $p{username} . '%' );
        return $sth->fetchall_arrayref->[0][0];
    }
}

sub Count {
    my ( $class, %p ) = @_;

    my $sth = sql_execute('SELECT COUNT(*) FROM users');
    return $sth->fetchall_arrayref->[0][0];
}

# Confirmation methods

sub restrictions {
    my $self = shift;
    return Socialtext::User::Restrictions->AllForUser($self);
}

sub add_restriction {
    my $self = shift;
    my $type = shift;
    my %params = @_;
    return Socialtext::User::Restrictions->CreateOrReplace( {
        user_id          => $self->user_id,
        restriction_type => $type,
        %params,
    } );
}

sub get_restriction {
    my $self = shift;
    my $type = shift;
    return Socialtext::User::Restrictions->Get( {
        user_id          => $self->user_id,
        restriction_type => $type,
    } );
}

sub remove_restriction {
    my $self = shift;
    my $type = shift;
    my $restriction = $self->get_restriction($type);
    $restriction->confirm if ($restriction);
}

sub has_restriction {
    my $self = shift;
    my $type = shift;
    my $restriction = $self->get_restriction($type);
    return $restriction ? 1 : 0;
}

sub is_restricted {
    my $self = shift;
    return $self->restrictions->count;
}

# restriction: email confirmation
sub create_email_confirmation {
    my $self = shift;
    my %params = @_;

    my $workspace_id;
    if ($params{workspace_name}) {
        require Socialtext::Workspace;
        $workspace_id = Socialtext::Workspace->new(name => $params{workspace_name})->workspace_id;
    }
    return $self->add_restriction(
        'email_confirmation',
        workspace_id => $workspace_id,
    );
}

sub email_confirmation {
    my $self = shift;
    return $self->get_restriction('email_confirmation');
}

sub send_confirmation_email {
    my $self = shift;
    my $restriction = $self->get_restriction('email_confirmation');
    $restriction->send if $restriction;
}

sub confirmation_uri {
    my $self = shift;
    my $restriction = $self->email_confirmation;
    return $restriction->uri if $restriction;
}

sub confirm_email_address {
    my $self = shift;
    return $self->remove_restriction('email_confirmation');
}

sub requires_email_confirmation {
    my $self = shift;
    return $self->has_restriction('email_confirmation');
}

# restriction: password change
sub create_password_change_confirmation {
    my $self = shift;
    return $self->add_restriction('password_change');
}

sub password_change_confirmation {
    my $self = shift;
    return $self->get_restriction('password_change');
}

sub send_password_change_email {
    my $self = shift;
    my $restriction = $self->get_restriction('password_change');
    $restriction->send if $restriction;
}

sub password_change_uri {
    my $self = shift;
    my $restriction = $self->get_restriction('password_change');
    return $restriction->uri if $restriction;
}

sub requires_password_change {
    my $self = shift;
    return $self->has_restriction('password_change');
}

# restriction:  require external id
sub requires_external_id {
    my $self = shift;
    return $self->has_restriction('require_external_id');
}

# END restrictions

sub is_plugin_enabled {
    my $self = shift;
    $self->can_use_plugin(@_);
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

sub avatar_is_visible {
    my $self = shift;

    my $people = Socialtext::Pluggable::Adapter->plugin_class('people');
    return 0 unless $people;
    return $people->AvatarIsVisible($self);
}

sub profile_is_visible_to {
    my $self   = shift;
    my $viewer = shift;

    my $people = Socialtext::Pluggable::Adapter->plugin_class('people');
    return 0 unless $people;
    return $people->ProfileIsVisibleTo($self, $viewer);
}

sub primary_account {
    my $self = shift;
    my $new_account = shift;
    my %opts = @_;

    require Socialtext::Account;
    unless ($new_account) {
        return Socialtext::Account->new(account_id => $self->primary_account_id)
            || Socialtext::Account->Unknown;
    }

    die "Cannot change the account of a system-user.\n"
        if $self->is_system_created;

    $new_account = Socialtext::Account->new(account_id => $new_account)
        unless ref($new_account);

    # Only go to the effort of doing the change *if* we're actually moving the
    # User to a new Primary Account.
    unless ($self->primary_account_id == $new_account->account_id) {
        $self->metadata->set_primary_account_id($new_account->account_id);

        Socialtext::Cache->clear('authz_plugin');

        # Update account membership. Business logic says to keep
        # the user as a member of the old account.

        unless ($new_account->has_user($self, direct => 1)) {
            $new_account->add_user(
                user => $self, # use a default role
            );
        }

        $self->_call_hook('nlw.user.primary_account') unless $opts{no_hooks};

        require Socialtext::JobCreator;
        Socialtext::JobCreator->index_person( $self );
    }

    return $new_account;
}

sub can_be_impersonated_by {
    my $self = shift;
    my $actor = shift;

    # Account-level impersonation works at least partially on membership, so
    # it shouldn't be possible to impersonate/be-impersonated with
    # system-created users.
    Socialtext::Exception::Auth->throw(
        "System-created users cannot be impersonated"
    ) if $self->is_system_created;

    Socialtext::Exception::Auth->throw(
        "System-created users cannot impersonate"
    ) if $actor->is_system_created;

    return $self->primary_account->impersonation_ok($actor => $self);
}

sub accounts_and_groups {
    my ($self,%p) = @_;
    $p{plugin} ||= 'people';
    my $t = time_scope('ang_user');

    my $group_count = 0;
    my %acct_group_set;

    my @accounts = lsort_by name =>
        @{$self->accounts(plugin => $p{plugin})};
    for my $acct (@accounts) {
        # List groups this user is in that are directly-connected to the
        # account.
        # Assume that by membership in the account, the group has access to
        # that plugin too.
        my $sth = sql_execute(q{
            SELECT group_id, LOWER(driver_group_name) AS gn
             FROM (
                   SELECT DISTINCT u2g.into_set_id AS user_set_id
                   FROM user_set_path u2g, user_set_include g2a
                   -- "user is in a group..."
                   WHERE u2g.from_set_id = ? -- user
                     AND u2g.into_set_id }.PG_GROUP_FILTER.q{
                   -- ".. and that group is directly in this account"
                     AND g2a.from_set_id = u2g.into_set_id
                     AND g2a.into_set_id = ?
              ) gi
              JOIN groups g USING (user_set_id)
             ORDER BY gn ASC
        }, $self->user_set_id, $acct->user_set_id);

        my @groups;
        for my $row (@{ $sth->fetchall_arrayref() || [] }) {
            $group_count++;
            push @groups, Socialtext::Group->GetGroup(group_id => $row->[0]);
        }
        $acct_group_set{$acct->account_id} = \@groups;
    }

    return (\@accounts,\%acct_group_set,$group_count);
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
no Moose;
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
form.  It will be stored in the DBMS in an encrypted form using SHA-256,
keyed with the current timestamp using the HMAC algorithm.  If you
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

=head2 $user->reload()

Reloads the User object from the DB, including any entries in in-memory caches.

Primarily used for I<testing>; when you're operating at a distance on a User
and need to reload that object quickly to verify the results.

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

=head2 $user->middle_name()

=head2 $user->last_name()

=head2 $user->driver_name()

=head2 $user->creation_datetime()

=head2 $user->last_login_datetime()

=head2 $user->created_by_user_id()

=head2 $user->is_business_admin()

=head2 $user->is_technical_admin()

=head2 $user->is_system_created()

=head2 $user->is_deactivated()

Returns the corresponding attribute for the user.

=head2 $user->accounts()

Returns a list of the accounts associated with the user.  Returns a
list reference in scalar context.

=head2 $user->shared_accounts( $user2 )

Returns a list of the accounts where both $user and $user2 are members.
Returns a list reference in scalar context.

=head2 $user->groups( %params )

Returns a C<Socialtext::MultiCursor> of groups that this user has a role in.

Supports C<discoverable>, C<limit> and C<offset> named parameters.

=head2 $user->shared_groups( $user2 )

Returns a list of the groups where both $user and $user2 are members.
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

This is just a helper method to
`Socialtext::Workspace::Roles->WorkspacesByUserId()`; please
refer to L<Socialtext::Workspace::Roles> for more information.

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

=head2 $user->primary_account( $account )

Sets the primary account this user is assigned to if $account is 
supplied, otherwise it returns the primary account for this user.

=head2 $user->primary_account_id()

Returns the primary account ID for this user.

=head2 $user->can_use_plugin_with( $name => $buddy )

Returns a boolean indicating whether the user can use the given plugin to interact with another user, C<$buddy>.

=head2 $user->deactivate()

Deactivates the user, removing them from all their workspaces, groups and
accounts.  Prevents them from logging in.

=head2 $user->avatar_is_visible()

Returns a boolean indicating whether the user's avatar should be hidden or visible.

=head2 $user->profile_is_visible_to( $viewer )

Returns a boolean indicating whether the user's profile should be visible to
the specified viewer.

=head2 Socialtext::User->Guest()

Returns the user object for the "guest user", which is used when an
end user comes to the application without authentication.

=head2 Socialtext::User->SystemUser()

Returns the user object for the "system user", which should be used as
the user for operations where a user is needed but there is no end
user, like operations done from the CLI (creating a workspace, for
example).

=head2 Socialtext::User->FormattedEmail($first_name, $middle_name, $last_name, $email_address)

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

This method also accepts two additional parameters:

=over 4

=item * primary_only - defaults to FALSE

If set to TRUE, only users for which this is their primary account will be included.

=item * exclude_hidden_people - defaults to FALSE

If set to TRUE, users with a hidden profile will not be included.

=back

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

=head2 Socialtext::User->ByUserIds(PARAMS)

Returns a cursor for all the users with the specified user IDs.

This accepts the same parameters as C<< Socialtext::User->All() >>,
but requires an additional "ids" parameter. This parameter should be
an array ref containing the specified user ids to be returned.

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

=head2 Socialtext::User->ResolveId( { driver_unique_id => $uniq_id } );

Given the low-level driver-unique-id for a User, try to resolve it to the
low-level C<user_id> for said User.

Checks each of the configured User Factories to see if they know about this
User, B<without> actually instantiating the User object; useful as a
peek-ahead to see if we know about a User with this C<driver_unique_id> yet.

=head2 Socialtext::User->Query( $hashref )

Finds User records that match the given hash-ref of field data B<exactly>,
returning a cursor of the records found.

=head2 Socialtext::User->Create_user_from_hash( $hashref )

Create a user from the data in the specified hash.  This routine is used
by import/export scripts.

=head2 $user->create_email_confirmation(%params)

Adds the "email_confirmation" restriction to the User, requiring that they
confirm their e-mail address before they are able to log into the system.

Valid parameters include:

=over

=item workspace_name

Name of Workspace to automatically add the User to as a Member when they have
confirmed their e-mail address.

=back

If the User already has an outstanding e-mail confirmation, it is replaced.

=head2 $user->email_confirmation()

Returns the restriction object for the "e-mail confirmation" restriction.  If
the restriction has not been placed on the User, this method returns
empty-handed.

=head2 $user->send_confirmation_email()

Sends the e-mail message to the User, asking them to confirm their e-mail
address.

If the User does not have the "e-mail confirmation" restriction on their User
record, calling this method does B<nothing>.

=head2 $user->confirmation_uri()

Returns the URI to confirm the User's e-mail address.  If the User is already
confirmed, this method returns empty-handed.

=head2 $user->confirm_email_address()

Confirms the User's e-mail address, and removes the restriction from their
User record.

=head2 $user->requires_email_confirmation()

Returns true if the User has the "e-mail confirmation" restriction on their User
record, returning false otherwise.

=head2 $user->create_password_change_confirmation()

Adds the "password_change" restriction to the User, requiring that they change
their password before they are able to log in to the system.

=head2 $user->password_change_confirmation()

Returns the restriction object for the "need to change your password"
restriction.  If this restriction has not been placed on the User, this method
returns empty-handed.

=head2 $user->send_password_change_email()

Sends an e-mail message to the User, telling them that they need to change the
password on their User record.

If the User does not have the "need to change your password" restriction on
their User record, calling this method does B<nothing>.

=head2 $user->password_change_uri()

Returns the URI to change the User's password.  If the User has already set
their password and no longer has the "need to change your password"
restriction, this method returns empty-handed.

=head2 $user->requires_password_change()

Returns true if the User has the "need to change your password" restriction on
their User record, returning false otherwise.

=head2 $user->requires_external_id()

Returns true if the User has the "requires an external id" restriction on
their User record, returning false otherwise.

=head2 $user->primary_account([$acct])

Returns a C<Socialtext::Account> object for the primary account this 
user is assigned to.

Passing in a new account will change this user's primary account.  The user
will retain whatever Role they had in the old account.

=head2 $user->accounts_and_groups([plugin => 'someplugin'])

Returns three items: the list of accounts this user can see under the
specified plugin, a hash of lists of groups under each of those accounts that
the user is connected to, and finally a count of account-group combinations in
the result.  C<plugin> defaults to 'people'.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005-2008 Socialtext, Inc., All Rights Reserved.

=cut
