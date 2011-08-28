#!/usr/bin/env perl
use warnings;
use strict;

# USAGE: perl -d:DProf bench/fake-request-dprof.t requests
#
# num_children taken to be 1 if not given
use lib "$ENV{PWD}/lib";

my %ET;
my $T0;
my $Tic;

BEGIN { $ENV{NLW_HANDLER_NO_PRELOADS} = 1; }
BEGIN {
    use Apache ();
    sub Apache::perl_hook { 1 }
    sub Apache::server { }

    use Socialtext::Handler;
    use Socialtext::Handler::App;

    $ENV{GATEWAY_INTERFACE} = 1;
    $ENV{HTTP_USER_AGENT} = 'fake-request.t';
    #$ENV{QUERY_STRING} = 'wiki_101';
    require Socialtext;

    require Socialtext::CGI;

    require Socialtext::Template;
}

{
    no warnings 'redefine';

    *Socialtext::CGI::page_name = sub { 'help' };

    *Socialtext::upgrade_check = sub { return };

    *Socialtext::Apache::User::user_id = sub { 'user1' };

    *Public::Users::assert_anonymous_user = sub {
        my $self = shift;
        $self->current($self->new_user('user1'));
        return 1;
    };
}
Socialtext::Template->preload_all;

my $pages = shift || 10;

for my $count (1 .. $pages) {
    my $nlw = Bogus::Handler->get_nlw(Bogus::Apache->new);
    if (not defined $nlw) {
        die 'Could not get NLW object';
    }
    my $html = $nlw->process;
    warn $html if $ARGV[0];
}

package Bogus::Apache;

use Apache;
sub new {
    my $class = shift;
    bless {@_}, $class;
}

sub uri { "/public/index.cgi?help" }

sub dir_config {
    return "$ENV{HOME}/.nlw/root" if ($_[1] eq 'nlw_root');
}

sub pnotes {
    $_[0]->{pnotes}{$_[1]} = $_[0]->{pnotes}{$_[2]} if @_ > 2;
    return $_[0]->{pnotes}{$_[1]};
}

package Bogus::Handler;
use base 'Socialtext::Handler';
sub workspace_uri_regex { qr{/([^/]+)} }
