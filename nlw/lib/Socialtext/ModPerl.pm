# @COPYRIGHT@
package Socialtext::ModPerl;
use strict;
use warnings;
use Carp ();
use File::Path ();
use Socialtext::Workspace;
use Socialtext::File;

# This can't really do its thing except under mod_perl
init() if $ENV{MOD_PERL};

sub init {
    $SIG{USR2} ||= sub { Carp::cluck('Caught SIGUSR2') };

    _create_and_chown_logo_root_dir();
}

sub _create_and_chown_logo_root_dir {
    my $dir = Socialtext::Workspace->LogoRoot;

    File::Path::mkpath( $dir, 0, 0775 ) unless -d $dir;

    my $uid = Apache->server->uid;
    my $gid = Apache->server->gid;
    chown $uid, $gid, $dir, Socialtext::File::files_and_dirs_under($dir)
        or die "Cannot chown all files/dirs in $dir to $uid:$gid: $!";
}


1;

__END__

=head1 NAME

Socialtext::ModPerl - Load this from the Apache config to do one-time setup under mod_perl

=head1 SYNOPSIS

  PerlModule  Socialtext::ModPerl

=head1 DESCRIPTION

Loading this module does the following:

* set up a USR2 signal handler that calls C<Carp::cluck()> per
http://perl.apache.org/docs/1.0/guide/debug.html#Using_the_Perl_Trace

* Chowns all the files and dirs under C<<
  Socialtext::Workspace->LogoRoot() >> to be owned by the Apache
  server's uid/gid, so that the app can save and delete workspace
  logos.

=cut
