#!/usr/bin/env perl
use strict;
# @COPYRIGHT@

# the catching side of poster.pl
# put this somewhere in its own directory where you can run 
# cgis. You can then post to it with form fields of data and
# name. The data will be written out as /tmp/{name}.  It's only
# been tested with text files.
#
# Do not run this all the time.

my $OUTPUT_DIR = "/tmp/catch.cgi";

use CGI;
use CGI::Carp 'fatalsToBrowser';
use IO::File;

my $q = new CGI;
print $q->header;

my $data = $q->param('data');
my $name = $q->param('name');


if (defined $name) {
    write_file($name, $data);
}
else {
    print "problem\n";
}

sub write_file {
    my ($name, $data) = @_;
    mkdir $OUTPUT_DIR or die "Cannot mkdir $OUTPUT_DIR: $!";
    my $io = new IO::File;
    $name =~ tr[/][_];
    $name = "$OUTPUT_DIR/$name";
    $io->open("> $name") || die "unable to open $name: $!";
    print $io $data;
    $io->close;
    print "Got $name.\n";
}
