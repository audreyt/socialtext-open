package Socialtext::Job::WeblogPing;
# @COPYRIGHT@
use Moose;
use Socialtext::WeblogUpdates;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

sub do_work {
    my $self = shift;
    my $page = $self->page or return;

    Socialtext::WeblogUpdates->new(hub => $page->hub)->send_ping($page);

    $self->completed();
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;
