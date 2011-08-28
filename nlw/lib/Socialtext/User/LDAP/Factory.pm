package Socialtext::User::LDAP::Factory;
# @COPYRIGHT@

use strict;
use warnings;

use base qw(Socialtext::User::Factory);

use Class::Field qw(field const);
use Socialtext::Encode;
use Socialtext::LDAP;
use Socialtext::User::LDAP;
use Socialtext::Log qw(st_log);
use Socialtext::SQL::Builder qw(sql_abstract);
use Net::LDAP::Util qw(escape_filter_value);
use Net::LDAP::Constant qw(LDAP_NO_SUCH_OBJECT);
use Socialtext::SQL qw(:exec :time);
use Socialtext::Exceptions qw(data_validation_error);
use Socialtext::Timer qw(time_scope);
use Readonly;
use List::MoreUtils qw(part);

# Flag to allow for the long-term caching of LDAP user data in the DB to be
# disabled.
#
# FOR TESTING/INSTRUMENTATION PURPOSES ONLY!!!
#
# This should *NEVER* be disabled in a production environment!
our $CacheEnabled = 1;

# please treat these fields as read-only:

field 'ldap_config'; # A Socialtext::LDAP::Config object

# only connect to the LDAP server when we really need to:
field 'ldap', -init => 'Socialtext::LDAP->new($self->ldap_config)';

field 'driver_id', -init => '$self->ldap_config->id';
const 'driver_name' => 'LDAP';
field 'driver_key', -init => '$self->driver_name . ":" . $self->driver_id';

field 'attr_map', -init => '$self->_attr_map()';

Readonly my %valid_get_user_terms => (
    user_id          => 1,
    username         => 1,
    email_address    => 1,
    driver_unique_id => 1,
);

sub new {
    my ($class, $driver_id) = @_;

    my $config = Socialtext::LDAP->ConfigForId($driver_id);
    return unless $config; # driver configuration is missing

    # create the factory object
    my $self = {
        ldap_config => $config,
    };
    bless $self, $class;
}

# this should create (and thus connect) the LDAP object if this has not
# already happened.
sub connect { return $_[0]->ldap; }

sub _attr_map {
    my $self = shift;
    my %attr_map = %{$self->ldap_config->attr_map()}; # copy!
    $attr_map{driver_unique_id} = delete $attr_map{user_id};

    # The "password" attr_map entry has been deprecated and removed from all
    # docs/code, *but* its still possible that some legacy installs have it
    # set up.  *DON'T* remove this code unless a migration script is put in
    # place that cleans up LDAP configs and removes unknown attributes from
    # the map.
    delete $attr_map{password};

    return \%attr_map;
}

sub GetUser {
    my ($self, $key, $val, %opts) = @_;

    return unless $key && $val;
    return unless ($valid_get_user_terms{$key});

    my $cache_lookup = $opts{preload};

    # Forcably re-enable local LDAP User cache; if we end up following any
    # User lookups for things like profile relationship lookups, we *don't*
    # want to end up chasing circular relationship.  So, break the chain now.
    local $Socialtext::User::LDAP::Factory::CacheEnabled = 1;

    my $proto_user;
    if ($cache_lookup) {
        for my $field (qw/username driver_unique_id email_address/) {
            my $value = $field eq 'username'
                ? $cache_lookup->{driver_username}
                : $cache_lookup->{$field};

            (my $cached_driver = $cache_lookup->{driver_key}) =~ s/:.+$//;
            next if $field eq 'driver_unique_id'
                && $self->driver_name ne $cached_driver;
                
            $proto_user = $self->lookup($field => $value);

            if ($proto_user) {
                $proto_user->{user_id} = $cache_lookup->{user_id};
                $proto_user->{cached_at} = $cache_lookup->{cached_at};
                last;
            }
        }
    }
    else {
        $proto_user = $self->lookup($key => $val);
    }

    return unless $proto_user;

    if ($self->_vivify($proto_user)) {
        return $self->new_homunculus($proto_user);
    }
    else {
        return;
    }
}

sub _mark_as_found {
    my $self  = shift;
    my $homey = shift;
    if ($homey->{missing}) {
        $homey->{missing}   = 0;
        $homey->{cached_at} = $self->Now();
        $self->UpdateUserRecord( {
            user_id   => $homey->{user_id},
            cached_at => $homey->{cached_at},
            missing   => $homey->{missing},
        } );
        st_log->info("LDAP User '$homey->{driver_unique_id}' found");
    }
}

