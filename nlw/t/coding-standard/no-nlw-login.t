#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use List::MoreUtils qw(any);
use Test::More tests => 1;
use Test::Differences;

# List of things that are OK to include "/nlw/login.html" in them.
my @skip_paths = qw(
    ./share/migrations/
    ./share/workspaces/stl10n/
);
my %skip_files =
    map { $_ => 1 }
    qw(
        ./dev-bin/st-create-account-data
        ./lib/Socialtext/Challenger/STLogin.pm
        ./lib/Socialtext/WikiFixture/SocialBase.pm
        ./share/skin/js-test/s3/t/bz-1379.t.js
        ./share/skin/js-test/s3/t/bz-1500.t.js
        ./share/workspaces/wikitests/test_case_login_logout
        ./share/workspaces/wikitests/test_case_appliance_health_report
        ./build/templates/apache-perl/nlw.tt2
    );

SKIP: {
    skip 'No `grep` available', 1, unless `which grep` =~ /\w/;

    my @args = qw(
        --recursive
        --files-with-matches
        --devices=skip
        --exclude-dir=.git
        --exclude-dir=blib
        --exclude-dir=tmp
        --exclude-dir=t
    );
    my @candidates = `grep @args /nlw/login.html .`;
    chomp @candidates;

    my @bad_files;
    foreach my $file (@candidates) {
        next if (exists $skip_files{$file});
        next if (any { $file =~ /^$_/ } @skip_paths);
        push @bad_files, $file;
    }

    eq_or_diff \@bad_files, [], 'No /nlw/login.html in our source code';

    if (@bad_files) {
        diag <<EOT;
We shouldn't be referencing the login template directly.  Instead,
we should either be:

a) triggering the Authen challenger at /challenge?<url>

b) using the 'authen/error.html' error template to display an error
   - see "ST::Handler::Authen->_show_error()" for an example

   you could also set the error message into the session and then redirect
   to "/nlw/error.html" to have the message displayed.
EOT
    }
}
