package Socialtext::Hub;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::MockBase';
# Because we're mocked, we load other mocked libraries.
use Socialtext::Rest;
use Socialtext::Workspace;
use Socialtext::Pages;
use Socialtext::CGI;
use Socialtext::Headers;
use Socialtext::Preferences;
use Socialtext::User;
use Socialtext::Watchlist;
use Socialtext::BreadCrumbsPlugin;
use Socialtext::HitCounterPlugin;

# use real classes unless already mocked
use unmocked 'Socialtext::Helpers';
use unmocked 'Socialtext::AccountFactory';
use unmocked 'Socialtext::DisplayPlugin';
use unmocked 'Socialtext::BacklinksPlugin';
use unmocked 'Socialtext::FavoritesPlugin';
use unmocked 'Socialtext::CategoryPlugin';
use unmocked 'Socialtext::RecentChangesPlugin';
use unmocked 'Socialtext::SyndicatePlugin';
use unmocked 'Socialtext::TiddlyPlugin';
use unmocked 'Socialtext::FetchRSSPlugin';
use unmocked 'Socialtext::Template';
use unmocked 'Socialtext::Stax';
use unmocked 'Socialtext::Pluggable::Adapter';
use unmocked 'Socialtext::Formatter';
use unmocked 'Socialtext::Formatter::Viewer';
use unmocked 'Socialtext::Attachments';

# warn "MOCKED HUB";

sub import {
    my $class = shift;
    return if (@_%2);
    my %args = @_;
    if ($args{gtv}) {
        no warnings 'redefine';
        if (ref($args{gtv}) eq 'CODE') {
            *Socialtext::Helpers::global_template_vars = $args{gtv};
        }
        elsif ($args{gtv} eq 'empty') {
            *Socialtext::Helpers::global_template_vars = sub { return };
        }
    }
}

sub init {}
sub load {}

sub current_workspace {
    my $self = shift;
    $self->{current_workspace} ||= Socialtext::Workspace->new(
        title => 'current'
    );
    return $self->{current_workspace};
}

sub pages {
    my $self = shift;
    $self->{pages} ||= Socialtext::Pages->new(hub => $self);
    return $self->{pages};
}

sub headers { $_[0]{headers} || Socialtext::Headers->new };

sub cgi { $_[0]{cgi} || Socialtext::CGI->new }

sub preferences_object { $_[0]{preferences} || Socialtext::Preferences->new }
sub preferences        { $_[0]->preferences_object }

sub current_user { $_[0]{current_user} || Socialtext::User->new(user_id => 1) }

sub checker { shift }

sub action {}

sub best_locale { 'en' }

# for "simplicity" main just returns ourself
sub main { shift }
sub status_message { 'mock_hub_status_message' }


# These methods return real libraries
sub account_factory { 
    return $_[0]{account_factory} 
        ||= Socialtext::AccountFactory->new(hub => $_[0]);
}

sub helpers { 
    return $_[0]{helpers} ||= Socialtext::Helpers->new(hub => $_[0]);
}
sub skin {
    my $self = shift;
    return $self->{skin} || Socialtext::Skin->new(hub => $self);
}

sub display { 
    return $_[0]{display} ||= Socialtext::DisplayPlugin->new(hub => $_[0]);
}

sub css { 
    return $_[0]{css} ||= Socialtext::CSS->new(hub => $_[0]);
}

sub favorites { 
    return $_[0]{favorites} ||= 
        Socialtext::FavoritesPlugin->new(hub => $_[0]);
}

sub category { 
    return $_[0]{category} ||= Socialtext::CategoryPlugin->new(hub => $_[0]);
}

sub recent_changes { 
    return $_[0]{recent_changes} ||= 
        Socialtext::RecentChangesPlugin->new(hub => $_[0]);
}

sub syndicate { 
    return $_[0]{syndicate} ||= Socialtext::SyndicatePlugin->new(hub => $_[0]);
}

sub tiddly { 
    return $_[0]{tiddly} ||= Socialtext::TiddlyPlugin->new(hub => $_[0]);
}

sub fetchrss { 
    return $_[0]{fetchrss} ||= Socialtext::FetchRSSPlugin->new(hub => $_[0]);
}

sub template {
    return $_[0]{template} ||= Socialtext::Template->new(hub => $_[0]);
}

sub stax {
    return $_[0]{stax} ||= Socialtext::Stax->new(hub => $_[0]);
}

sub pluggable {
    return $_[0]{pluggable} ||= Socialtext::Pluggable::Adapter->new(hub => $_[0]);
}

sub check_permission { 1 }

sub can_modify_locked { return 1; }

sub backlinks {
    return $_[0]{backlinks} ||= Socialtext::BacklinksPlugin->new(hub => $_[0]);
}

sub formatter {
    return $_[0]{formatter} ||= Socialtext::Formatter->new(hub => $_[0]);
}

sub attachments {
    return $_[0]{attachments} ||= Socialtext::Attachments->new(hub => $_[0]);
}

sub breadcrumbs {
    return $_[0]{breadcrumbs} ||= Socialtext::BreadCrumbsPlugin->new(hub => $_[0]);
}

sub hit_counter {
    return $_[0]{hit_counter} ||= Socialtext::HitCounterPlugin->new(hub => $_[0]);
}

sub viewer {
    return $_[0]{viewer} ||= Socialtext::Formatter::Viewer->new(hub => $_[0]);
}

sub rest {
    my $self = shift;
    return $self->{rest} ||= Socialtext::Rest->new(
        Socialtext::Rest->new(undef, $self->cgi),
        $self->cgi,
    );
}

# Timezone plugin mocked up here
sub timezone { $_[0] } # return ourself
sub date_local { $_[1] } # return the date we passed in
sub get_date { $_[1] } # return the date we passed in
sub get_date_user { $_[1] } # return the date we passed in

# Authz plugin mocked up here
sub authz { $_[0] } # return ourself

sub registry_loaded { 1 }

# Mock up the registry here
sub registry { $_[0] } # return ourself
sub lookup { $_[0] } # return ourself
sub wafl { +{} } # empty registry hash

1;
