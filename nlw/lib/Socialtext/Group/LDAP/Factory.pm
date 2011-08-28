package Socialtext::Group::LDAP::Factory;
# @COPYRIGHT@

use Moose;
use Socialtext::LDAP;
use Socialtext::LDAP::Config;
use Socialtext::Log qw(st_log);
use DateTime::Duration;
use Socialtext::SQL qw(sql_txn);
use Net::LDAP::Util qw(escape_filter_value);
use Socialtext::IntSet;
use namespace::clean -except => 'meta';

with qw(Socialtext::Group::Factory);

sub BUILD {
    my $self = shift;

    # If we can't find our LDAP Config, throw a fatal error
    my $config = $self->ldap_config();
    unless (defined $config) {
        my $driver_id = $self->driver_id();
        die "Can't find configuration '$driver_id' for LDAP Group Factory\n";
    }
}

has 'ldap_config' => (
    is => 'ro', isa => 'Maybe[Socialtext::LDAP::Config]',
    lazy_build => 1,
);

sub _build_ldap_config {
    my $self = shift;
    my $driver_id = $self->driver_id();
    return Socialtext::LDAP->ConfigForId($driver_id);
}

has 'ldap' => (
    is => 'ro', isa => 'Socialtext::LDAP::Base',
    lazy_build => 1,
);

sub _build_ldap {
    my $self = shift;
    return Socialtext::LDAP->new( $self->ldap_config );
}

# the LDAP store is *NOT* updateable; its read-only
sub can_update_store { 0 }

# the LDAP store *is* cacheable
sub is_cacheable { 1 }

# Returns list of available Groups
sub Available {
    my $self = shift;
    my %p    = @_;
    my $all  = $p{all} || 0;

    # Get our LDAP Group Attribute Map.  If we don't have one, we *can't* look
    # up Groups, so just return right away.
    my $attr_map = $self->ldap_config->group_attr_map();
    return unless (%{$attr_map});

    # Build up the LDAP search options
    my @ldap_group_attrs =
        map  { $attr_map->{$_} }
        grep { $_ ne 'member_maps_to' }     # internal use, not an actual attr
        keys %{$attr_map};

    my %options = (
        base    => $self->ldap_config->base(),
        scope   => 'sub',
        attrs   => [ @ldap_group_attrs ],
        filter  => Socialtext::LDAP->BuildFilter(
            global => $self->ldap_config->group_filter(),
        ),
    );

    # Look up the list of Groups in LDAP
    my $ldap = $self->ldap;
    return unless $ldap;

    my $mesg = $ldap->search( %options );
    unless ($mesg) {
        st_log->error( "ST::Group::LDAP::Factory: no suitable LDAP response" );
        return;
    }
    if ($mesg->code) {
        st_log->error( "ST::Group::LDAP::Factory: LDAP error while listing available Groups; " . $mesg->error() );
        return;
    }

    # Extract the Groups from the LDAP response
    my @available;
    while (my $entry = $mesg->shift_entry()) {
        my $proto        = $self->_map_ldap_entry_to_proto($entry);
        my $exists_in_db = $self->_get_cached_group($proto);
        my @members      = $entry->get_value($attr_map->{member_dn});

        next unless (defined $exists_in_db || $all);

        my $group = {
            driver_key          => $self->driver_key(),
            driver_group_name   => $proto->{driver_group_name},
            driver_unique_id    => $proto->{driver_unique_id},
            already_created     => defined $exists_in_db ? 1 : 0,
            member_count        => scalar @members,
        };
        $group->{driver_unique_id} =~ s/\\23/#/g;

        push @available, $group;
    }

    # Results have a pre-determined sort order
    my @sorted =
        sort { $a->{driver_group_name} cmp $b->{driver_group_name} }
        @available;
    return @sorted;
}

# empty stub; store is read-only, can't create a new Group in LDAP
sub Create {
    # XXX: should we throw a warning here?
}

# empty stub; store is read-only; can't update a Group in LDAP
sub Update {
    # XXX: should we throw a warning here?
}

# cache lifetime is based off of TTL for the LDAP server that we got the Group
# from.
sub _build_cache_lifetime {
    my $self = shift;
    return DateTime::Duration->new( seconds => $self->ldap_config->ttl );
}

