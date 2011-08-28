#!/usr/bin/env perl
# @COPYRIGHT@
use warnings;
use strict;

use EV;
use Coro;
use AnyEvent;
use Coro::AnyEvent;
use AnyEvent::HTTP;
use AnyEvent::AIO ();
use IO::AIO;
use Guard;
use JSON::XS qw/encode_json decode_json/;
use Data::Dumper;
use URI::Escape qw/uri_escape_utf8/;
use List::Util qw/sum/;

use constant TRACE => 0;

my $SERVER_ROOT = 'http://dev8.socialtext.net';
my $REFRESH = 60;       # integer seconds; widget refresh interval
my $SIGNAL_EVERY = 5.0; # fractional seconds: per-user signal interval
my $SIGNAL_CHANCE = 0.1; # probability of sending a signal instead of a full wait
my $USER_ITERATIONS = 10;
my $USER_COUNT = 250;
my $USER_FMT = 'user-%d-27810@ken.socialtext.net';
our $TICKER_EVERY = 5;

#
# End configuration
#


my $UNPARSEABLE_CRUFT = "throw 1; < don't be evil' >";
my $proxy = "$SERVER_ROOT/nlw/json-proxy";
$AnyEvent::HTTP::MAX_PER_HOST = $AnyEvent::HTTP::MAX_PERSISTENT_PER_HOST = 9999;

sub show (@);
sub diag (@);

my $all_done = AE::cv;
my %phase_state = ();
our $phase_display = sub {show "nothing to report"};
our $script_start = AnyEvent->time;
my $ticker = AE::timer $TICKER_EVERY,$TICKER_EVERY, unblock_sub {
    show "-" x 30,(AnyEvent->now - $script_start),$AnyEvent::HTTP::ACTIVE;
    $phase_display->();
#     Coro::Debug::command('ps');
};

my %users;
for my $n (1..$USER_COUNT) {
    my $user = sprintf $USER_FMT, $n;
    $users{$user} = 'password';
}
my @user_keys = keys %users;
my %user_state;

sub ignore {}
sub show (@) {
    my $msg = join('',@_).$/;
    aio_write *STDOUT, undef, length($msg), $msg, 0, \&ignore;
    return;
}

sub diag (@) {
    return unless TRACE; # although it's good to say "diag ... if TRACE" for speed
    my $msg = join(' ',@_).$/;
    aio_write *STDERR, undef, length($msg), $msg, 0, \&ignore;
    return;
}

sub run_for_user ($$&) {
    my $user = shift;
    my $desc = shift;
    my $code = shift;

    async {
        $Coro::current->{desc} = $desc;
        $code->($user);
    };
}

sub log_in_users {
    my $phase = AE::cv;
    my $phase_timeout = AE::timer 60, 0, sub {
        $all_done->send;
        $phase->croak('timed-out logging-in users');
    };
    show "logging-in users...";

    my %guards; # cancelling guards
    local $phase_display = sub {
        show "logging in users, ".(scalar keys %guards)." remaining";
    };

    for my $user (keys %users) {
        $phase->begin;

        $user_state{$user} = {
            name => $user,
        };

        run_for_user $user, "log-in $user", sub {
            scope_guard { $phase->end if $phase };
            diag "+ logging in user",$user if TRACE;
            my $password = $users{$user} || 'password';
            my $post = "redirect_to=/&lite=&remember=1&".
                "username=".uri_escape_utf8($user).
                "&password=".uri_escape_utf8($password);

            my $g2 = http_post "$SERVER_ROOT/nlw/submit/login", $post,
                headers => { 
                    'Content-Type' => 'application/x-www-form-urlencoded',
                    'Content-Length' => length($post),
                },
                timeout => 10,
                Coro::rouse_cb;
            $guards{$user} = $g2;

            diag "+ waiting for user",$user if TRACE;
            my (undef, $headers) = Coro::rouse_wait;
            delete $guards{$user};

            my $c = $headers->{'set-cookie'};
            if ($c && $c =~ /(NLW-user=[^;]+)/) {
                $user_state{$user}{cookie} = $1;
                diag "++ logged-in:",$user,$user_state{$user}{cookie} if TRACE;
            }
            else {
                warn "Failed to log in $user ($headers->{Status} $headers->{Reason})\n";
                $phase->croak('failed to log in '.$user);
            }
        };
    }
    $phase->recv;
    show "done logging in";
}

my $signal_number = 0;

