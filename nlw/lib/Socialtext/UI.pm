# @COPYRIGHT@
package Socialtext::UI;

use strict;
use warnings;

our $VERSION = '0.01';

sub EntriesPerPage {
    return 50;
}

sub PagesPerSet {
    return 10;
}


1;

__END__

=head1 NAME

Socialtext::UI - Functions for web UI

=head1 SYNOPSIS

Perhaps a little code snippet.

  use Socialtext::UI;

  my $entries_per_page = Socialtext::UI->EntriesPerPage;

=head1 DESCRIPTION

This module provides various methods intended to be used by the web
UI.

Right now this module is mostly glorified constants, but by using an
API rather than hard-coding numbers, we can easily switch over to
using application preferences, and without too much trouble even use
per-user preferences.

=head1 METHODS/FUNCTIONS

This module provides the following class methods:

=over 4

=item * Socialtext::UI->EntriesPerPage()

The number of entries to show on a page when displaying paged data.

=item * Socialtext::UI->PagesPerSet()

How many pages to group into a set when using paging controls.

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-socialtext-ui@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.  I will be notified, and then you'll automatically be
notified of progress on your bug as I make changes.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., All Rights Reserved.

=cut
