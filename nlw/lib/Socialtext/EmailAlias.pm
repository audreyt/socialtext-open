# @COPYRIGHT@
package Socialtext::EmailAlias;

use strict;
use warnings;

use Socialtext::AppConfig;
use Socialtext::Paths;


sub create_alias {
    my $name = shift;

    my $admin_cmd = Socialtext::AppConfig->admin_script();
    if (Socialtext::AppConfig->is_dev_env) {
        # need to prefix it with the current perl interpreter so that
        # exim/whatever can run it in a dev-env context (where the #! is
        # likely "/usr/bin/env perl")
        $admin_cmd = "$^X $admin_cmd";
    }

    my $line = qq{$name: "|$admin_cmd deliver-email --workspace $name"};
    my $aliases_file = Socialtext::Paths::aliases_file();

    open my $fh, '>>', $aliases_file
        or die "Cannot append to $aliases_file: $!";
    print $fh $line, "\n"
        or die "Cannot write to $aliases_file: $!";
    close $fh
        or die "Cannot write to $aliases_file: $!";
}

sub delete_alias {
    my $name = shift;

    my $aliases_file = Socialtext::Paths::aliases_file();

    my @aliases;
    open my $fh, '<', $aliases_file
        or die "Cannot read $aliases_file: $!";
    for my $line (qx(grep "^." "$aliases_file")) {
        next if $line =~ /^\Q$name\E/;
        push @aliases, $line;
    }
    close $fh;

    open $fh, '>', $aliases_file
        or die "Cannot write to $aliases_file: $!";
    for my $line (@aliases) {
        print $fh $line
            or die "Cannot write to $aliases_file: $!";
    }
    close $fh
        or die "Cannot write to $aliases_file: $!";
}

sub find_alias {
    my $name = shift;

    for my $file ( '/etc/aliases', Socialtext::Paths::aliases_file() ) {
        next unless -e $file;

        for my $line (qx(grep "^$name: " "$file")) {
            return $2 if $line =~ /^([\w\.\-]+): (.*)$/ and $1 eq $name;
        }
    }

    return;
}

1;


__END__

=head1 NAME

Socialtext::EmailAlias - Functions for manipulating email alias files

=head1 SYNOPSIS

  Socialtext::EmailAlias::create_alias('foobar');
  Socialtext::EmailAlias::delete_alias('foobar');

  if ( Socialtext::EmailAlias::find_alias('foobar') ) { ... }

=head1 DESCRIPTION

This module contains a few functions for changing and reading the
email aliases file(s) used by Socialtext Wiki.

=head1 FUNCTIONS

This module provides the following functions, none of which are
exported:

=head2 create_alias($name)

Given a workspace name, this function creates an alias in the
Socialtext Wiki aliases file (usually F</etc/aliases.deliver>). This
alias will call the appropriate script to "deliver" email to the named
workspace.

=head2 delete_alias($name)

Given an alias name, this deletes the alias from the Socialtext Wiki
aliases file, if it exists.

=head2 find_alias($name)

Given a possible alias name, this searches both the Socialtext Wiki
aliases file and the system aliases file (F</etc/aliases>) for a
matching alias. If one is found, it returns the right-hand side of the
alias. Otherwise, it returns false.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc., All Rights Reserved.

=cut

