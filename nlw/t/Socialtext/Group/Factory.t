#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 8;

###############################################################################
# Implement some Group Factories that we can test with/against
{
    package ReadWriteGroupFactory;
    use Moose;
    with 'Socialtext::Group::Factory';

    sub can_update_store { 1 };
    sub is_cacheable { 0 };
    sub Available { +[] };
    sub Create {
        my ($self, $proto_group) = @_;
    }
    sub Update { }
    sub _build_cache_lifetime {
        return DateTime::Duration->new(years => 10);
    }
    sub _lookup_group { }
    sub _update_group_members { }
}

{
    package ReadOnlyGroupFactory;
    use Moose;
    with 'Socialtext::Group::Factory';

    sub can_update_store { 0 };
    sub is_cacheable { 0 };
    sub Available { +[] };
    sub Create {
        my ($self, $proto_group) = @_;
    }
    sub Update { }
    sub _build_cache_lifetime {
        return DateTime::Duration->new(years => 10);
    }
    sub _lookup_group { }
    sub _update_group_members { }
}

###############################################################################
# TEST: instantiation
instantiation: {
    my $factory = ReadWriteGroupFactory->new(driver_key => 'ReadWrite:123');
    isa_ok $factory, 'ReadWriteGroupFactory', 'Test Group Factory';

    is $factory->driver_key,  'ReadWrite:123', '... with driver_key';
    is $factory->driver_name, 'ReadWrite',     '... ... containing driver_name';
    is $factory->driver_id,   '123',           '... ... containing driver_id';
}

###############################################################################
# TEST: read-write group is updateable
read_write_group_is_updateable: {
    my $factory = ReadWriteGroupFactory->new(driver_key => 'ReadWrite:123');
    isa_ok $factory, 'ReadWriteGroupFactory', 'ReadWrite Test Group Factory';
    ok $factory->can_update_store(), '... is updateable';
}

###############################################################################
# TEST: read-only group is NOT updateable
read_only_group_is_not_updateable: {
    my $factory = ReadOnlyGroupFactory->new(driver_key => 'ReadOnly:123');
    isa_ok $factory, 'ReadOnlyGroupFactory', 'ReadOnly Test Group Factory';
    ok !$factory->can_update_store(), '... is NOT updateable';
}
