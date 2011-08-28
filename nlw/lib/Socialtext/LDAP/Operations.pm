package Socialtext::LDAP::Operations;
# @COPYRIGHT@
use Moose;

use Guard qw(scope_guard);
use List::MoreUtils qw(uniq);
use Socialtext::LDAP;
use Socialtext::Log qw(st_log);
use Socialtext::SQL qw(sql_execute sql_txn);
use Socialtext::SQL::Builder qw(sql_abstract);
use Socialtext::Group;
use Socialtext::Group::Factory;         # needed for cache/async over-ride
use Socialtext::User::LDAP::Factory;    # needed for cache/async over-ride
use Net::LDAP::Control::Paged;
use Net::LDAP::Constant qw(LDAP_CONTROL_PAGED);

# Tweakable from *unit tests*
our $LDAP_PAGE_SIZE = 500;

###############################################################################
# Refreshes existing LDAP Users.
sub RefreshUsers {
    my ($class, %opts) = @_;
    my $force         = $opts{force};
    my $want_email    = $opts{email};
    my $want_username = $opts{username};

    # Disable cache freshness checks if we're forcing the refresh of all
    # users.
    local $Socialtext::User::LDAP::Factory::CacheEnabled = 0     if ($force);
    local $Socialtext::Pluggable::Plugin::People::Asynchronous=0 if ($force);

    # Get the list of LDAP users *directly* from the DB.
    #
    # Order this by "driver_key" so that we'll group all of the LDAP lookups
    # for a single server together; if we spread them out we risk having the
    # LDAP connection time out in between user lookups.
    st_log->info( "getting list of LDAP users to refresh" );
    my ($sql, @bind) = sql_abstract->select('users',
        [qw( driver_key driver_unique_id driver_username )],
        {
            driver_key => { '~*' => 'LDAP' },
            (
                $want_email ? (email_address => $want_email) : ()
            ),
            (
                $want_username ? (driver_username => lc($want_username)) : ()
            ),
        },
        [qw( driver_key driver_username )],
    );

    my $sth = sql_execute($sql, @bind);
    st_log->info( "... found " . $sth->rows . " LDAP users" );

    my $rows_aref = $sth->fetchall_arrayref();
    $sth->finish();

    # Refresh each of the LDAP Users
    foreach my $row (@{$rows_aref}) {
        my ($driver_key, $unique_id, $driver_username) = @{$row};

        # Enable the general User cache (if its not already enabled), breaking
        # possible recursion chains when chasing relationships).
        #
        # We want each User to get refreshed from LDAP (thus clearing the
        # cache between lookups), but in any single lookups we only want a
        # User to get looked up *once*) (thus enabling general User cache).
        local $Socialtext::User::Cache::Enabled = 1;
        scope_guard { Socialtext::User::Cache->Clear };

        # refresh the user data from the Factory
        st_log->info( "... refreshing: $driver_username" );
        my $homunculus = eval {
            sql_txn { Socialtext::User->new(driver_unique_id => $unique_id) };
        };
        if ($@) {
            st_log->error($@);
        }
    }

    # All done.
    st_log->info( "done" );
}

