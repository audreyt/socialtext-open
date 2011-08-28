package Socialtext::Rest::EventsBase;
# @COPYRIGHT@
use warnings;
use strict;
use base qw(Socialtext::Rest::Collection);

use Socialtext::Events;
use Socialtext::Events::Reporter;
use Socialtext::User;
use Socialtext::Workspace;
use Socialtext::Exceptions qw/auth_error bad_request/;
use Socialtext::JSON qw/encode_json/;
use Socialtext::Timer;
use Socialtext::l10n 'loc';
use Socialtext::Permission qw/ST_READ_PERM/;
use List::MoreUtils qw/uniq/;

use constant MAX_EVENT_COUNT => 500;
use constant DEFAULT_EVENT_COUNT => 25;

sub allowed_methods { 'GET' }
sub collection_name { loc('rest.events') }
sub events_auth_method { 'default' }

our @ADD_HEADERS = (); # for testing only!

sub default_if_authorized {
    my $self = shift;
    my $method = shift;
    my $perl_method = shift;

    my $user = $self->rest->user;
    return $self->not_authorized 
        unless ($user && $user->is_authenticated());

    my $event_class = $self->rest->query->param('event_class');
    if (defined $event_class && $event_class eq 'person') {
        return $self->not_authorized 
            unless $user->can_use_plugin('people');
    }

    return $self->$perl_method(@_);
}

sub people_if_authorized {
    my $self = shift;
    my $method = shift;
    my $perl_method = shift;

    my $user = $self->rest->user;
    return $self->not_authorized 
        unless ($user && $user->is_authenticated());

    return $self->not_authorized
        unless $user->can_use_plugin('people');

    return $self->$perl_method(@_);
}

sub if_authorized {
    my $self = shift;
    my $method = $self->events_auth_method;
    if ($method eq 'people') {
        return $self->people_if_authorized(@_);
    }
    elsif ($method eq 'page') {
        return $self->SUPER::if_authorized(@_);
    }
    else {
        return $self->default_if_authorized(@_);
    }
}

# returns zero or more things, lowercased
sub _bunch_of {
    my $q = shift;
    my $name = shift;
    my $checker = shift;
    my @result;

    for my $param ($name,"$name!") {
        my $val = $q->param($param);
        next unless defined $val;
        if (defined $val) {
            $val = lc $val unless $name eq 'tag_name';
            if ($val eq '') {
                $val = undef;
            }
            elsif ($val =~ /,/) {
                $val = [split(/,/, $val)];
            }
        }
        $param =~ tr/./_/;
        $checker->($val) if $checker;
        push @result, $param => $val;
    }
    return @result;
}

# returns zero or one thing, verbatim
sub _one {
    my $q = shift;
    my $name = shift;

    my $val = $q->param($name); # datetime
    return unless defined $val;
    $name =~ tr/./_/;
    return $name => $val;
}

sub extract_common_args {
    my $self = shift;
    my $q = $self->rest->query;
    my $viewer = Socialtext::User->Resolve($self->rest->user);
    my @args;

    my $count = $q->param('count') || 
                $q->param('limit') || DEFAULT_EVENT_COUNT;
    $count = DEFAULT_EVENT_COUNT unless $count =~ /^\d+$/;
    $count = MAX_EVENT_COUNT if ($count > MAX_EVENT_COUNT);
    push @args, count => $count if ($count > 0);

    my $offset = $q->param('offset') || 0;
    $offset = 0 unless $offset =~ /^\d+$/;
    push @args, offset => $offset if ($offset > 0);

    push @args,
        _one($q,'before'),
        _one($q,'after'),
        _one($q, 'activity'),
        _one($q, 'direct'),
        _one($q, 'link_dictionary'),
        _bunch_of($q,'account_id'),
        _bunch_of($q,'group_id', sub {
                # is the viewer IN this group?
                my $group_id = shift;
                my $group = Socialtext::Group->GetGroup(group_id => $group_id);
                Socialtext::Exception::NoSuchResource
                    ->throw(name => "group: $group_id")
                    unless $group;
                auth_error "you don't have permission to view group $group_id"
                    unless $group->user_can(
                        user       => $viewer,
                        permission => ST_READ_PERM,
                    );
            }),
        _bunch_of($q,'event_class'),
        _bunch_of($q,'action', sub {
                # no longer serve view events
                my $action = shift;
                bad_request "view is not a valid action" if $action eq 'view';
            }),
        _bunch_of($q,'tag_name'),
        _bunch_of($q,'actor.id');

    return @args
}

sub extract_page_args {
    my $self = shift;
    my $q = $self->rest->query;

    my @args;
    my @workspace_ids;

    my $workspace_id = $q->param('page.workspace_id');
    if ($workspace_id && $workspace_id =~ /^\d+(,\d+)*$/) {
        push @workspace_ids, split(',', $workspace_id);
    }

    my $workspace_name = $q->param('page.workspace_name');
    if ($workspace_name) {
        my @names = split(',', $workspace_name);
        for my $name (@names) {
            my $ws = Socialtext::Workspace->new(name => $name);
            Socialtext::Exception::NoSuchResource->throw(name => $name)
                unless $ws;
            push @workspace_ids, $ws->workspace_id;
        }
    }

    if (@workspace_ids > 1) {
        push @args, page_workspace_id => [uniq @workspace_ids];
    }
    elsif (@workspace_ids == 1) {
        push @args, page_workspace_id => $workspace_ids[0];
    }

    push @args,
        _bunch_of($q,'page.id'),
        _one($q,'contributions'),
        _one($q,'signals');

    return @args;
}

sub extract_people_args {
    my $self = shift;
    my $q = $self->rest->query;
    return _one($q, 'followed'),
           _one($q, 'with_my_signals'),
           _bunch_of($q,'person.id');
}

sub _add_test_headers {
    my $self = shift;

    $self->rest->header(
        $self->rest->header,
        @ADD_HEADERS,
    );
    @ADD_HEADERS = ();
}

sub resource_to_text {
    my ($self, $events) = @_;
    $self->_add_test_headers();
    $self->template_render('data/events.txt', {
        events => $events,
        viewer => $self->rest->user,
    });
}

sub resource_to_html {
    my ($self, $events) = @_;
    $self->_add_test_headers();
    $self->template_render('data/events.html', {
        events => $events,
        viewer => $self->rest->user,
    });
}

sub resource_to_atom {
    my ($self, $events) = @_;

    $self->_add_test_headers();

    # Format dates for atom
    $_->{at} =~ s{^(\d+-\d+-\d+) (\d+:\d+:\d+).\d+Z$}{$1T$2+0} for @$events;
    $self->template_render('data/events.atom.xml', {
        events => $events,
        viewer => $self->rest->user,
    });
}

sub _htmlize_event {
    my ($self, $event) = @_;
    my $renderized = $self->template_render('data/event', {
        event => $event,
        out => 'html',
    });
    $event->{html} = $renderized;
    return $event;
}

sub resource_to_json {
    my ($self, $events) = @_;
    my $html = $self->rest->query->param('html');
    unless (defined $html and !$html) {
        $self->_htmlize_event($_) for @$events;
    }
    $self->_add_test_headers();
    return encode_json($events);
}

1;
