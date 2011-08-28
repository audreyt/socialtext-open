package Socialtext::Job::PageIndex;
# @COPYRIGHT@
use Moose;

extends 'Socialtext::Job', 'Socialtext::Job::PageIndex::Base';
with 'Socialtext::CoalescingJob', 'Socialtext::IndexingJob';

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
no Moose;

package Socialtext::Job::PageIndex::Base;
use Moose;
use Socialtext::PageLinks;
use Socialtext::Log qw/st_log/;
use namespace::clean -except => 'meta';

sub do_work {
    my $self    = shift;
    my $page    = $self->page or return;
    my $indexer = $self->indexer or return;

    $indexer->index_page($page->id);
    $self->unlink_cached_wikitext_linkers;

    $self->completed();
}

sub unlink_cached_wikitext_linkers {
    my $self = shift;

    eval {
        my $links = Socialtext::PageLinks->new(
            page => $self->page,
            hub  => $self->hub,
        );
        for my $page (@{ $links->backlinks }) {
            $page->delete_cached_html;
        }
    };
    if ($@) {
        st_log->info("Error cleaning wikitext cache: $@");
    }
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
no Moose;
1;
__END__

=head1 NAME

Socialtext::Job::PageIndex - index a page

=head1 SYNOPSIS

  use Socialtext::JobCreator;
  Socialtext::JobCreator->index_page($page, $config);

=head1 DESCRIPTION

Index a page's content.

=cut
