package Test::Socialtext::Workspace;
# @COPYRIGHT@

use strict;
use warnings;

sub delete_recklessly {
    my ($class, $ws) = @_;

    # Delete the WS
    $ws->delete();
}

1;

=head1 NAME

Test::Socialtext::Workspace - methods to operate on Workspaces from within tests

=head1 SYNOPSIS

  use Test::Socialtext::Workspace;

  # recklessly delete a WS from the DB
  $ws = Socialtext::Workspace->new(name => $ws_name);
  Test::Socialtext::Workspace->delete_recklessly($ws);

=head1 DESCRIPTION

C<Test::Socialtext::Workspace> implements methods that can be used to operate
on C<Socialtext::Workspace> objects from within test suites.

These methods are placed here so that its B<really> obvious that you don't
want to be using these methods as part of the regular operation of the system.
They're usful for test purposes, but beyond that you should keep your fingers
out of them.

=head1 METHODS

=over

=item B<Test::Socialtext::Workspace-E<gt>delete_recklessly($ws)>

Deletes the given C<$ws> record outright, purging B<all> of the data related
to this WS from the DB.  This is an B<irreversible> action!

=back

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc., All Rights Reserved.

=cut