###############################################################################
# Loads Users from LDAP into Socialtext.
sub LoadUsers {
    my ($class, %opts) = @_;
    my $dryrun        = $opts{dryrun};
    my $want_email    = $opts{email};
    my $want_username = $opts{username};

    # SANITY CHECK: make sure that *ALL* of the LDAP configurations have a
    # "filter" specified.
    my @configs = Socialtext::LDAP::Config->load();
    my @missing_filter = grep { !$_->filter } @configs;
    if (@missing_filter) {
        foreach my $cfg (@missing_filter) {
            my $ldap_id = $cfg->id();
            st_log->error("no LDAP filter in config '$ldap_id'; aborting");
        }
        return;
    }

    # Query the LDAP servers to get a list of e-mail addresses for all of the
    # User records that they contain.
    my @emails;
    st_log->info( "getting list of LDAP users to load" );
    foreach my $cfg (@configs) {
        # figure out which LDAP attributes we need to query
        my $mail_attr     = $cfg->attr_map->{email_address};
        my $username_attr = $cfg->attr_map->{username};

        # the basic/unchanging parts of the query that we're going to ask
        my %query = (
            attrs    => [$mail_attr],        # get their e-mails
            callback => sub {
                # gather the e-mails out of the response
                my ($search, $entry) = @_;
                push @emails, $entry->get_value($mail_attr) if $entry;
            },
        );

        # grab Users by "first letter of their e-mail address", so that we
        # reduce the chance of ever hitting an LDAP hard limit (where it'd
        # simply be *impossible* for us to ask a single LDAP query to get back
        # the list of Users, paged or otherwise).  Note, that substring
        # searches by e-mail should be case IN-sensitive (thankfully).
        #
        # Once we're done grabbing the letters we're expecting, we'll need to
        # do *one last* query to get "anyone else we may have missed"
        # (basically "anything that wasn't matched by an earlier query").
        eval {
            my $ldap = Socialtext::LDAP->new($cfg);

            # Build up the full list of clauses to "get everyone by the first
            # letter of their e-mail address, and *then* get anyone that
            # didn't match any of the above".
            my @filters = map { "($mail_attr=$_*)" } ('a'..'z', '0'..'9');
            {
                local $" = '';
                push @filters, "(!(|@filters))";
            }

            # IF we're looking for a single specific User, over-ride the
            # filters to search for *just* that one User
            if ($want_email) {
                @filters = ("($mail_attr=$want_email)");
            }
            if ($want_username) {
                @filters = ("($username_attr=$want_username)");
            }

            # Execute all the queries, and load all of the Users
            foreach my $f (@filters) {
                $class->_paged_ldap_query(
                    %query,
                    ldap   => $ldap,
                    filter => $f,
                );
            }
        };
        if ($@) {
            my $err = $@;
            st_log->error($err);
            return;
        }
    }

    # Uniq-ify the list of e-mails.
    @emails = uniq(@emails);

    my $total_users = scalar @emails;
    st_log->info( "... found $total_users LDAP users to load" );

    # If we're doing a dry-run, log info on the Users found and STOP!
    if ($dryrun) {
        foreach my $addr (@emails) {
            st_log->info("... found: $addr");
        }
        return;
    }

    # Instantiate/vivify all of the Users.
    my $users_loaded = 0;
    foreach my $email (@emails) {
        st_log->info("... loading: $email");
        my $user = eval {
            sql_txn { Socialtext::User->new(email_address => $email) };
        };
        if ($@) {
            st_log->error($@);
        }
        elsif (!$user) {
            st_log->error("unable to instantiate user with address '$email'");
        }
        else {
            $users_loaded++;
        }
    }
    st_log->info("Successfully loaded $users_loaded out of $total_users total LDAP Users");
    return $users_loaded;
}

###############################################################################
# Issue a paged LDAP query.
sub _paged_ldap_query {
    my ($class, %opts) = @_;
    my $ldap   = $opts{ldap}   || die "_paged_ldap_query() requires 'ldap'";
    my $filter = $opts{filter} || die "_paged_ldap_query() requires 'filter'";
    my $attrs  = $opts{attrs}  || ['*'];
    my $callback = $opts{callback} || die "_paged_ldap_query() requires 'callback'";

    my $page = Net::LDAP::Control::Paged->new(size => $LDAP_PAGE_SIZE);
    my %args = (
        base     => $ldap->config->base(),
        scope    => 'sub',
        filter   => $filter,
        attrs    => $attrs,
        callback => $callback,
        control  => [$page],
    );

    while (1) {
        my $mesg = $ldap->search(%args);

        # fail/abort on *any* error (play it safe)
        unless ($mesg) {
            my $ldap_id = $ldap->config->id();
            die "no response from LDAP server '$ldap_id'; aborting\n";
        }
        if ($mesg->code) {
            my $err = $mesg->error();
            die "error while searching for Users, aborting; $err\n";
        }

        # get cookie from paged control so we can get next page of results
        my ($resp) = $mesg->control(LDAP_CONTROL_PAGED) or last;
        my $cookie = $resp->cookie() or last;
        $page->cookie($cookie);
    }
}

