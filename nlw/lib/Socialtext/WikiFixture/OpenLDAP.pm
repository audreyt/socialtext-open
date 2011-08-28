package Socialtext::WikiFixture::OpenLDAP;
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::Bootstrap::OpenLDAP;
use Socialtext::AppConfig;
use Socialtext::LDAP::Config;
use Test::More;
use File::Temp;
use base qw(Socialtext::WikiFixture::Socialtext);

sub init {
    my $self = shift;

    # bootstrap an OpenLDAP instance
    $self->{ldap} = Socialtext::Bootstrap::OpenLDAP->new();

    # init our base class
    $self->SUPER::init(@_);
}

sub end_hook {
    my $self = shift;

    # tear down OpenLDAP instance, which cleans up after itself
    $self->{ldap} = undef;

    # tear down our base class
    $self->SUPER::end_hook(@_);
}

sub add_ldif_data {
    my $self = shift;
    my $ldif = shift;
    diag "add ldif data: $ldif";
    $self->{ldap}->add_ldif($ldif);
}

sub remove_ldif_data {
    my $self = shift;
    my $ldif = shift;
    diag "remove ldif data: $ldif";
    $self->{ldap}->remove_ldif($ldif);
}

sub add_ldap_user {
    my $self = shift;
    my $username = shift;

    add_ldif_data($self, _ldif_fh_for($username)->filename);
}

sub remove_ldap_user {
    my $self = shift;
    my $username = shift;

    remove_ldif_data($self, _ldif_fh_for($username)->filename);
}


# XXX: file::Temp usage is uuuugly; need to refactor
sub _ldif_fh_for {
    my $username = shift;

    my $temp_fh = new File::Temp(UNLINK => 1, SUFFIX => '.ldif');

    print $temp_fh join("\n",
        "dn: cn=$username LdapUser,dc=example,dc=com",
        "objectClass: inetOrgPerson",
        "cn: $username LdapUser",
        "gn: $username",
        "sn: LdapUser",
        "mail: $username\@example.com",
        "userPassword: ldapd3v",
        "ou: people"
    );

    close $temp_fh;      # ensure file's flushed to disk
    return $temp_fh;
}


sub ldap_config {
    my $self = shift;
    my $param = shift;
    my $value = shift;
    diag "configure ldap: $param => $value";

    my $ldap_cfg = $self->{ldap}->ldap_config();
    $ldap_cfg->{$param} = $value;
    Socialtext::LDAP::Config->save($ldap_cfg);
}

1;

=head1 NAME

Socialtext::WikiFixture::OpenLDAP - OpenLDAP extensions to the WikiFixture test framework

=head1 DESCRIPTION

This module extends C<Socialtext::WikiFixture::Socialtext> and includes some
extra commands relevant for testing against an LDAP directory (in this case, OpenLDAP).

On initialization, this module automatically bootstraps an OpenLDAP server,
saves out the F<ldap.yaml> LDAP configuration file, and updates the "user
factories" configuration in the Socialtext application config so that the LDAP
directory is the B<first> known user factory.  On cleanup, the user factories
are reset back to their initial state.

=head1 METHODS

=over

=item B<init()>

Over-ridden initialization routine, which bootstraps an OpenLDAP instance.

=item B<end_hook()>

Over-ridden cleanup routine, tears down the OpenLDAP instance.

=item B<add_ldif_data($ldif)>

Adds data in the given C<$ldif> file to the LDAP directory.

=item B<remove_ldif_data($ldif)>

Removes data in the given C<$ldif> file from the LDAP directory.

=item B<add_ldap_user($username)>

Given a unique C<$username>, creates a minimal LDAP record describing
that user and adds it to the LDAP directory.

=item B<remove_ldap_user($username)>

Removes a record previously added with C<add_ldap_user> and belonging
to C<$username> from the LDAP directory.

=item B<ldap_config($param, $value)>

Tweaks the configuration of the bootstrapped OpenLDAP server, changing
C<$param> to C<$value>.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
