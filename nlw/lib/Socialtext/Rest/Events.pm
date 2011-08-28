package Socialtext::Rest::Events;
# @COPYRIGHT@
use warnings;
use strict;
use base 'Socialtext::Rest::EventsBase';
use Socialtext::HTTP ':codes';
use Socialtext::JSON qw/decode_json/;
use Socialtext::l10n 'loc';
use Socialtext::User;
use Socialtext::Role;
use Socialtext::SQL qw/:txn/;
use Guard;

sub allowed_methods {'GET, POST'}

sub collection_name {
    my $self = shift;
    $self->rest->query->param('contributions')
        ? loc("rest.all-changes")
        : loc("rest.all-events");
}

sub get_resource {
    my $self = shift;

    my @args = ($self->extract_common_args(), 
                $self->extract_page_args(),
                $self->extract_people_args());

    my $events = Socialtext::Events->Get($self->rest->user, @args);
    $events ||= [];

    return $events;
}


sub POST_text {
    die "POST text?!";
}

sub POST_json {
    my ( $self, $rest ) = @_;
    return $self->if_authorized( 'POST', '_post_json' );
}

sub POST_form {
    my ( $self, $rest ) = @_;
    return $self->if_authorized( 'POST', '_post_form' );
}

sub _post_json {
    my $self = shift;
    my $json = $self->rest->getContent();
    my $data = decode_json($json);

    $data->{actor} ||= {};
    $data->{person} ||= {};
    $data->{page} ||= {};

    my %params = (
        at => $data->{at},
        event_class => $data->{event_class},
        action => $data->{action},
        'actor.id' => $data->{actor}{id},
        'actor.name' => $data->{actor}{name},
        'person.id' => $data->{person}{id},
        'person.name' => $data->{person}{name},
        'page.id' => $data->{page}{id},
        'page.workspace_name' => $data->{page}{workspace_name},
        tag_name => $data->{tag_name},
    );

    return $self->_post_an_event(\%params, $data->{context});
}

sub _post_form {
    my $self = shift;
    my $cgi = $self->{_test_cgi} || Socialtext::CGI::Scrubbed->new;
 
    my %params;
    foreach my $key (qw(event_class action actor.id person.id page.id page.workspace_name tag_name)) {
        my $value = $cgi->param($key);
        $params{$key} = $value if defined $value;
    }

    my $context = $cgi->param('context');
    if ($context) {
        $context = eval { decode_json($context) };
        if ($@) {
            $self->rest->header(
                -status => HTTP_400_Bad_Request,
                -type   => 'text/plain',
            );
            warn $@;
            return "Event recording failure; 'context' must be vaild JSON";
        }
    }

    return $self->_post_an_event(\%params, $context);
}

sub _post_an_event {
    my $self = shift;
    my $params = shift;
    my $context = shift;

    my $event_class = $params->{'event_class'};
    return $self->_missing_param('event_class')
        unless $event_class;

    my $action = $params->{'action'};
    return $self->_missing_param('action')
        unless $action;

    my $actor_id = $params->{'actor.id'};
    if (!$actor_id && $self->rest->user && !$self->rest->user->is_guest) {
        $actor_id = $self->rest->user->user_id;
        my $uname = $self->rest->user->username;
    }
    return $self->_missing_param('actor.id')
        unless $actor_id;

    my %event = (
        event_class  => $event_class,
        action => $action,
        actor  => $actor_id,
    );

    my $at = $params->{'at'};
    $event{timestamp} = $at if $at;

    $event{context} = $context
        if defined($context) && length($context);

    my $tag_name = $params->{'tag_name'};
    $event{tag_name} = $tag_name if $tag_name;


    if ($event_class eq 'person') {
        my $person_id = $params->{'person.id'};
        return $self->_missing_param('person.id')
            unless $person_id;
        $event{person} = $person_id;
    }
    elsif ($event_class eq 'page') {
        my $page_id = $params->{'page.id'};
        return $self->_missing_param('page.id')
            unless $page_id;
        my $ws_name = $params->{'page.workspace_name'};
        return $self->_missing_param('page.workspace_name')
            unless $ws_name;

        my $ws = Socialtext::Workspace->new(name => $ws_name);
        if (!$ws) {
            $self->rest->header(
                -status => HTTP_400_Bad_Request,
                -type   => 'text/plain',
            );
            return "Invalid workspace '$ws_name'";
        }

        $event{page} = $page_id;
        $event{workspace} = $ws->workspace_id;
    }

    eval {
        Socialtext::Events->Record(\%event);
    };
    if ($@) {
        $self->rest->header(
            -status => HTTP_500_Internal_Server_Error,
            -type   => 'text/plain',
        );
        warn $@;
        return "Event recording failure";
    }

    $self->rest->header(
        -status => HTTP_201_Created,
        -type => 'text/plain',
    );
    return "Event recording success"
}

sub _missing_param {
    my $self = shift;
    my $param = shift;
    $self->rest->header(
        -status => HTTP_400_Bad_Request,
        -type   => 'text/plain',
    );
    return "Event recording failure: Missing required parameter '$param'";
}

1;