sub lookup {
    my ($self, $key, $val) = @_;
    time_scope 'ldap_user_lookup';

    # SANITY CHECK: lookup term is acceptable
    return unless ($valid_get_user_terms{$key});

    # SANITY CHECK: given a value to lookup
    return unless ((defined $val) && ($val ne ''));

    # EDGE CASE: lookup by user_id
    #
    # The 'user_id' is internal to ST and isn't stored/held in the LDAP
    # server, so we handle this as a special case; grab the data we've got on
    # this user out of the DB and recursively look the user up by each of the
    # possible unique identifiers.
    if ($key eq 'user_id') {
        return if ($val =~ /\D/);   # id *must* be numeric

        my ($unique_id, $username, $email) =
            sql_selectrow(
                q{SELECT driver_unique_id, driver_username, email_address
                   FROM users
                  WHERE driver_key=? AND user_id=?
                },
                $self->driver_key, $val,
            );

        my $user = $self->lookup( driver_unique_id => $unique_id )
                || $self->lookup( username => $username )
                || $self->lookup( email_address => $email );
        return $user;
    }

    # search LDAP directory for our record
    my $mesg = $self->_find_user($key => $val);
    unless ($mesg) {
        die "ST::User::LDAP: no suitable LDAP response\n";
    }

    if ($mesg->code && ($mesg->code != LDAP_NO_SUCH_OBJECT)) {
        die "ST::User::LDAP: LDAP error while finding user $key/$val; " . $mesg->error . "\n";
    }
    if ($mesg->count() > 1) {
        # If we get here, there are duped LDAP records for this field. ST
        # requires that these fields be unique, so be sure to note this.
        die "ST::User::LDAP: found multiple matches for user; $key/$val\n";
    }

    # extract result record
    my $result = $mesg->shift_entry();
    unless ($result) {
        st_log->debug( "ST::User::LDAP: unable to find user in LDAP; $key/$val" );
        return;
    }

    st_log->debug("ST::User::LDAP: found user in LDAP search; $key/$val");
    # instantiate from search results
    my $attr_map = $self->attr_map;
    my $proto_user = {
        driver_key  => $self->driver_key(),
    };
    while (my ($user_attr, $ldap_attr) = each %$attr_map) {
        my $val;
        if ($ldap_attr =~ m{^(dn|distinguishedName)$}) {
            # DN isn't an attribute, its a Net::LDAP::Entry method
            $val = $result->dn();
        }
        else {
            $val = $result->get_value($ldap_attr);
        }
        $val = Socialtext::Encode::guess_decode($val) if (defined $val);
        $proto_user->{$user_attr} = $val;
    }

    return $proto_user;
}

sub cache_is_enabled {
    return $CacheEnabled;
}

sub db_cache_ttl {
    my $self       = shift;
    my $proto_user = shift;

    my $ttl = $proto_user->{missing}
        ? $self->ldap_config->not_found_ttl
        : $self->ldap_config->ttl;

    return DateTime::Duration->new( seconds => $ttl);
}

