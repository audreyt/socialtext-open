# @COPYRIGHT@
package Socialtext::WatchlistPlugin;
use strict;
use warnings;

use base 'Socialtext::Query::Plugin';
use Class::Field qw( const field );
use Socialtext::EmailNotifier;
use Socialtext::Watchlist;
use Socialtext::l10n qw(loc __);
use Socialtext::Events;
use Socialtext::Pageset;

const class_id    => 'watchlist';
const class_title => __('class.watchlist');
const cgi_class   => 'Socialtext::Watchlist::CGI';
const listview_extra_columns => { watchlist => 1 };
field 'lock_handle';

sub register {
    my $self     = shift;
    my $registry = shift;
    $registry->add( action     => 'display_watchlist' );
    $registry->add( action     => 'watchlist' );
    $registry->add( action     => 'add_to_watchlist' );
    $registry->add( action     => 'remove_from_watchlist' );

    $self->_register_prefs($registry);
}

sub pref_names {
    return qw(watchlist_notify_frequency watchlist_links_only);
}

sub init {
    my $self = shift;
    $self->SUPER::init(@_);
}

our $Default_notify_frequency_in_minutes = 1440;

sub watchlist_notify_frequency_data {
    my $self = shift;

    return {
        title => loc('watchlist.frequence-of-updates'),
        default_setting => $Default_notify_frequency_in_minutes,
        options => [
            {setting => 0, display => __('time.never')},
            {setting => 1, display => __('every.minute')},
            {setting => 5, display => __('every.5minutes')},
            {setting => 15, display => __('every.15minutes')},
            {setting => 60, display => __('every.hour')},
            {setting => 360, display => __('every.6hours')},
            {setting => 1440, display => __('every.day')},
            {setting => 4320, display => __('every.3days')},
            {setting => 10080, display => __('every.week')},
        ],
    };
}

sub watchlist_notify_frequency {
    my $self = shift;
    
    my $data = $self->watchlist_notify_frequency_data;
    my $p = $self->new_preference('watchlist_notify_frequency');

    $p->query($data->{title});
    $p->type('pulldown');
    $p->choices($self->_choices($data));
    $p->default($data->{default_setting});

    return $p;
}

sub watchlist_links_only_data {
    my $self = shift;

    return {
        title => loc('watchlist.digest-information'),
        default_setting => 'expanded',
        options => [
            {setting => 'condensed', display => __('email.page-name-link-only')},
            {setting => 'expanded', display => __('email.page-name-link-author-date')},
        ],
    };
}

sub watchlist_links_only {
    my $self = shift;

    my $data = $self->watchlist_links_only_data;
    my $p = $self->new_preference('watchlist_links_only');

    $p->query($data->{title});
    $p->type('radio');
    $p->choices($self->_choices($data));
    $p->default($data->{default_setting});

    return $p;
}

