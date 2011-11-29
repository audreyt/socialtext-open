package Socialtext::Revision::HtmlSideBySideDiff;
# @COPYRIGHT@

use strict;
use warnings;

use Socialtext::URI;
use HTMLDiff;

use base 'Socialtext::Revision::SideBySideDiff';

sub diff_rows {
    my $self = shift;

    my $before = $self->before_page->to_html;
    my $after = $self->after_page->to_html;

    my $webroot = Socialtext::URI::uri(path => '');

    my @additions = HTMLDiff::filterhtml($before, $after, $webroot);
    my @subtractions = HTMLDiff::filterhtml($after, $before, $webroot);

    my $offset = 0;
    foreach (@subtractions) {
        substr($before, $_->{start} + $_->{len} + $offset, 0) = '</span>';
        substr($before, $_->{start} + $offset, 0) = '<span class="st-revision-compare-old">';
        $offset += 7 + 38;
    }
    
    $offset = 0;
    foreach (@additions) {
        substr($after, $_->{start} + $_->{len} + $offset, 0) = '</span>';
        substr($after, $_->{start} + $offset, 0) = '<span class="st-revision-compare-new">';
        $offset += 7 + 38;
    }
    return [{
        before => $before,
        after => $after,
    }];
}

1;

=head1 NAME

Socialtext::Revision::HtmlSideBySideDiff - HTML Revision Compare

=head1 SYNOPSIS

  package Socialtext::Revision::HtmlSideBySideDiff;
  my $differ = Socialtext::Revision::HtmlSideBySideDiff->new(
    before_page => $before_page,
    after_page => $new_page,
    hub => $hub,
  );
  my $rows = $differ->diff_rows;

=head1 DESCRIPTION

Compare the HTML from two revisions.

=cut
