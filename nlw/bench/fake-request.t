#!/usr/bin/env perl
use warnings;
use strict;

# USAGE: bench/fake-request.t reqs_per_child num_children
# Add a third argument if you want to see the output.
#
# num_children taken to be 1 if not given
use lib "$ENV{PWD}/lib";

my %ET;
my $T0;
my $Tic;

BEGIN {
    $ENV{NLW_HANDLER_NO_PRELOADS} = 1;
}

BEGIN {
    use Apache ();
    sub Apache::perl_hook { 1 }
    sub Apache::server { }

    sub tic($) {
        my $toc = time;
        $ET{$_[0]} = $toc - $Tic;
        $Tic = $toc;
    }

    use Time::HiRes 'time';
    $T0 = $Tic = time;

    use Devel::Profiler;
    tic('Devel::Profiler');

    use Socialtext::Handler;
    tic('Socialtext::Handler');

    use Socialtext::Handler::App;
    tic('Socialtext::Handler::App');

    $ENV{GATEWAY_INTERFACE} = 1;
    $ENV{HTTP_USER_AGENT} = 'fake-request.t';
    #$ENV{QUERY_STRING} = 'wiki_101';
    require Socialtext;
    tic('NLW');

    require Socialtext::CGI;
    tic('Socialtext::CGI');

    require Socialtext::Template;
    tic('Socialtext::Template');
}

{
    no warnings 'redefine';

    *Socialtext::CGI::page_name = sub { 'help' };

    *Apache::Cookie::fetch = sub { };
}

Socialtext::Template->preload_all;
tic('preload_all');

my $pages = shift || 10;
my $concurrency = shift || 1;

for my $child (1 .. $concurrency) {
    my $child_pid = fork;
    if (! defined $child_pid) {
        die "fork: $!";
    } elsif (0 == $child_pid) {
        diag("fork $child");
        Devel::Profiler->import( output_file => "tmon.$$.out" );
        Devel::Profiler::init();
        for my $count (1 .. $pages) {
            my $nlw = Bogus::Handler->get_nlw(Bogus::Apache->new);
            if (not defined $nlw) {
                die 'Could not get NLW object';
            }
            my $html = $nlw->process;
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

foreach my $thing (sort { $ET{$a} <=> $ET{$b} } keys %ET) {
    printf "%10.3f (ET) %s\n", $ET{$thing}, $thing;
}

sub diag { print STDERR @_, "\n" }

package Bogus::Apache;

use Apache;
sub new {
    my $class = shift;
    bless {@_}, $class;
}

sub uri { "/public/index.cgi?wiki_101" }

sub pnotes {
    $_[0]->{pnotes}{$_[1]} = $_[0]->{pnotes}{$_[2]} if @_ > 2;
    return $_[0]->{pnotes}{$_[1]};
}

package Bogus::Handler;
use base 'Socialtext::Handler';
sub workspace_uri_regex { qr{/([^/]+)} }
