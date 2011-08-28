#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 8;

###############################################################################
# Fixtures: db
# - need DB around, but don't care what's in it.
fixtures(qw( db ));

###############################################################################
# Implement a Group Factory that we can test with/against
{
    package TestGroupFactory;
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

###############################################################################
### TEST DATA
my %TEST_DATA = (
    driver_key         => 'Dummy:123',
    driver_group_name  => 'Test Group Name',
    driver_unique_id   => 456,
    primary_account_id => Socialtext::Account->Socialtext->account_id(),
    creation_datetime  => DateTime->now(),
    created_by_user_id => Socialtext::User->SystemUser->user_id(),
);

###############################################################################
# TEST: new Groups are assigned a "group_id"
auto_assign_group_id: {
    my %proto_group = %TEST_DATA;
    delete $proto_group{group_id};

    my $factory = TestGroupFactory->new(driver_key => 'DummyKey');
    $factory->ValidateAndCleanData(undef, \%proto_group);
    ok $proto_group{group_id}, 'auto-assigned Group Id';
}

###############################################################################
# TEST: new Groups are assigned a "creation_datetime"
auto_assign_creation_datetime: {
    my %proto_group = %TEST_DATA;
    delete $proto_group{creation_datetime};

    my $factory = TestGroupFactory->new(driver_key => 'DummyKey');
    $factory->ValidateAndCleanData(undef, \%proto_group);
    ok $proto_group{creation_datetime}, 'auto-assigned Creation Date/Time';
}

###############################################################################
# TEST: new Groups are assigned a "created_by_user_id"
auto_assign_created_by_user_id: {
    my %proto_group = %TEST_DATA;
    delete $proto_group{created_by_user_id};

    my $factory = TestGroupFactory->new(driver_key => 'DummyKey');
    $factory->ValidateAndCleanData(undef, \%proto_group);
    ok $proto_group{created_by_user_id}, 'auto-assigned Creating User';
}

###############################################################################
# TEST: new Groups are assigned a "primary_account_id"
auto_assign_primary_account_id: {
    my %proto_group = %TEST_DATA;
    delete $proto_group{primary_account_id};

    my $factory = TestGroupFactory->new(driver_key => 'DummyKey');
    $factory->ValidateAndCleanData(undef, \%proto_group);
    ok $proto_group{primary_account_id}, 'auto-assigned Primary Account';
}

###############################################################################
# TEST: attributes having leading/trailing whitespace trimmed
trim_whitespace: {
    my %proto_group = %TEST_DATA;
    $proto_group{driver_group_name} = '     Test Group Name     ';

    my $factory = TestGroupFactory->new(driver_key => 'DummyKey');
    $factory->ValidateAndCleanData(undef, \%proto_group);
    is $proto_group{driver_group_name}, 'Test Group Name',
        'fields trimmed for leading/trailing whitespace';
}

###############################################################################
# TEST: presence of required attributes
required_attributes: {
    my @required_attrs =
        grep { $_ ne 'group_id' }               # validation assigns default
        grep { $_ ne 'created_by_user_id' }     # validation assigns default
        grep { $_ ne 'creation_datetime' }      # validation assigns default
        grep { $_ ne 'primary_account_id' }     # validation assigns default
        map { $_->name }
        grep { $_->is_required && !$_->is_lazy_build }
        Socialtext::Group::Homunculus->meta->get_all_attributes;

    foreach my $attr (@required_attrs) {
        my %proto_group = %TEST_DATA;
        delete $proto_group{$attr};

        my $factory = TestGroupFactory->new(driver_key => 'DummyKey');
        eval {
            $factory->ValidateAndCleanData(undef, \%proto_group);
        };

        my $match_attr = $attr;
        $match_attr =~ s/_/./g;
        like $@, qr/$match_attr.*is a required field/i, "required field: $attr";
    }
}