sub send_proxy_req ($$$$$$) {
    my $user = shift;
    my $proxy_method = shift; # "outer" method: client -> apache2 -> proxy HTTP method
    my $method = shift; # "inner" method: proxy -> apache-perl/internet HTTP method
    my $uri = shift;
    my $body_ref = shift;
    my $result_cb = shift;

    my $req_url = $SERVER_ROOT.$uri;
    my $payload = "url=".uri_escape_utf8($req_url).
        '&httpMethod='.$method.'&contentType=JSON&numEntries=99'.
        '&getSummaries=false&gadget=local%3Awidgets%3Awhoknows'.
        '&authz=&st=&signOwner=true&signViewer=true';

    my $url = $proxy;

    my %request_opts = (
        recurse => 0,
        timeout => 0,
        headers => {
            'Cookie' => $user_state{$user}{cookie},
            'Accept' => 'application/json; charset=UTF-8',
        },
    );

    if ($proxy_method ne 'GET') {
        $payload .= '&refresh=0';
        $payload .= "&postBody=".uri_escape_utf8($$body_ref);
        $request_opts{body} = $payload;
        $request_opts{headers}{'Content-Type'} =
            'text/x-www-form-urlencoded; charset=UTF-8';
        my $len = do { use bytes; length($request_opts{body}) };
        $request_opts{headers}{'Content-Length'} = $len;
    }
    else {
        $payload .= '&refresh='.$REFRESH;
        $url .= "?$payload";
    }
    undef $payload;

    my $start_t = AnyEvent->time;
    my $when_get_is_done = sub {
        my ($body, $headers) = @_;

        my $delta_t = AnyEvent->time - $start_t;
        $phase_state{r_time_sum} += $delta_t;
        $phase_state{r_num} ++;

        my $g = guard { $result_cb->(undef) };
        diag "++ got a result from proxy for",$user,'status:',$headers->{Status},"uri:",$uri if TRACE;
        delete $phase_state{in_progress}{$user}{$url};

        if (!$headers || !$headers->{Status} || $headers->{Status} != 200) {
            $phase_state{failed}++;
            $phase_state{timeout}++ if $headers->{Reason} =~ /time/i;
            undef $body;
        }
        return unless $body;
        $g->cancel;
        $phase_state{req_success}++;
        $result_cb->([$body,$headers,$uri]);
    };

    eval { 

        my $timeout = AE::timer $REFRESH,0, sub {
            $when_get_is_done->(undef,{Status=>599,Reason=>'timeout'});
        };

        my $fg = http_request $proxy_method, $url,
            %request_opts,
            $when_get_is_done;

        diag "++ sent $proxy_method to proxy for $user: $uri";

        # hold on to the guards:
        $phase_state{in_progress}{$user}{$url} = [$fg,$timeout];
    };
    if ($@) {
        $phase_state{failed}++;
        $result_cb->(undef);
    }
    return;
}

sub parse_single_proxy_result {
    my $body = shift;
    my $data;
    eval {
        $body =~ s/^\Q$UNPARSEABLE_CRUFT\E//;
        my $wrapper = decode_json($body);
        my ($first_val) = (values %$wrapper);
        die "req failed" if $first_val->{rc} ne '200';
        my $data = decode_json($first_val->{body});
    };
    $phase_state{parse_error}++ if $@;
    return $data || [];
}

sub activities_widget_simulator {
    my $user = shift;
    my $last_event = '';
    my $last_signal = '';
    my $signal_ids = [];

    my $force_next_events_get;
    my $num_visible = 10;
    $phase_state{plan}{$user} = $USER_ITERATIONS * 2; # two uris per iteration
    $phase_state{in_progress}{$user} = {};

    Coro::AnyEvent::sleep(rand(1) * $REFRESH / 2.0); # fuzz the start time
    diag "+ phase starting for",$user if TRACE;

    for (1..$USER_ITERATIONS) {
        my $fetches = AE::cv;

        # Request all events, which includes signals
        my $events_uri = '/data/events?'.
            'activity=all-combined;with_my_signals=1;limit='.($num_visible+1);
        $events_uri .= ";after=$last_event" if $last_event;

        $fetches->begin;
        my $events_result;
        $phase_state{plan}{$user}--;
        send_proxy_req($user, ($force_next_events_get ? 'POST' : 'GET'), 
            'GET' => $events_uri, undef, sub {
                diag "++ events result for",$user if TRACE;
                $events_result = shift;
                $fetches->end;
            });
        undef $force_next_events_get;

        # Probe for deleted signals.
        # If none are visible yet, call 
        if (@$signal_ids) {
            my $vis_count = scalar @$signal_ids;
            $vis_count = $num_visible if $vis_count > $num_visible;
            # copy, otherwise memory leaks.
            # Also, (0 .. -1) is an empty list.
            $signal_ids = [
                @$signal_ids[0 .. $vis_count-1]
            ];
        }

        my $signals_uri;
        if (!@$signal_ids) {
            $signals_uri = '/data/signals?limit='.$num_visible;
        }
        else {
            $signals_uri = '/data/signals/'.
                join(',',@$signal_ids).
                '/!visible';
        }

        $fetches->begin;
        my $signals_result;
        $phase_state{plan}{$user}--;
        send_proxy_req($user, 'GET',
            'GET' => $signals_uri, undef, sub {
                diag "++ signals result for",$user if TRACE;
                $signals_result = shift;
                $fetches->end;
            });

        $fetches->recv; # wait for both requests to return

        if ($events_result) {
            diag "++ events result ok for",$user if TRACE;
            my ($body, $headers, $uri) = @$events_result;
            $body = parse_single_proxy_result($body);
            $last_event = $body->[0]{at} if $body->[0];

            # Put signal IDs onto the front of the list
            unshift @$signal_ids,
                map { $_->{signal_id} }
                grep { $_->{event_class} eq 'signal' }
                @$body;
        }

        if ($signals_result) {
            diag "++ signals result ok for",$user if TRACE;
            my ($body, $headers, $uri) = @$signals_result;
            $body = parse_single_proxy_result($body);
            if ($uri =~ m#visible#) {
                my @invisible_ids = map { $_->{signal_id} } @$body;
                for my $id (@invisible_ids) {
                    @$signal_ids = grep { $_ ne $id } @$signal_ids;
                }
            }
            else {
                $signal_ids = [
                    map { $_->{signal_id} } @$body
                ];
            }
        }

        diag "+ polling done for",$user if TRACE;

        last unless $phase_state{plan}{$user} > 0;
        if (rand(1) <= $SIGNAL_CHANCE) {
            my $signum = ++$signal_number;
            diag "+ going to post signal",$signum if TRACE;

            Coro::AnyEvent::sleep(rand($REFRESH)/2);
            $force_next_events_get = 1;

            diag "+ posting signal",$signum if TRACE;
            my $sig = '{"signal":"hey guys, signal '.$signum.' here"}';

            my $cb = Coro::rouse_cb;
            send_proxy_req($user, POST => POST => '/data/signals', \$sig, $cb);
            my $result = Coro::rouse_wait($cb);

            if ($result) {
                my (undef,$headers,undef) = @$result;
                diag "+ posted signal",$signum," status ",$headers->{Status} if TRACE;
                $phase_state{posted_signals}++;
            }
            else {
                diag "+ failed signal",$signum if TRACE;
                $phase_state{failed_signals}++;
            }
        }
        else {
            Coro::AnyEvent::sleep($REFRESH);
        }

        diag "+ iteration done for",$user if TRACE;
    }

    diag "+ phase done for",$user if TRACE;
    delete $phase_state{in_progress}{$user};
    $phase_state{plan}{$user} = 0;
}

