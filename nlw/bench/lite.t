#!/usr/bin/env perl
use warnings;
use strict;
use lib "$ENV{PWD}/lib";

# USAGE: bench/lite.t page_id count children [show output]
#
# Excepts a fresh-dev-env to have been created in .nlw, for use
# as the data source.

use Devel::Profiler;

use Socialtext;
use Socialtext::Lite;
use Socialtext::Page;
use Socialtext::Template;

Socialtext::Template->preload_all;

my $Dir = $ENV{HOME} . '/.nlw/root/workspace/admin';
chdir $Dir;
my $nlw = Socialtext->new();
$nlw->load_hub('config*.yaml');
$nlw->hub()->registry()->load();
$nlw->debug();
my $hub = $nlw->hub;

my $page_id = shift || 'help';
my $pages = shift || 10;
my $concurrency = shift || 1;
$concurrency or die "bad args";


for my $child (1 .. $concurrency) {
    my $child_pid = fork;
    if (! defined $child_pid) {
        die "fork: $!";
    } elsif (0 == $child_pid) {
        diag("fork $child");
        Devel::Profiler->import( output_file => "$ENV{PWD}/tmon.$$.out" );
        Devel::Profiler::init();
        for my $count (1 .. $pages) {
            my $html;
            my $lite = Socialtext::Lite->new(hub => $hub);
            my $id = $nlw->uri_unescape($page_id);
            my $page = Socialtext::Page->new(
                hub => $hub,
                id  => Socialtext::Page->name_to_id($id),
            );
            $html = $lite->display($page);
            diag($html)if @ARGV;
            diag("done $child/$count");
        }
        exit;
    }
}

for my $child (1 .. $concurrency) {
    wait;
    diag("reap $child");
}

sub diag { print STDERR @_, "\n" }

