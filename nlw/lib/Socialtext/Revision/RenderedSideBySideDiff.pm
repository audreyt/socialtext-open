package Socialtext::Revision::RenderedSideBySideDiff;
# @COPYRIGHT@

use strict;
use warnings;

use base 'Socialtext::Revision::SideBySideDiff';

sub diff_rows {
    my $self = shift;
    return [{
        before => $self->before_page->to_html,
        after => $self->after_page->to_html,
    }];
}

1;

=head1 NAME

Socialtext::Revision::RenderedSideBySideDiff - Display both revisions

=head1 SYNOPSIS

  package Socialtext::Revision::RenderedSideBySideDiff;
  my $differ = Socialtext::Revision::RenderedSideBySideDiff->new(
    before_page => $before_page,
    after_page => $new_page,
    hub => $hub,
  );
  my $rows = $differ->diff_rows;

=head1 DESCRIPTION

This class just presents tthe two versions side by side without highlighting.

=cut
