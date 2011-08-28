# @COPYRIGHT@
package Socialtext::BacklinksPlugin;
use strict;
use warnings;
use Class::Field qw( const );
use Socialtext::Pages;
use Socialtext::l10n qw(loc __);
use Socialtext::String();
use Socialtext::Pageset;
use Socialtext::PageLinks;

use base 'Socialtext::Query::Plugin';

const class_id => 'backlinks';
const class_title          => __('class.backlinks');
const preference_query     => __('wiki.sidebox-number-of-backlinks?');
const cgi_class => 'Socialtext::Backlinks::CGI';

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add(action => 'backlinks_html');
    $registry->add(action => 'show_all_backlinks');
    $registry->add(action => 'orphans_list' );
}

sub show_backlinks {
    my $self = shift;
    my $p = $self->new_preference('show_backlinks');
    $p->query($self->preference_query);
    $p->type('pulldown');
    my $choices = [
        0  => 0,
        5  => 5,
        10 => 10,
        25 => 25,
        50 => 50,
        100 => 100
    ];
    $p->choices($choices);
    $p->default(10);
    return $p;
}

sub box_on {
    my $self = shift;
    $self->preferences->show_backlinks->value and
        $self->hub->action eq 'display'
    ? 1 : 0;
}

sub backlinks_html {
    my $self = shift;
    $self->template_process('backlinks_box_filled.html',
        backlinks => $self->all_backlinks
    );
}

sub show_all_backlinks {
    my $self = shift;
    my $page_id = $self->cgi->page_id;
    my $page = $self->hub->pages->new_from_name($page_id);
    $self->screen_wrap(
        loc('page.backlinks=page', $page->name),
        $self->present_tense_description_for_page($page)
    );
}

sub orphans_list {
    my $self = shift;
    my $pages = $self->get_orphaned_pages();

    my %sortdir = %{ $self->sortdir };
    $self->_make_result_set( \%sortdir, $pages );
    $self->result_set->{hits} = @{$self->result_set->{rows}};

    return $self->display_results(
        \%sortdir,
        feeds => $self->_feeds($self->hub->current_workspace),
        display_title => loc('page.orphaned'),
        Socialtext::Pageset->new(
            cgi => {$self->cgi->all},
            total_entries => $self->result_set->{hits},
        )->template_vars(),
    );
}

sub _make_result_set {
    my $self  = shift;
    my $sortdir = shift;
    my $pages = shift;

    $self->result_set($self->new_result_set());
    my $rs = $self->result_set;
    $rs->{predicate} = 'action=orphans_list';

    {
        local $Socialtext::Page::No_result_times = 1;
        $self->push_result($_) for @$pages;
    }

    $rs->{rows} = [
        sort { $b->{Date} cmp $a->{Date} } @{ $rs->{rows} }
    ];

    $self->result_set->{title} = loc('page.orphaned');
    $self->result_set($self->sorted_result_set($sortdir));
}

sub update {
    my $self = shift;
    my $page = shift;

    Socialtext::PageLinks->new(hub => $self->hub, page => $page)->update;
}

sub all_backlinks {
    my $self = shift;
    $self->all_backlinks_for_page($self->hub->pages->current);
}

sub all_backlink_pages_for_page {
    my $self      = shift;
    my $page      = shift;
    my $incipient = shift;

    my $links = Socialtext::PageLinks->new(hub => $self->hub, page => $page);
    return $links->backlinks;
}

sub all_frontlink_pages_for_page {
    my $self      = shift;
    my $page      = shift;
    my $incipient = shift;

    my $links = Socialtext::PageLinks->new(hub => $self->hub, page => $page);
    my @pages = $links->links;

    # REVIEW: meh, this is oogly, but it's done
    if ($incipient) {
        return ( grep { not $_->active } @pages );
    }
    else {
        return ( grep { $_->active } @pages );
    }
}

sub all_backlinks_for_page {
    my $self = shift;
    my $page  = shift;

    return [
        map { +{ page_uri => $_->uri, page_title => $_->title, page_id => $_->id } }
            sort { $b->modified_time <=> $a->modified_time }
            $self->all_backlink_pages_for_page($page)
    ];
}

sub past_tense_description_for_page {
    my $self = shift;
    my $page = shift;
    return $self->html_description($page, loc('page.backlinks:'));
}

sub present_tense_description_for_page {
    my $self = shift;
    my $page = shift;
    return $self->html_description($page, loc('page.linked-from:'));
}

sub html_description {
    my $self = shift;
    my $page = shift;
    my $text_for_when_there_are_backlinks = shift;

    my $links = $self->hub->backlinks->all_backlinks_for_page($page);
    return '<p>' . loc('page.no-backlinks') . '<p>'
        unless $links and @$links;
    my @items = map {
        '<li>'.$self->hub->helpers->page_display_link($_->{page_title}).'</li>'
    } @$links;
    return join "\n",
        "<p>$text_for_when_there_are_backlinks</p>",
        '<ul>',
        @items,
        '</ul>';
}

# return a list of Socialtext::Page objects that have no backlinks
sub get_orphaned_pages {
    my $self = shift;
    return [] unless $self->hub->current_workspace->real;

    my $pages = Socialtext::Pages->All_active(
        hub => $self->hub,
        workspace_id => $self->hub->current_workspace->workspace_id,
        do_not_need_tags => 1,
        limit => -1,
        orphaned => 1,
    );
    return $pages;
}

package Socialtext::Backlinks::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'page_id';
cgi 'sortby';
cgi 'direction';
cgi 'summaries';
cgi 'offset';

1;

__END__

=head1 DESCRIPTION

Backlinks are one of the context providing devices in a wiki that make the
wiki useful in an emergent and wiki way. Other devices include recent changes
and recently viewed. Using search is helpful, but needing to use search is a
bad smell.

A backlink is a link from some other resource to the resource currently
under consideration. Knowing what links to here places information in
context, sometime creating greater understanding.

=head1 TODO

It would behoove us to eventually migrate this class to using a
database that supports multiple link types.

As it is easier to keep track of forward links, we should do that on
page:store, storing wiki links, interwiki links, and hyperlinks. Our
schema should extend to multiple link types (of course).

Users should only be displayed those links to which they have access
permission, so we should wait on the authorization framework before
proceeding on this work.

Ideally a backlink presentation would be sortable and filterable.

We should provide a TpVortex interface for kicks and giggles:
L<http://tpvortext.blueoxen.net/>.
