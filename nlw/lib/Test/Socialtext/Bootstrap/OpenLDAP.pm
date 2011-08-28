package Test::Socialtext::Bootstrap::OpenLDAP;
# @COPYRIGHT@

use strict;
use warnings;
use base qw(Exporter Socialtext::Bootstrap::OpenLDAP);
use Test::Builder;
use Test::Base;
use Net::LDAP::Entry;
use Socialtext::AppConfig;
use File::Temp qw(tempdir);
use Socialtext::SQL qw(sql_singlevalue);

our @EXPORT = qw(initialize_ldap set_user_factories 
                 user_is_unique_to_socialtext);

sub initialize_ldap {
    my $dc = shift;
    my $dir = shift || tempdir(TMPDIR=>1, CLEANUP=>1); 

    my $dn = "dc=${dc},dc=com";
    my $ldap = Test::Socialtext::Bootstrap::OpenLDAP->new(
        base_dn=>$dn,
        statedir => "$dir/run",
        datadir => "$dir/data",
        logfile => "$dir/ldap.log",
    );

    my $entry = Net::LDAP::Entry->new();
    $entry->changetype('add');
    $entry->dn($dn);
    $entry->add(
        objectClass => 'dcObject',
        objectClass => 'organization',
        dc => $dc,
        o => "$dc dot com",
    );
    my $rc = $ldap->_update(
        \&Socialtext::Bootstrap::OpenLDAP::_cb_add_entry, [$entry]);
    ok $rc, "added ldap store '$dc' with base object";

    return $ldap;
}

sub set_user_factories {
    my $new_factories = join(';', @_);

    Socialtext::AppConfig->set(user_factories => $new_factories);
    Socialtext::AppConfig->write();

    my $factories = Socialtext::AppConfig->user_factories();
    is $factories, $new_factories, "factories are $new_factories";

    return $factories;
}

sub user_is_unique_to_socialtext {
    my $username = shift;

    my $count = sql_singlevalue(qq{
        SELECT COUNT(*) 
          FROM all_users
         WHERE driver_username = ?
    }, $username);
    is $count, 1, "one copy of $username exists";
}

# Over-ridden method to find the starting port number for LDAP during
# autodetection.  This over-ridden version takes into consideration that we
# _could_ be running tests in parallel and as a result need to take our "test
# slot" into consideration.
sub _base_port_number {
    my $class  = shift;
    my $port   = $class->SUPER::_base_port_number();
    my $slot   = Socialtext::AppConfig->test_slot() || 0;
    my $offset = $slot * 100;
    return $port + $offset;
}

1;

=head1 NAME

Test::Socialtext::Bootstrap::OpenLDAP - Test::Builder helper for Socialtext::Bootstrap::OpenLDAP

=head1 SYNOPSIS

  # auto-detect OpenLDAP, skipping all tests if it can't be found.
  use Test::Socialtext::Bootstrap::OpenLDAP;
  use Test::Socialtext tests => ...

  # bootstrap OpenLDAP, add some data, and start testing
  ...

or, if you want to fail outright if OpenLDAP can't be found...

  # auto-detect OpenLDAP, failing the test and aborting if it
  # can't be found.
  use Test::Socialtext::Bootstrap::OpenLDAP qw(:fatal);
  use Test::Socialtext tests => ...

=head1 DESCRIPTION

C<Test::Socialtext::Bootstrap::OpenLDAP> implements a C<Test::Builder> helper
for C<Socialtext::Bootstrap::OpenLDAP>.  On load, we try to auto-detect the
installed copy of OpenLDAP and then skip/fail tests as appropriate.

By default, C<Test::Socialtext::Bootstrap::OpenLDAP> does a "skip_all" if
we're unable to find OpenLDAP.  By using the C<:fatal> tag on import, though,
you can turn this into an assertion which causes the tests to fail outright.

B<NOTE:> this does mean, though, that you have to C<use> this bootstrap
I<before> you set up your test plan!

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Socialtext::Bootstrap::OpenLDAP>.

=cut