# look up the Group in LDAP
sub _lookup_group {
    my ($self, $proto_group, %opts) = @_;
    $opts{escaped} ||= 0;

    # Get our LDAP Group Attribute Map.  If we don't have one, we *can't* look
    # up Groups, so just return right away.
    my $attr_map = $self->ldap_config->group_attr_map();
    return unless (%{$attr_map});

    # Map the fields in the provided proto-group to their underlying LDAP
    # attributes, and make sure that the values are properly escaped.  If we
    # don't have anything sensible to lookup, return right away; we're not
    # going to find it if we don't know what we're looking for.
    my $ldap_search_attrs = $self->_map_proto_to_ldap_attrs($proto_group,
        escaped => $opts{escaped});
    return unless (%{$ldap_search_attrs});

    # build up the LDAP search options
    my @ldap_group_attrs =
        map  { $attr_map->{$_} }
        grep { $_ ne 'member_maps_to' }     # internal use, not an actual attr
        keys %{$attr_map};
    my %options = (
        attrs => [ @ldap_group_attrs ],
    );

    my ($dn) =
        grep { $_ =~ m{^(dn|distinguishedName)$}i }
        keys %{$ldap_search_attrs};
    if ($dn) {
        # LDAP lookup contains the DN in the search; do an exact search
        $options{'base'}   = $ldap_search_attrs->{$dn};
        $options{'scope'}  = 'base';
        $options{'filter'} = Socialtext::LDAP->BuildFilter(
            global => $self->ldap_config->group_filter(),
        );
    }
    else {
        # LDAP lookup has no DN; do a sub-tree search
        $options{'base'}   = $self->ldap_config->base();
        $options{'scope'}  = 'sub';
        $options{'filter'} = Socialtext::LDAP->BuildFilter(
            global => $self->ldap_config->group_filter(),
            search => $ldap_search_attrs,
        );
    }

    # Go look up the Group in LDAP
    my $ldap = $self->ldap;
    return unless $ldap;

    my $text = join ", ",
        map { "$_ => $options{$_}" } keys %options;
    $text = "options($text)";

    my $mesg = $ldap->search( %options );
    unless ($mesg) {
        st_log->error( "ST::Group::LDAP::Factory: no suitable LDAP response; $text" );
        return;
    }
    if ($mesg->code) {
        st_log->error( "ST::Group::LDAP::Factory: LDAP error while finding Group; $text, " . $mesg->error() );
        return;
    }
    if ($mesg->count() > 1) {
        st_log->error( "ST::Group::LDAP::Factory: found multiple matches for Group; $text" );
        return;
    }

    # Extract the Group from the LDAP response
    my $entry = $mesg->shift_entry();
    unless ($entry) {
        st_log->debug( "ST::Group::LDAP::Factory: unable to find Group in LDAP; $text" );
        return;
    }

    # Map the LDAP response back to a proto group
    $entry->{asn}->{objectName} =~ s/\\#/#/;
    my $response = $self->_map_ldap_entry_to_proto($entry);
    $response->{driver_key} = $self->driver_key();
    $response->{members}    = [ $entry->get_value( $attr_map->{member_dn} ) ];
    foreach my $passthru (qw( primary_account_id )) {
        if (defined $proto_group->{$passthru}) {
            $response->{$passthru} ||= $proto_group->{$passthru};
        }
    }
    return $response;
}