sub _vivify {
    my ($self, $proto_user) = @_;

    require Socialtext::User;
    require Socialtext::UserMetadata;
    require Socialtext::JobCreator;

    # set some defaults into the proto user
    $proto_user->{driver_key} ||= $self->driver_key;
    $proto_user->{cached_at} = 'now';           # auto-set to 'now'
    $proto_user->{password}  = '*no-password*'; # placeholder password

    # separate out "core" fields from "profile" fields
    my ($user_attrs, $extra_attrs) = 
        Socialtext::User::LDAP->UserFields($proto_user);

    # XXX: some fields are explicitly set to '' elsewhere
    # (ST:U:Def:Factory:create, ST:U:Factory:NewUserRecord), and we're going
    # to do the same here.  Yes, this should be refactored and cleaned up, no,
    # I'm not doing that just yet.
    $user_attrs->{first_name}  ||= '';
    $user_attrs->{middle_name} ||= '';
    $user_attrs->{last_name}   ||= '';

    # don't encrypt the placeholder password; just store it as-is
    $user_attrs->{no_crypt} = 1;

    my $user_id = $proto_user->{user_id} || $self->ResolveId($proto_user);
    if ($user_id) {
        ### Update existing User record

        # Pull existing User record out of DB
        my @user_drivers = Socialtext::User->_drivers();
        my $cached_homey = $self->GetHomunculus('user_id', $user_id, \@user_drivers);

        return 0 unless $cached_homey;

        # Mark the User as cached, so that if we trigger any hooks/plugins
        # during validation/saving that they don't try to re-query the User
        # record again because he looks stale.
        $cached_homey->{cached_at} = $self->Now();
        $self->UpdateUserRecord( {
            user_id   => $cached_homey->{user_id},
            cached_at => $cached_homey->{cached_at},
        } );

        # Validate data from LDAP as changes to cached User record
        #
        # If this fails, use the "last known good" cached data for the User;
        # we know *that* data was good at some point.
        eval {
            $user_attrs->{user_id} = $user_id;
            $user_attrs->{missing} = $cached_homey->{missing};
            $self->ValidateAndCleanData($cached_homey, $user_attrs);
            $self->_check_cache_for_conflict(
                user_id => $cached_homey->{user_id},
                %$user_attrs,
            );
        };
        if (my $e = Exception::Class->caught("Socialtext::Exception::DataValidation")) {
            # record error(s)
            st_log->warning("Unable to refresh LDAP user '$cached_homey->{username}':");
            foreach my $err ($e->messages) {
                st_log->warning(" * $err");
            }
            # return "last known good" cached data for the User
            %{$proto_user} = %{$cached_homey};
            return 1;
        }
        elsif ($@) {
            # some other kind of error; re-throw it.
            die $@;
        }

        # Update cached User record in DB
        my $old_name = $cached_homey->{display_name};
        my $new_name = $user_attrs->{display_name}; # set by Validate above
        $user_attrs->{driver_username} = delete $user_attrs->{username};    # map "object -> DB"
        $self->UpdateUserRecord($user_attrs);
        $self->_mark_as_found($user_attrs);
        Socialtext::JobCreator->index_person(
            $user_attrs->{user_id},
            run_after        => 10,
            priority         => 60,
            name_is_changing => ($old_name ne $new_name),
        );
    }
    else {
        ### Create new User record

        # validate/clean the data we got from LDAP
        $self->ValidateAndCleanData(undef, $user_attrs);

        # create User record, and update cached data
        $user_attrs->{driver_username} = delete $user_attrs->{username};    # map "object -> DB"
        $self->NewUserRecord($user_attrs);

        # set up the UserMetadata for the new User record.
        my $user_metadata = Socialtext::UserMetadata->create(
            user_id                 => $user_attrs->{user_id},
            email_address_at_import => $user_attrs->{email_address},
            created_by_user_id      => Socialtext::User->SystemUser->user_id,
        );

        # trigger an initial indexing of the User record
        Socialtext::JobCreator->index_person(
            $user_attrs->{user_id},
            run_after => 10,
        );
    }

    $user_attrs->{username} = delete $user_attrs->{driver_username};        # map "DB -> object"
    $user_attrs->{extra_attrs} = $extra_attrs;
    %$proto_user = %$user_attrs;
    return 1;
}

sub _check_cache_for_conflict {
    my $self = shift;
    my %attrs = @_;

    # the 'users_driver_unique_id' IX in the 'users' table.
    my @driver_unique_id = (
        '-and' => [
            driver_key => $attrs{driver_key},
            driver_unique_id => $attrs{driver_unique_id},
        ],
    );

    # the 'users_lower_username_driver_key' IX in the 'users' table.
    my @username_driver_key = (
        '-and' => [
            driver_key => $attrs{driver_key},
            driver_username => lc($attrs{username}),
        ],
    );

    # the 'users_lower_email_address_driver_key' in the 'users' table.
    my @email_driver_key = (
        '-and' => [
            driver_key => $attrs{driver_key},
            email_address => lc($attrs{email_address}),
        ],
    );

    my ($sql, @bind) = sql_abstract()->select('users', 'COUNT(1)', {
        '-and' => [ 
            user_id => {'-!=' => $attrs{user_id}},
            '-or' => [
                @email_driver_key,
                @username_driver_key,
                @driver_unique_id,
            ],
        ],
    });

    my $rows = sql_singlevalue($sql, @bind);
    data_validation_error errors => ['Cached user already exists values']
        if $rows;
}

