#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings FATAL => 'all';
use Test::Socialtext tests => 5;

use_ok 'Socialtext::User::Base';

###############################################################################
# Password constraints/restrictions.
password_constraints: {
    my $str;

    # password is required
    eval { $str = Socialtext::User::Base->ValidatePassword() };
    like $@, qr/mandatory.*password/i, 'password constraint; mandatory';

    # must be at least 6 chars in length
    $str = Socialtext::User::Base->ValidatePassword(password=>'12345');
    like $str, qr/must be at least/, 'password constraint; 5 chars too short';

    $str = Socialtext::User::Base->ValidatePassword(password=>'123456');
    ok !$str, 'password constraint; 6 chars ok';

    $str = Socialtext::User::Base->ValidatePassword(password=>'1234567');
    ok !$str, 'password constraint; 7 chars ok';
}
