# @COPYRIGHT@
package Socialtext::TiddlyPlugin;
use strict;
use warnings;
use Socialtext::l10n '__';

# See
# http://www.socialtext.net/tiddlytext/index.cgi?tiddlywiki_template_for_socialtext
# for data structure info

use base 'Socialtext::Plugin';

use Class::Field qw( const field );
use Encode;
use File::Temp;
use Readonly;
use Socialtext::AppConfig;
use Socialtext::Search 'search_on_behalf';
use Socialtext::String;

const class_id => 'tiddly';
const class_title   => __('class.tiddly');
const cgi_class     => 'Socialtext::Tiddly::CGI';
const default_tag   => 'recent changes';
const default_count => 50;

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add(action => 'unplug');
}

sub unplug {
    my $self = shift;
    my $count = $self->cgi->count() || $self->default_count();

    my $pages;

    # REVIEW: mmm, that reads well, don't it?
    if ( my $page = $self->cgi->page_name() ) {
        $pages = [ $self->hub->pages->new_from_name($page) ];
    }
    elsif ( my $tag = $self->cgi->tag() ) {
        $pages = $self->_pages_for_tag($tag);
    }
    elsif ( my $search = $self->cgi->search_term ) {
        $pages = $self->_pages_for_search($search);
    }
    elsif ( my $watchlist = $self->cgi->watchlist ) {
        $pages = $self->_pages_for_watchlist($watchlist);
    }
    elsif ( my $crumbs = $self->cgi->breadcrumbs ) {
        $pages = [ $self->hub->breadcrumbs->breadcrumb_pages() ];
    }
    else {
        $pages = $self->_pages_for_tag( $self->default_tag );
    }

    my $html = $self->produce_tiddly(
        pages => $pages,
        count => $count,
    );

    return $self->_send_html($html);
}

=head2 produce_tiddly(%args)

Create an HTML string, including $args{count} pages
from the ordered (however you like) list of pages referenced in $args{pages}.
Tiddlers are made from each page and pushed into the tiddlytext.html
template.

=cut
sub produce_tiddly {
    my $self = shift;
    # XXX validate
    my %p = @_;

    my $pages = $p{pages};
    $pages = [ splice( @$pages, 0, $p{count} ) ];
    return $self->_create_html($pages);
}

sub _create_html {
    my $self      = shift;
    my $pages_ref = shift;
    my $tiddlers  = $self->_make_tiddlers($pages_ref);

    return $self->template_process(
        'tiddlytext/tiddlytext.html',
        workspace => $self->hub->current_workspace,
        pages     => $tiddlers,
        default   => {
            workspace => $self->hub->current_workspace->name,
            workspacelist => join (' ',
                map { $_->name } $self->hub->current_user->workspaces()->all()),
            server    => $self->hub->cgi->base_uri(),
        },
    );
}

sub _pages_for_watchlist {
    my $self = shift;
    my $user = shift;

    if ($user eq 'default') {
        $user = $self->hub->current_user;
    } else {
        $user = Socialtext::User->new (username => $user);
    }

    my $watchlist = Socialtext::Watchlist->new(
        user      => $user,
        workspace => $self->hub->current_workspace
    );
    my @pages
        = map { $self->hub->pages->new_from_name($_) } $watchlist->pages;
    return \@pages;
}

# REVIEW: Duplication with Socialtext::SyndicatePlugin
sub _pages_for_search {
    my $self  = shift;
    my $query = shift;

    my ($hits, $hit_count) = search_on_behalf(
            $self->hub->current_workspace->name,
            $query,
            undef, # undefined scope
            $self->hub->current_user,
            sub { },   # FIXME: swallowing this error for now
            sub { } ); # FIXME: swallowing this error for now
    my @pages = map { $self->hub->pages->new_from_name( $_->page_uri ) }
        grep { $_->isa('Socialtext::Search::PageHit') }
            @$hits;

    return \@pages;
}

sub _pages_for_tag {
    my $self = shift;
    my $tag = shift;

    # Changes this to page ids!
    return [ $self->hub->category->get_pages_for_category($tag) ];
}

sub _send_html {
    my $self = shift;
    my $html = shift;

    my $filename = join ('-', $self->hub->current_workspace->name, 'unplugged.html');
    $self->hub->headers->add_attachment(
        type => 'text/html',
        len => undef,
        filename => $filename
    );

    return $html;
}

sub _make_tiddlers {
    my $self      = shift;
    my $pages_ref = shift;

    my @tiddlers;

    foreach my $page (@$pages_ref) {
        push @tiddlers, $self->_tiddler_representation($page);
    }

    return \@tiddlers;
}

sub _tiddler_representation {
    my $self = shift;
    my $page = shift;

    return +{
        title => $page->name,
        modifier => $page->last_editor->email_address, # REVIEW: adjust to best full name?
        modified => $self->_make_tiddly_date( $page->datetime_utc ),
        created  => $self->_make_tiddly_date( $page->createtime_utc ),
        tags     => $self->_make_tiddly_tags( $page->tags ),
        wikitext => $self->_escape_wikitext( $page->content ),
        workspace   => $self->hub->current_workspace->name(),
        page        => $page->uri,
        server      => $self->hub->cgi->base_uri(),
        pageName    => $page->name,
        revision    => $page->revision_id(),
    };
}

sub _escape_wikitext {
    my $self = shift;
    my $content = shift;

    $content = Socialtext::String::html_escape($content);
    $content =~ s{\r}{};

    return $content;
}

sub _make_tiddly_date {
    my $self        = shift;
    my $date_string = shift;

    # 2006-09-19 22:07:00 GMT

    # REVIEW: we should trap the case where no date is available
    my ( $year, $month, $day, $hour, $min, $sec )
        = ( $date_string =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):/ );

    return $year . $month . $day . $hour . $min;
}

sub _make_tiddly_tags {
    my $self = shift;
    my $tags = shift;

    my @formatted_tags;

    foreach my $tag (@$tags) {
        # filter out recent changes which sometimes is there, sometimes now
        next if lc($tag) eq 'recent changes';
        if ( $tag =~ /\s/ ) {
            $tag = "[[$tag]]";
        }
        push @formatted_tags, $tag;
    }

    return join ' ', @formatted_tags;
}
        
package Socialtext::Tiddly::CGI;

use base 'Socialtext::Query::CGI';
use Socialtext::CGI qw( cgi );

cgi 'tag';
cgi 'count';
cgi 'watchlist';
cgi 'search_term';
cgi 'page_name';
cgi 'breadcrumbs';

1;
