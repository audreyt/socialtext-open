#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 3;

###############################################################################
# Make sure that Net::LDAP gets loaded up by ST::LDAP::Base.
#
# This was a regression in the "ldap-improvements" branch that had slipped
# into the trunk due to insufficient testing.  It also didn't show up in the
# other unit tests as our LDAP test harness loads it up for us, as do the
# back-end specific modules.
make_sure_that_net_ldap_gets_loaded: {
    ok !$INC{'Net/LDAP.pm'}, 'Net::LDAP is not loaded (yet)';
    use_ok 'Socialtext::LDAP::Base';
    ok $INC{'Net/LDAP.pm'}, 'Net::LDAP is now loaded';
}