sub Search {
    my ($self, $term) = @_;

    # SANITY CHECK: have inbound parameters
    return unless $term;
    $term = escape_filter_value($term);

    # Searchable fields (matching up with those that are searched in the DB in
    # ST::User::Default::Factory).
    #
    # Note that we specifically do *NOT* search any "dn"-like fields (e.g. dn,
    # ou, etc); some LDAP directories don't allow for sub-string searches to
    # be done against those fields (and its easier for us to just ignore the
    # obvious ones than to query LDAP for the schemas and figure out which
    # ones they are).
    my @searchable_attrs = qw(
        username
        email_address
        first_name
        last_name
    );

    # build up the LDAP search filter
    my $attr_map = $self->attr_map;
    my %search   =
        map { $_ => "*$term*" }
        map { $attr_map->{$_} }
        @searchable_attrs;
    my $filter   = Socialtext::LDAP->BuildFilter(
        global => $self->ldap_config->filter(),
        search => \%search,
    );

    # build up the search options
    my %options = (
        base    => $self->ldap_config->base(),
        scope   => 'sub',
        filter  => $filter,
        attrs   => [ values %$attr_map ],
    );

    # execute search against LDAP directory
    my $ldap = $self->ldap();
    return unless $ldap;
    my $mesg = $ldap->search( %options );

    unless ($mesg) {
        st_log->error( "ST::User::LDAP; no suitable LDAP response" );
        return;
    }
    if ($mesg->code()) {
        my $err = "ST::User::LDAP; LDAP error while performing search; "
                . $mesg->error();
        st_log->error($err);
        return;
    }

    # extract search results
    require Socialtext::User;
    my @users;
    foreach my $rec ($mesg->entries()) {
        my $email  = $rec->get_value($attr_map->{email_address});
        my $first  = $rec->get_value($attr_map->{first_name});
        my $middle = $rec->get_value($attr_map->{middle_name});
        my $last   = $rec->get_value($attr_map->{last_name});
        push @users, {
            driver_name     => $self->driver_key(),
            email_address   => $email,
            name_and_email  => 
                Socialtext::User->FormattedEmail($first, $middle, $last, $email),
        };
    }
    return @users;
}

sub _is_dn_search_in_base {
    my $self = shift;
    my $search_attr = shift;
    my $dn = shift;
  
    return 0 unless ($search_attr =~ m{^(dn|distinguishedName)$});

    my $base = $self->ldap_config->base;
    return $dn =~ /\Q$base\E$/;
}

sub _find_user {
    my ($self, $key, $val) = @_;
    my $attr_map = $self->attr_map();

    # map the ST::User key to an LDAP attribute, aborting if it isn't a mapped
    # attribute
    my $search_attr = $attr_map->{$key};
    return unless $search_attr;

    # build up the search options
    my %options = (
        attrs => [ values %$attr_map ],
    );
    if ($self->_is_dn_search_in_base($search_attr, $val)) {
        # DN searches are best done as -exact- searches
        $options{'base'}    = $val;
        $options{'scope'}   = 'base';
        $options{'filter'}  = Socialtext::LDAP->BuildFilter(
            global => $self->ldap_config->filter,
        );
    }
    else {
        # all other searches are done as sub-tree under Base DN
        $options{'base'}    = $self->ldap_config->base();
        $options{'scope'}   = 'sub';
        $options{'filter'}  = Socialtext::LDAP->BuildFilter(
            global => $self->ldap_config->filter,
            search => {
                $search_attr => escape_filter_value($val),
            },
        );
    }

    my $ldap = $self->ldap;
    return unless $ldap;
    return $self->ldap->search( %options );
}


1;

=head1 NAME

Socialtext::User::LDAP::Factory - A Socialtext LDAP User Factory

=head1 SYNOPSIS

  use Socialtext::User::LDAP::Factory;

  # create a default LDAP factory
  $factory = Socialtext::User::LDAP::Factory->new();

  # create a LDAP factory for named LDAP configuration
  $factory = Socialtext::User::LDAP::Factory->new('My LDAP Config');

  # use the factory to find user records
  $user = $factory->GetUser( user_id => $user_id );
  $user = $factory->GetUser( username => $username );
  $user = $factory->GetUser( email_address => $email );

  # user search
  @results = $factory->Search( 'foo' );