# "trace update"; if set to false, perl can optimize out statements starting
# with "TU &&" in front.
use constant TU => $ENV{ST_DEBUG_LDAP};
our %UPDATING_GROUP;
sub _update_group_members {
    my $self    = shift;
    my $homey   = shift;
    my $members = shift;

    require Socialtext::Group;
    my $group   = Socialtext::Group->new(homunculus => $homey);

    # Watch out for recursion during Group updates.
    #
    # We've had an instance in the past where we accidentally triggered a
    # Group lookup to be done _while_ we were in the process of refreshing the
    # Group.  This triggered the Group to be refreshed _recursively_, which is
    # just bad.
    #
    # So, keep track of what Groups we're actively refreshing.  If we find
    # that we end up recursively trying to do a Group lookup, its an error.
    # Ideally we shouldn't hit/trigger this, but this code will help us verify
    # that while running regression tests.
    my $name = $group->driver_group_name;
    if ($UPDATING_GROUP{$name}) {
        my $msg = "ST recursed internally while doing LDAP Group refresh";

        # when encountered in tests, this is a *FATAL* condition
        if ($ENV{HARNESS_ACTIVE}) {
            require Test::More;
            Test::More::BAIL_OUT($msg);
        }
        # but _if_ we happen to encounter this out in the field, log an error
        # and then just don't recurse.
        st_log->critical($msg);
        return;
    }
    local $UPDATING_GROUP{$name} = 1;

    # Start with the current direct members. Algorithm below cross-checks this
    # list.
    my $member_set = Socialtext::IntSet->FromArray(
        $group->user_ids(direct => 1));
    TU && warn "*** INITIAL SET IS ".join(',',@{$member_set->array});

    # Keep track of DNs and IDs that we've seen, so we're not looking them up
    # repeatedly.  This prevents lots of superflous user lookups on nested
    # groups (and helps for recursively nested groups).
    my %seen_dn;
    my $seen_set = Socialtext::IntSet->new();

    # Take all of the "Member DNs" that we were given and try to add them.
    # The DN _may_ be a User, a Group, or not in any LDAP store we know of.
    # The DN might also be a referral, so don't use the DN as a key.
    my @left_to_add = @{$members};
    while (my $dn = shift @left_to_add) {
        TU && warn "CONSIDERING $dn";

        # early-out if we've already processed this *exact* DN (DNs in
        # sub-groups are not guaranteed to be the same case/punctuation and
        # can also be referrals).  Need to check ID for correctness; this is
        # an optimization for speed.
        next if ($seen_dn{$dn}++);

        my $user_id;
        eval {
            $user_id = Socialtext::User->ResolveId({driver_unique_id => $dn})
        };
        if ($@) {
            TU && warn "unable to resolve $dn to user_id: $@";
            st_log->warning("Unable to resolve DN to user_id: $@");
        }

        if ($user_id) {
            TU && warn "$dn IS ID $user_id";
            # set() returns the previous presence/absence in the IntSet
            next if ($seen_set->set($user_id) or $member_set->get($user_id));
        }
        else {
            TU && warn "$dn has no quick user_id";
        }

        # we couldn't find a user_id because either
        # * the user doesn't exist in our database yet, or
        # * the DN isn't a user; it's either a group or doesn't exist
        # OR
        # we did get a user_id, but the user isn't in the group.

        my $user;
        eval {
            sql_txn {
                $user = Socialtext::User->new(driver_unique_id => $dn);
                $user->primary_account($group->primary_account, no_hooks => 1)
                    if $user && !$user_id; # newly created user
            };
        };
        if (my $e = Exception::Class->caught(
                'Socialtext::Exception::DataValidation'))
        {
            st_log()->warning(
                "Unable to refresh LDAP Group member '$dn', skipping; $_")
                for $e->messages;
            next;
        }
        elsif ($@) {
            TU && warn "during user->new: $@";
            st_log()->error(
                "Unable to refresh LDAP Group member '$dn', skipping; $@");
            next;
        }

        if ($user) {
            $user_id = $user->user_id;
            TU && warn "$dn IS ID $user_id (no shortcut)";
            $seen_set->set($user_id);
            next if ($member_set->get($user_id));

            # If the User has been explicitly de-activated, DO NOT add them
            # back into an LDAP Group; they're supposed to be deactivated.
            next if ($user->is_deactivated);

            # it's a user, but they don't have a role.  Give them the default
            # role in the group.
            TU && warn "ADD $dn";
            $group->add_user(user => $user);
            $member_set->set($user_id);
            next;
        }
        else {
            TU && warn "no user record?!";
        }

        # OK, the DN isn't a user. Look this DN up as a Group, and add its
        # membership list to the list of things we have left to try and add.
        my $nested_proto = $self->_lookup_group(
            {driver_unique_id => $dn}, escaped => 1);
        if ($nested_proto) {
            TU && warn "GROUP $dn";
            push @left_to_add, @{$nested_proto->{members}};
            next;
        }

        st_log()->warning(
            "Unable to find User/Group in LDAP for DN '$dn'; skipping" );
    }

    # Remove Users that *used to* be in the Group, but that don't appear to be
    # any more.
    TU && warn "MEMBER SET IS ".join(',',@{$member_set->array});
    TU && warn "SEEN SET IS ".join(',',@{$seen_set->array});
    my $gone = $member_set->subtract($seen_set);
    TU && warn "DIFF SET IS ".join(',',@{$gone->array});
    my $gone_gen = $gone->generator;
    while (my $to_remove_id = $gone_gen->()) {
        TU && warn "REMOVE $to_remove_id";
        my $to_remove = Socialtext::User->new(user_id => $to_remove_id);
        $group->remove_user(user => $to_remove) if $to_remove;
    }
}