sub simple_dashboard {
    my $phase = AE::cv;
    %phase_state = (
        failed => 0,
        timeout => 0,
        parse_error => 0,
        posted_signals => 0,
        failed_signals => 0,
        req_success => 0,
        r_time_sum => 0.0,
        r_num => 0,
        total_r_time_sum => 0.0,
        total_r_num => 0,
        plan => {},
        in_progress => {},
    );
    scope_guard { %phase_state = () };

    local $phase_display = sub {
        my $total_u = scalar keys %{$phase_state{in_progress}};
        my $outstanding = sum values %{$phase_state{plan}};

        $phase_state{total_r_time_sum} += $phase_state{r_time_sum};
        $phase_state{total_r_num} += $phase_state{r_num};
        my $total_r = $phase_state{total_r_num} || 1;
        my $total_r_time = ($phase_state{total_r_time_sum} / $total_r);
        my $total_r_rate = ($total_r / (AnyEvent->time - $script_start));

        my $immed_r = $phase_state{r_num} || 1;
        my $immed_r_time = ($phase_state{r_time_sum} / $immed_r);
        my $immed_r_rate = $phase_state{r_num} / $TICKER_EVERY;
        $phase_state{r_time_sum} = 0.0;
        $phase_state{r_num} = 0;

        show
        "Simple dashboard phase\n".
        "Average Response Time: ".
            sprintf("%0.3f",$immed_r_time)."s/r immed, ".
            sprintf("%0.3f",$total_r_time)."s/r overall\n".
        "Average Request Rate: ".
            sprintf("%0.3f",$immed_r_rate)."r/s immed, ".
            sprintf("%0.3f",$total_r_rate)."r/s overall\n".
        "Remaining: $total_u users, $outstanding requests.\n".
        "Success: $phase_state{posted_signals} signals, $phase_state{req_success} requests.\n".
        "Errors: $phase_state{failed} failed, $phase_state{timeout} timeouts, $phase_state{parse_error} parse errors, ".
            "$phase_state{failed_signals} failed signals"
        ;
    };

    my @coros; # for keeping coro guards
    scope_guard { $_->throw("cancel") for @coros };

    for my $user (keys %users) {
        $phase->begin;
        push @coros, run_for_user($user, "activities $user", sub {
            scope_guard { $phase->end if $phase };
            activities_widget_simulator($user);
        });
    }

    $phase->recv;
#     diag "++ phase all done\n";
    $phase_display->();
}

async { $Coro::current->{desc} = 'main schedule';
    eval { 
        log_in_users();
        simple_dashboard();
    };
    if ($@) {
        warn "death! $@\n";
    }
    $all_done->send;
};

my $main_start = AnyEvent->time;
print "main: waiting...\n";
$all_done->recv;
my $main_elapsed = AnyEvent->time - $main_start;
print "done in $main_elapsed seconds\n";
