package Socialtext::Job::WatchlistNotifyUser;
# @COPYRIGHT@
use Moose;
use Socialtext::Watchlist;
use Socialtext::l10n qw/loc/;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job::EmailNotifyUser';

override '_notification_vars' => sub {
    my $self = shift;
    my $ws = $self->workspace;

    return (
        subject => loc('watch.email-subject=wiki', $ws->title),
        text_template => 'email/watchlist.txt',
        html_template => 'email/watchlist.html',
    );
};

override '_pages_to_send' => sub {
    my $self = shift;
    my $pages = $self->hub->pages;

    my $wl = Socialtext::Watchlist->new(
        user      => $self->user,
        workspace => $self->workspace,
    );
    my @page_ids = $wl->pages(new_as => $self->arg->{pages_after});

    return [
        grep { !$_->is_system_page }
        map { $pages->new_page($_) }
        @page_ids
    ];
};

override '_extra_template_vars' => sub {
    my $self = shift;
    return (
        preference_uri   => $self->workspace->uri . 'watchlistprefs',
    );
};

override '_links_only' => sub {
    my $self = shift;
    my $prefs = shift;
    return $prefs->watchlist_links_only->value eq 'condensed' ? 0 : 1;
};

override '_frequency_pref' => sub {
    my $self = shift;
    my $prefs = shift;
    return $prefs->{watchlist_notify_frequency}->value * 60;
};

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;