###############################################################################
# Refreshes existing LDAP Groups.
sub RefreshGroups {
    my ($class, %opts) = @_;
    my $force   = $opts{force};
    my $want_id = $opts{id};

    # Disable cache freshness checks if we're forcing the refresh of all
    # Groups.
    local $Socialtext::Group::Factory::CacheEnabled = 0 if ($force);
    local $Socialtext::Group::Factory::Asynchronous = 0 if ($force);
    # Get the list of LDAP Groups *directly* from the DB.
    #
    # Order this by "driver_key" so that we'll group all of the LDAP lookups
    # for a single server together; if we spread them out we risk having the
    # LDAP connection time out between lookups.
    st_log->info( "getting list of LDAP groups to refresh" );
    my ($sql, @bind) = sql_abstract->select('groups',
        [qw( group_id driver_key driver_unique_id driver_group_name )],
        {
            driver_key => { '~*' => 'LDAP' },
            (
                $want_id ? (group_id => $want_id) : (),
            ),
        },
        [qw( driver_key driver_group_name )],
    );

    my $sth = sql_execute($sql, @bind);
    st_log->info( "... found " . $sth->rows . " LDAP groups" );

    my $rows = $sth->fetchall_arrayref({});
    $sth->finish();

    # Refresh each of the LDAP Groups
    foreach my $row (@{$rows}) {
        # get the LDAP group factory we need for this Group.
        my $factory = _get_group_factory($row->{driver_key});
        next unless $factory;

        # refresh the Group data from the Factory
        st_log->info(
            "... refreshing: $row->{driver_group_name} ($row->{group_id})");

        my $homunculus = eval {
            $factory->GetGroupHomunculus(
                driver_unique_id => $row->{driver_unique_id}
            );
        };
        if ($@) {
            st_log->error($@);
        }
    }
    _clear_group_factory_cache();

    # All done.
    st_log->info( "done" );
}

