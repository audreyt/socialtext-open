#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use YAML qw();
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext tests => 37;

use_ok( 'Socialtext::LDAP::Config' );

###############################################################################
### TEST DATA
###############################################################################
our $yaml =<<EOY;
id: 1deadbeef1
name: Authenticated LDAP
backend: OpenLDAP
base: ou=Development,dc=my-domain,dc=com
host: 127.0.0.1
port: 389
bind_user: cn=Manager,ou=Development,dc=my-domain,dc=com
bind_password: abc123
filter: '(objectClass=inetOrgPerson)'
ttl: 300
not_found_ttl: 150
attr_map:
    user_id: dn
    username: cn
    email_address: mail
    first_name: gn
    last_name: sn
group_filter: (objectClass=groupOfNames)
group_attr_map:
    group_id: dn
    group_name: cn
    member_dn: member
EOY

###############################################################################
# Check for required fields on instantiation; host, attr_map
check_required_fields: {
    foreach my $required (qw( host attr_map )) {
        clear_log();

        my $data = YAML::Load($yaml);
        delete $data->{$required};

        my $config = Socialtext::LDAP::Config->new(%{$data});
        ok !defined $config, "instantiation, missing '$required' parameter";

        is logged_count(), 1, '... logged right number of entries';
        next_log_like 'error', qr/missing '$required'/, "... ... missing $required";
    }
}

###############################################################################
# Check for required mapped attributes; user_id, username, email_address,
# first_name, last_name
check_required_mapped_attributes: {
    foreach my $attr (qw( user_id username email_address first_name last_name )) {
        clear_log();

        my $data = YAML::Load($yaml);
        delete $data->{attr_map}{$attr};

        my $config = Socialtext::LDAP::Config->new(%{$data});
        ok !defined $config, "instantiation, missing '$attr' mapped attribute";

        is logged_count(), 1, '... logged right number of entries';
        next_log_like 'error', qr/missing mapped User attribute '$attr'/, "... ... missing $attr";
    }
}

###############################################################################
# Check that "group_attr_map" is optional; upgrades ain't gonna have one.
check_group_attribute_map_is_optional: {
    my $data = YAML::Load($yaml);
    delete $data->{group_attr_map};

    my $config = Socialtext::LDAP::Config->new(%{$data});
    isa_ok $config, 'Socialtext::LDAP::Config', 'valid instantiation';
}

###############################################################################
# Check for required mapped Group attributes; group_id, group_name, member_dn
check_required_mapped_group_attributes: {
    foreach my $attr (qw( group_id group_name member_dn )) {
        clear_log();

        my $data = YAML::Load($yaml);
        delete $data->{group_attr_map}{$attr};

        my $config = Socialtext::LDAP::Config->new(%{$data});
        ok !defined $config, "instantiation, missing '$attr' mapped Group attribute";

        is logged_count(), 1, '... logged an error';
        next_log_like 'error', qr/missing mapped Group attribute '$attr'/, "... ... missing $attr";
    }
}

###############################################################################
# Instantiation with full config; should be ok.
instantiation: {
    my $data = YAML::Load($yaml);
    my $config = Socialtext::LDAP::Config->new(%{$data});
    isa_ok $config, 'Socialtext::LDAP::Config', 'valid instantiation';
}

###############################################################################
# Mistyping 'bind_user' as 'bind_username' should be OK.
username_typo: {
    my $yaml2 = $yaml;
    $yaml2 =~ s/^bind_user:/bind_username:/m; # introduce a common typo
    my $data = YAML::Load($yaml2);
    my $config = Socialtext::LDAP::Config->new(%{$data});
    isa_ok $config, 'Socialtext::LDAP::Config', 'valid instantiation';
    ok $config->bind_user, 'typo was fixed';
}

###############################################################################
# If "not_found_ttl" is missing, should default to "ttl"
not_found_ttl_default: {
    my $data = YAML::Load($yaml);

    my $with = Socialtext::LDAP::Config->new(%{$data});
    is $with->not_found_ttl, 150, 'not_found_ttl has explicit value';

    delete $data->{not_found_ttl};
    my $without = Socialtext::LDAP::Config->new(%{$data});
    is $without->not_found_ttl, $without->ttl, 'not_found_tto defaults to ttl';
}