sub page_watched {
    my $self      = shift;
    my $watchlist = Socialtext::Watchlist->new(
        user      => $self->hub->current_user,
        workspace => $self->hub->current_workspace
    );

    my $page = $self->hub->pages->current;
    if ( $watchlist->has_page( page => $page ) ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub pages_in_watchlist {
    my $self      = shift;
    my $user      = shift;
    my $workspace = shift;
    my $pages     = shift;
    my @return;
    my $watchlist = Socialtext::Watchlist->new(
        user      => $user,
        workspace => $workspace
    );
    foreach my $page (@$pages) {
        push( @return, $page )
            if ( $watchlist->has_page( page => $page ) );
    }
    return ( \@return );
}

sub add_to_watchlist {
    my $self = shift;

    $self->reject_guest(type => 'watchlist_requires_account');

    my $watchlist = Socialtext::Watchlist->new(
        user      => $self->hub->current_user,
        workspace => $self->hub->current_workspace
    );

    my $page = $self->hub->pages->new_from_name( $self->cgi->page );
    if ( !$watchlist->has_page( page => $page ) ) {
        $watchlist->add_page( page => $page );
    }

    Socialtext::Events->Record({
        event_class => 'page',
        action => 'watch_add',
        page => $page,
    });

    # Ideally this should be in Socialtext::Watchlist, but it doesn't have
    # a hub or know the actor.
    $self->hub->pluggable->hook( 'nlw.page.watch',
        [$page, workspace => $self->hub->current_workspace]
    );
    return '1';
}

sub remove_from_watchlist {
    my $self = shift;

    $self->reject_guest(type => 'watchlist_requires_account');

    my $watchlist = Socialtext::Watchlist->new(
        user      => $self->hub->current_user,
        workspace => $self->hub->current_workspace
    );

    if ( $self->cgi->page ) {
        my $page = $self->hub->pages->new_from_name( $self->cgi->page );
        $watchlist->remove_page( page => $page );
        $self->_record_watch_delete($page);
        return '0';
    }
    else {
        my @pages_to_remove = map { split /\000/ } $self->cgi->selected;
        for my $checked_page (@pages_to_remove) {
            my $page = $self->hub->pages->new_page($checked_page);
            $watchlist->remove_page( page => $page );
            $self->_record_watch_delete($page);
        }
        $self->redirect("action=display_watchlist");
    }
}

sub _record_watch_delete {
    my ($self, $page) = @_;

    # Ideally this should be in Socialtext::Watchlist, but it doesn't have
    # a hub or know the actor.

    Socialtext::Events->Record({
        event_class => 'page',
        action => 'watch_delete',
        actor => $self->hub->current_user,
        workspace => $self->hub->current_workspace,
        page => $page,
        revision_count => $page->revision_count,
        revision_id => $page->revision_id,
    });

    $self->hub->pluggable->hook( 'nlw.page.unwatch',
        [$page, workspace => $self->hub->current_workspace]
    );
}

sub watchlist {
    my $self = shift;
    $self->display_watchlist();
}

sub display_watchlist {
    my $self = shift;

    $self->reject_guest(type => 'watchlist_requires_account');

    my $watchlist = Socialtext::Watchlist->new(
        user      => $self->hub->current_user,
        workspace => $self->hub->current_workspace
    );

    my @pages = $watchlist->pages;
    return $self->watchlist_changes( \@pages );
}

sub _feeds {
    my $self = shift;
    my $workspace = shift;

    my $feeds = $self->SUPER::_feeds($workspace);
    $feeds->{rss}->{page} = {
        title => $feeds->{rss}->{watchlist}->{title},
        url => $feeds->{rss}->{watchlist}->{url},
    };
    $feeds->{atom}->{page} = {
        title => $feeds->{atom}->{watchlist}->{title},
        url => $feeds->{atom}->{watchlist}->{url},
    };

    return $feeds;
}

sub watchlist_changes {
    my $self  = shift;
    my $pages = shift;

    my %sortdir = %{ $self->sortdir };
    $self->result_set( $self->new_result_set() );

    my $watchlist;
    foreach my $page (@$pages) {
        my $page_object = $self->hub->pages->new_page($page);

        # If the page has been purged take it out of the watchlist
        if ( !$page_object->active ) {
            $watchlist ||= Socialtext::Watchlist->new(
                user      => $self->hub->current_user,
                workspace => $self->hub->current_workspace
            );
            $watchlist->remove_page( page => $page_object );
            next;
        }

        $self->push_result($page_object);
    }
    $self->result_set( $self->sorted_result_set( \%sortdir ) );
    $self->result_set->{display_title} = loc("watch.current-pages");
    $self->result_set->{hits} = @{$self->result_set->{rows}};

    $self->write_result_set;

    return $self->display_results(
        \%sortdir,
        feeds         => $self->_feeds( $self->hub->current_workspace ),
        Socialtext::Pageset->new(
            cgi => {$self->cgi->all},
            total_entries => $self->result_set->{hits},
        )->template_vars(),
        empty_include => 'view/empty_watchlist',
    );
}

#------------------------------------------------------------------------------#
package Socialtext::Watchlist::CGI;

use base 'Socialtext::Query::CGI';
use Socialtext::CGI qw( cgi );

cgi 'page' => '-clean_path';
cgi 'title';
cgi 'watchlist';
cgi 'selected';
cgi 'id' => '-clean_path';
cgi 'offset';

1;
