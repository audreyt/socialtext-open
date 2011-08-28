package Socialtext::Job::WatchlistNotify;
# @COPYRIGHT@
use Moose;
use Socialtext::Watchlist;
use Socialtext::WatchlistPlugin;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job::EmailNotify';

override '_user_job_class' => sub {
    return "Socialtext::Job::WatchlistNotifyUser";
};

override '_default_freq' => sub {
    return $Socialtext::WatchlistPlugin::Default_notify_frequency_in_minutes;
};

override '_pref_name' => sub {
    return 'watchlist_notify_frequency';
};

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;
