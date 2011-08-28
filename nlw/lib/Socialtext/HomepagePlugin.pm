package Socialtext::HomepagePlugin;
# @COPYRIGHT@
use strict;
use warnings;

use base 'Socialtext::Plugin';
use Socialtext::Watchlist;
use Socialtext::l10n qw(loc __);
use URI::Escape;
use Class::Field qw( const );

my $did_you_know_title;
my $did_you_know_text;

const class_id => 'homepage';
const class_title => __('class.homepage');

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add( action     => 'homepage' );
    $registry->add( action     => 'dashboard' );
}

sub homepage {
    my $self = shift;

    if ( my $blog = $self->hub->current_workspace->homepage_weblog ) {
        return $self->redirect( '?'
                . 'action=blog_display;category='
                . URI::Escape::uri_escape_utf8($blog) );
    }
    elsif ($self->hub->current_workspace->homepage_is_dashboard) {
        if ($self->hub->skin->info_param('no_workspace_dashboard')) {
            return $self->central_page;
        }
        else {
            return $self->dashboard;
        }
    }
    return $self->central_page;
}

sub central_page {
    my $self = shift;
    my $title = $self->hub->current_workspace->title;
    my $uri = $self->hub->pages->new_from_name($title)->full_uri;
    return $self->redirect($uri);
}

sub dashboard {
    my $self = shift;

    if ($self->hub->skin->info_param('no_workspace_dashboard')) {
        return $self->redirect('/');
    }

    # Grab the did_you_know text now, so that we don't read the config file on
    # every page hit.
    $did_you_know_title ||= Socialtext::AppConfig->did_you_know_title;
    $did_you_know_text  ||= Socialtext::AppConfig->did_you_know_text;

    return $self->template_render(
        template => 'view/homepage',
        vars     => {
            $self->hub->helpers->global_template_vars,
            did_you_know_title => $did_you_know_title,
            did_you_know_text  => $did_you_know_text,
            title          => loc('wiki.dashboard'),
            username       => $self->hub->current_user->username,
            group_notes    => $self->_get_group_notes_info,
            personal_notes => $self->_get_personal_notes_info,
            whats_new      => $self->_get_whats_new_info,
            watchlist      => $self->_get_watchlist_info,
            wikis          => $self->_get_wikis_info,
            hub            => $self->hub,
            feeds          => $self->_feeds( $self->hub->current_workspace ),
            unplug_uri     => "?action=unplug",
            unplug_phrase  => loc('info.unplug-recent=count', $self->hub->tiddly->default_count),
        },
    );
}


sub _get_group_notes_info {
    my ($self) = @_;
    my $page_title = loc('wiki.notes-title');
    return {
        html      => $self->hub->pages->new_from_name($page_title)->to_html_or_default,
        edit_path => $self->hub->helpers->page_edit_path($page_title),
        view_path => $self->hub->helpers->page_display_path($page_title),
    };
}

sub _get_personal_notes_info {
    my ($self) = @_;
    my $page_title = $self->hub->favorites->preferences->which_page->value;

    if ($page_title) {
        return {
            html      => $self->hub->pages->new_from_name($page_title)->to_html_or_default,
            edit_path => $self->hub->favorites->favorites_edit_path . ';caller_action=homepage',
            view_path => $self->hub->helpers->page_display_path(URI::Escape::uri_escape_utf8($page_title)),
        };
    }
    return {
        html      => '',
        edit_path => $self->hub->helpers->preference_path('favorites'),
    };
}

sub _get_whats_new_info {
    my ($self) = @_;
    
    my $pages = $self->hub->recent_changes->by_seconds_limit();
    return {
        pages => [ map { $self->_get_whats_new_page_info($_) } @$pages ],
    };
}

sub _get_whats_new_page_info {
    my $self = shift;
    my $page = shift;

    my $updated_author = $page->last_edited_by || $self->hub->current_user;
    # This should really be a user object or user-pref object method,
    # but this is what we've got.
    my $show_preview = $self->hub->pages->show_mouseover;

    return {
        link    => $self->hub->helpers->page_display_path($page->id),
        title   => $self->hub->helpers->html_escape($page->title),
        date    => $page->datetime_for_user,
        author  => (  $updated_author
                    ? $updated_author->username
                    : undef),
        preview => (  $show_preview ? $page->summary : '' ),
    }
}


sub _get_watchlist_info {
    my ($self) = @_;

    my $watchlist = Socialtext::Watchlist->new(
        user        => $self->hub->current_user,
        workspace   => $self->hub->current_workspace,
    );

    my $show_preview = $self->hub->pages->show_mouseover;

    my @pages = ();
    # If the page has been purged take it out of the watchlist.
    # For the sake of performance, don't go through all
    # items in the watchlist, just collect first 5 active pages.
    # Because we only want 5 in the homepage dashboard.
    # Leave the rest of purging to display_watchlist action.
    # (Or further invocations to this function.)
    foreach ( $watchlist->pages() ) {
        my $page = $self->hub->pages->new_page($_);
        if ( !$page->active ) {
            $watchlist ||= Socialtext::Watchlist->new(
                user      => $self->hub->current_user,
                workspace => $self->hub->current_workspace
            );
            $watchlist->remove_page( page => $page );
            next;
        } 
        my $updated_author = $page->last_edited_by || $page->hub->current_user;
        push @pages, {
            title   => $self->hub->helpers->html_escape($page->name),
            link    => $self->hub->helpers->page_display_path($_),
            date    => $page->datetime_for_user,
            author  => (  $updated_author
                        ? $updated_author->username
                        : undef),
            preview => (  $show_preview ? $page->summary : '' ),
        };
        last if @pages >= 5;
     }
    return {
        pages => \@pages,
    };
}

sub _get_wikis_info {
    my $self = shift;
    return [
        map { {
            title   => $self->hub->helpers->html_escape($_->title),
            name    => $self->hub->helpers->uri_escape($_->name),
            changes => $self->_get_changes_count_for_wiki($_),
        } } 
        $self->hub->current_workspace->read_breadcrumbs(
            $self->hub->current_user 
        )
    ];
}

sub _get_changes_count_for_wiki {
    my ($self, $workspace) = @_;

    my $pages = $self->hub->recent_changes->by_seconds_limit(
        workspace_id => $workspace->workspace_id,
    );
    my $count = @$pages;
    return $count;
}

1;