=head1 DESCRIPTION

C<Socialtext::User::LDAP::Factory> provides a User factory for user records
that happen to exist in an LDAP data store.  Copies of retrieved users are
stored in the "users" table, creating a "long-term cache" of LDAP user
information (with the exception of passwords and authentication).  See
L<GetUser($key, $val)> for details.

=head1 METHODS

=over

=item B<Socialtext::User::LDAP::Factory-E<gt>new($driver_id)>

Creates a new LDAP user factory, for the named LDAP configuration.

If no LDAP configuration name is provided, the default LDAP configuration will
be used.

=item B<driver_name()>

Returns the name of the driver this Factory implements, "LDAP".

=item B<driver_id()>

Returns the unique ID of the LDAP configuration instance used by this Factory.
e.g. "0deadbeef0".

=item B<driver_key()>

Returns the full driver key ("name:id") of the LDAP instance used by this
Factory.  e.g. "LDAP:0deadbeef0".

=item B<ldap()>

Returns the C<Socialtext::LDAP> for this factory.

=item B<connect()>

The same as C<ldap()>, but ensures that it is connected.

=item B<ldap_config()>

Returns the C<Socialtext::LDAP::Config> for this factory.

=item B<attr_map()>

Returns the mapping of Socialtext user attributes (as they appear in the DB)
to their respective LDAP representations.

This B<is> different than the mapping returned by 
C<< Socialtext::LDAP::Config->attr_map() >> in that this mapping is
specifically targetted towards the underlying database representation of the
user attributes.

=item B<cache_ttl()>

Returns a C<DateTime::Duration> object representing the TTL for this Factory's
LDAP data.

=item B<cache_not_found_ttl()>

Returns a C<DateTime::Duration> object representing the "Not Found TTL" for
this Factory's LDAP data.

=item B<ResolveId(\%params)>

Attempts to resolve the C<user_id> for the User represented by the given
C<\%params>.

For LDAP Users, we do an extended lookup to see if we can find the User by any
one (or more) of:

=over

=item * driver_unique_id (their dn)

=item * driver_username

=item * email_address

=back

If any one of these match and can be found, we can be confident that we've
found a matching User (we're still limiting ourselves to B<just> Users from
this LDAP factory instance, so we're not doing cross-factory resolution).

If the LDAP administrator re-uses somebodies username or e-mail address for a
completely different User we'll mismatch, but that's the risk we take.

=item B<GetUser($key, $val)>

Searches for the specified user in the LDAP data store and returns a new
C<Socialtext::User::LDAP> Homunculus object representing that user if it
exists.  

Long-term caching of LDAP users is implemented by storing user
records in the "users" database table.

The long-term cache is checked before connecting to the LDAP server..  If a
user is not found in the cache, or the cached copy has expired, the user is
retrieved from the LDAP server.  If the retrieval is successful, the details
of that user are stored in the long-term cache.

If the cached copy has expired, and the LDAP server is unreachable, the cached
copy is used.

If a user has been used on this system, but is no longer present in the LDAP
directory, a C<Socialtext::User::Deleted> Homunculus is returned.

User lookups can be performed by I<one> of:

=over

=item * user_id => $user_id

=item * driver_unique_id => $driver_unique_id

=item * username => $username

=item * email_address => $email_address

=back

=item B<lookup($key, $val)>

Looks up a user in the LDAP data store and returns a hash-ref of data on that
user.

Lookups can be performed using the same criteria as listed for C<GetUser()>
above.

The long-term cache is B<not> consulted when using this method.

=item B<Search($term)>

Searches for user records where the given search C<$term> is found in any one
of the following fields:

=over

=item * username

=item * email_address

=item * first_name

=item * last_name

=back

The search will return back to the caller a list of hash-refs containing the
following key/value pairs:

=over

=item driver_name

The unique driver key for the instance of the data store that the user was
found in.  e.g. "LDAP:0deadbeef0".

=item email_address

The e-mail address for the user.

=item name_and_email

The canonical name and e-mail for this user, as produced by
C<< Socialtext::User->FormattedEmail() >>.

=back

The long-term cache is B<not> consulted when using this method.

=back

=head1 AUTHOR

Socialtext, Inc.  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2005-2008 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