{
    my %proto_to_field = (
        # proto-group       => ST field (as noted in LDAP Group Attr Map)
        driver_unique_id    => 'group_id',
        driver_group_name   => 'group_name',
    );
    my %field_to_proto = reverse %proto_to_field;

    sub _map_proto_to_ldap_attrs {
        my ($self, $proto_group, %opts) = @_;
        $opts{escaped} ||= 0;

        my $attr_map = $self->ldap_config->group_attr_map();
        return unless (%{$attr_map});

        my %ldap_attrs;
        while (my ($proto_field, $proto_value) = each %{$proto_group}) {
            my $field = $proto_to_field{$proto_field};
            next unless $field;

            my $attr = $attr_map->{$field};
            next unless $attr;

            if ($proto_field eq 'driver_unique_id') {
                $proto_value =~ s/\\#/#/g;
                $proto_value =~ s/#/\\23/g;
                $ldap_attrs{$attr} = $proto_value;
            }
            else {
                $ldap_attrs{$attr} = $opts{escaped}
                    ?  $proto_value : escape_filter_value($proto_value);
            }
        }
        return \%ldap_attrs;
    }

    sub _map_ldap_entry_to_proto {
        my ($self, $entry) = @_;

        my $attr_map = $self->ldap_config->group_attr_map();
        return unless (%{$attr_map});

        my %proto_group;
        while (my ($field, $ldap_attr) = each %{$attr_map}) {
            my $proto_field = $field_to_proto{$field};
            next unless $proto_field;

            my $proto_value;
            if ($ldap_attr =~ m{^(dn|distinguishedName)$}i) {
                # DN isn't an attribute, its a Net::LDAP::Entry method
                $proto_value = $entry->dn();
            }
            else {
                $proto_value = $entry->get_value( $ldap_attr );
            }

            if ($proto_field eq 'driver_unique_id') {
                $proto_value =~ s/CN=\\#/CN=#/;
            }

            $proto_group{$proto_field} = $proto_value;
        }
        return \%proto_group;
    }
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

Socialtext::Group::LDAP::Factory - LDAP sourced Group Factory

=head1 SYNOPSIS

  use Socialtext::Group;

  $factory = Socialtext::Group->Factory(driver_key => 'LDAP:abc123');

=head1 DESCRIPTION

C<Socialtext::Group::LDAP::Factory> provides an implementation of a Group
Factory that is sourced externally via LDAP.

Consumes the C<Socialtext::Group::Factory> Role.

=head1 METHODS

=over

=item B<$factory-E<gt>ldap_config()>

Returns a C<Socialtext::LDAP::Config> object for the LDAP configuration in use
by this LDAP Group Factory.

=item B<$factory-E<gt>ldap()>

Returns a C<Socialtext::LDAP::*> object, holding the connection to the LDAP
server that this Factory presents Groups from.

=item B<$factory-E<gt>can_update_store()>

Returns false; LDAP Group Factories are B<read-only>.

=item B<$factory-E<gt>is_cacheable()>

Returns true; LDAP Group stores should be cached locally.

=back

=head1 NOTES

In an Active Directory, User records contain a C<memberOf> attribute, which
points I<back> to the Group object DN ("Hey, I'm a member of I<that> Group").
B<However>, the Group record contains a C<member> attribute which contains a
list of User DNs (one for each User) ("Hey, I<these> Users are member of this
Group").  Fortunately, these C<member> and C<memberOf> attributes are linked
and are updated automatically by Active Directory; updating "Group.member"
automatically updates the "User.memberOf" attribute.

As a result, B<we> only ever have to be concerned with enumerating the
"Group.member" attribute; that's going to contain the full list of DNs for
Users/Groups/etc. that are members of this Group.  We do I<not> have to also
go out and scour AD for Users that are a C<memberOf> the Group, as we already
got the full list of those from querying the Group object directly.

Reference: http://www.informit.com/articles/article.aspx?p=26136&seqNum=5

=head1 AUTHOR

Socialtext, Inc.,  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc.,  All Rights Reserved.

=cut