###############################################################################
sub ListGroups {
    my ($class, %opts) = @_;
    my @driver_ids = $opts{driver} ? ($opts{driver}) : ();

    # If no driver was provided, list the Groups for *all* drivers
    unless (@driver_ids) {
        @driver_ids =
            map  { s/^LDAP://; $_ }
            grep { /^LDAP:/ }
            Socialtext::Group->Drivers();
    }

    # List the Groups in each of the LDAP Group Factory drivers
    foreach my $id (@driver_ids) {
        my $factory = Socialtext::Group->Factory(
            driver_name => 'LDAP',
            driver_id   => $id,
        );

        unless ( $factory ) {
            warn "No factory for Driver '$id'\n";
            next;
        }

        print "Factory: " . $factory->driver_id . "\n";

        my @available = $factory->Available(all => 1);
        if (@available) {
            foreach my $listing (@available) {
                # prettify this, rather than showing "0|1"
                $listing->{already_created} =
                    $listing->{already_created} ? 'yes' : 'no';

                print "\tGroup: $listing->{driver_group_name}\n";
                print "\t\tmembers : $listing->{member_count}\n";
                print "\t\tcreated : $listing->{already_created}\n";
                print "\t\tldap-dn : $listing->{driver_unique_id}\n";
                print "\n";
            }
        }
        else {
            print "\tNo Groups found\n";
        }
        print "\n";
    }
}

###############################################################################
# Subroutine:   _get_group_factory($driver_key)
###############################################################################
# Gets the LDAP Group Factory to use for the given '$driver_key'.  Caches the
# Factory for later re-use, so that we're not opening a new LDAP connection
# for each and every group lookup.
###############################################################################
{
    my %Factories;
    sub _get_group_factory {
        my $driver_key = shift;

        # create a new Factory if we don't have a cached one yet
        unless ($Factories{$driver_key}) {
            # instantiate a new LDAP Group Factory
            my ($driver_id) = ($driver_key =~ /LDAP:(.*)/);
            st_log->info( "creating new LDAP Group Factory, '$driver_id'" );
            my $factory
                = Socialtext::Group->Factory(driver_key => "LDAP:$driver_id");
            unless ($factory) {
                st_log->error( "unable to find LDAP config '$driver_id'; was it removed from your LDAP config?" );
                return;
            }

            # make sure we can actually connect to the LDAP server
            unless ($factory->ldap()) {
                st_log->error( "unable to connect to LDAP server" );
                return;
            }

            # cache the factory for later re-use
            $Factories{$driver_key} = $factory;
        }
        return $Factories{$driver_key};
    }
    sub _clear_group_factory_cache {
        %Factories = ();
    }
}

1;

=head1 NAME

Socialtext::LDAP::Operations - LDAP operations

=head1 SYNOPSIS

  use Socialtext::LDAP::Operations;

  # refresh all known/existing LDAP Users
  Socialtext::LDAP::Operations->RefreshUsers();

  # refresh all known/existing LDAP Groups
  Socialtext::LDAP::Operations->RefreshGroups();

=head1 DESCRIPTION

C<Socialtext::LDAP::Operations> implements a series of higher-level operations
that can be performed.

=head1 METHODS

=over

=item B<Socialtext::LDAP::Operations-E<gt>RefreshUsers(%opts)>

Refreshes known/existing LDAP Users from the configured LDAP servers.

Supports the following options:

=over

=item force => 1

Forces a refresh of the LDAP User data regardless of whether our local cached
copy is stale or not.  By default, only stale Users are refreshed.

=item email => $email

Refreshes a single User, selecting by e-mail address.

=item username => $username

Refreshes a single User, selecting by username.

=back

=item B<Socialtext::LDAP::Operations-E<gt>LoadUsers(%opts)>

Loads User records from LDAP into Socialtext from all configured LDAP
directories.

Load is performed by searching for all records in your LDAP directory that
have a valid e-mail address, and then loading each of those records into
Socialtext.

The search is performed using a "paged query", to try to accommodate large
directories where we may have more Users to load than the directory wants to
give us in a single search result set.

If, however, you have more Users in your directory than the B<hard limit> in
your directory, you're out of luck; without increasing the hard limit in the
directory there I<isn't> going to be a way we can invoke a single search to
get Users that'll let us march through the result set (paged or otherwise).
Only solution here is to increase the hard limit, or use the C<base_dn/filter>
configuration options to restrict our view on the LDAP directory to a smaller
sub-set of Users.

B<NOTE:> you B<must> have a C<filter> specified in your LDAP configurations
before you can load Users into Socialtext.  This is required so that it forces
you to stop and think about how you filter for "only User records" in B<your>
LDAP directories.  Without a filter, I<any> record found in LDAP that has an
e-mail address would be loaded into Socialtext, including Groups, Mailing
Lists, and any other device/item that may have an e-mail address (which most
assuredly is B<not> what you want).

Supports the following options:

=over

=item dryrun => 1

Dry-run; Users are searched for in the configured LDAP directories, but are
B<not> actually added to Socialtext.

=item email => $email

Loads a single LDAP User, selecting by e-mail address.

=item username => $username

Loads a single LDAP User, selecting by username.

=back

=item B<Socialtext::LDAP::Operations-E<gt>RefreshGroups(%opts)>

Refreshes known/existing LDAP Groups from the configured LDAP servers.

Supports the following options:

=over

=item force => 1

Forces a refresh of the LDAP Group data regardless of whether our local cached
copy is stale or not.  By default, only stale Groups are refreshed.

=item id => $group_id

Refreshes a single LDAP Group, selecting by internal Group Id.

=back

=item B<Socialtext::LDAP::Operations-E<gt>ListGroups(%opts)>

List Groups and their attributes. By default, we'll look up B<all> groups for
B<all> drivers.

Supports the following options:

=over

=item driver => <driver_id>

Only lookup the groups for the given C<driver_id> (from the C<group_factory>
option in the C<socialtext.conf> file).

=back

=back

=head1 AUTHOR

Graham TerMarsch C<< <graham.termarsch@socialtext.com> >>

=head1 COPYRIGHT

Copyright 2009 Socialtext, Inc., All Rights Reserved.

=head1 SEE ALSO

L<st-ldap>.

=cut
