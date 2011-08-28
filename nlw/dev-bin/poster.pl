#!/usr/bin/env perl
# @COPYRIGHT@

# use this script on an appliance to overcome firewall barriers 
# that prevent sending a file elsewhere. You must first set
# http_proxy in the environment (ask the customer for the proxy)
# and then run as
#
#   ./poster.pl <filename> <url where catch.cgi is>
#
# see catch.cgi for more info on the other end.

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use LWP::UserAgent;
use Socialtext::File;

my $file = $ARGV[0] || die "you must give me a file";
my $url = $ARGV[1]  || die "you must give me a catch.cgi url";

my $ua  = LWP::UserAgent->new;
$ua->env_proxy;

my $response = $ua->post(
    $url,
    {
        name => $file,
        data => Socialtext::File::get_contents($file),
    }
);

unless ( $response->is_success ) {
    die "error: ", $response->status_line, "\n";
}


