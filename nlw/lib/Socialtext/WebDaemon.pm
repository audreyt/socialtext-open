package Socialtext::WebDaemon;
# @COPYRIGHT@
use Moose;
use MooseX::AttributeHelpers;
use MooseX::StrictConstructor;

use FindBin;
use Getopt::Long;
use Carp qw/carp croak cluck/;

use Socialtext::TimestampedWarnings;
use Socialtext::AppConfig;
use Socialtext::Paths;
BEGIN {
    # unbuffer stderr/stdout
    select STDERR; $|=1;
    select STDOUT; $|=1;
    if ($ENV{ST_LOG_NAME} && !$ENV{HARNESS_ACTIVE}) {
        my $path = '/var/log';
        $path = Socialtext::Paths->log_directory() if $0 !~ m{/usr/s?bin};
        eval "use Socialtext::System::TraceTo '$path/$ENV{ST_LOG_NAME}.log'";
    }

    if (Socialtext::AppConfig->is_dev_env && !$ENV{HARNESS_ACTIVE}) {
        # set this manually in your test, it interferes with TAP parsers:
        $ENV{ST_DEBUG_ASYNC} = 1; # See Socialtext::WebDaemon::Util
    }
}

use Socialtext::HTTP::Ports;

use EV;
use Feersum;
use Socket qw/SOMAXCONN/;
use IO::Socket::INET;
use POSIX ();
use Socialtext::Async;
use Socialtext::Async::WorkQueue;

use Socialtext::Cache;
use Socialtext::User;
use Socialtext::User::Cache;
use Socialtext::User::Default::Factory;

use Socialtext::WebDaemon::Util; # auto-exports some stuff;
use Socialtext::WebDaemon::Request;

use namespace::clean -except => 'meta';

BEGIN {
    # {bz: 4151} - load LDAP code in the parent if that factory is enabled.
    if (Socialtext::AppConfig->user_factories  =~ /LDAP/ ||
        Socialtext::AppConfig->group_factories =~ /LDAP/)
    {
        require Socialtext::User::LDAP::Factory;
        require Socialtext::Group::LDAP::Factory;
    }
}

our $SINGLETON;
our $NAME; # don't set this, define a `name` constant in your module
our $PROC_NAME;

has 'host' => (is => 'rw', isa => 'Str', default => '127.0.0.1');
has 'port' => (is => 'rw', isa => 'Int');

has 'is_running' => (
    is => 'rw', isa => 'Bool',
    default => 1, writer => '_running'
);

has 'cv' => (
    is => 'ro', isa => 'AnyEvent::CondVar',
    default => sub { AE::cv() }
);

has 'stats' => (is => 'rw', isa => 'HashRef', default => sub {{}});

has 'shutdown_delay'     => (is => 'rw', isa => 'Num', default => 15);
has 'stats_period'       => (is => 'rw', isa => 'Num', default => 900);
has 'worker_ping_period' => (is => 'rw', isa => 'Num', default => 60);
# Feersum sets a default of 5 seconds. http_read_timeout is a timeout between
# read() system calls.
has 'http_read_timeout'  => (is => 'rw', isa => 'Num', default => 30);

has 'guards' => (
    is => 'ro', isa => 'HashRef',
    metaclass => 'Collection::Hash',
    provides => {
        delete => 'disable_guard',
    },
    default => sub {{}},
    clearer => '_destroy_guards'
);

use constant RequestClass => 'Socialtext::WebDaemon::Request';
use constant NeedsWorker => 1;

# called by startup scripts
sub Configure {
    shift; # __PACKAGE__
    my $class = shift;
    my $default_port = shift;

    eval "require $class";
    croak $@ if $@;

    {
        no strict 'refs';
        croak "class '$class' needs a Name constant"
            unless *{$class."::Name"};
        croak "class '$class' needs a ProcName constant"
            unless *{$class."::ProcName"};
    }
    $NAME = $class->Name;
    $PROC_NAME = $class->ProcName;

    st_log->info("$PROC_NAME is starting up...");

    my %opts;
    GetOptions(
        \%opts,
        $class->Getopts(),
        'shutdown-delay=i',
        'http-read-timeout=i',
        'port=i',
    );

    my %args = map { (my $k = $_) =~ tr/-/_/; $k => $opts{$_} } keys %opts;
    $args{port} ||= $default_port;
    unless (Socialtext::AppConfig->is_appliance) {
        $args{shutdown_delay} ||= 5.0;
        # change args for running under dev-env
        $class->ConfigForDevEnv(\%args);
    }

    $0 = $PROC_NAME;
    $SINGLETON = $class->new(\%args);

    if ($class->NeedsWorker) {
        require Socialtext::Async::Wrapper;
        Socialtext::Async::Wrapper->RegisterCoros();
        Socialtext::Async::Wrapper->RegisterAtFork(sub{$SINGLETON->_at_fork});
    }
    return;
}

sub Run {
    my ($class, @args) = @_;

    POSIX::setsid();
    try { $class->Configure(@args) }
    catch {
        croak "could not configure $class: $_";
    };

    try { $SINGLETON->_startup }
    catch {
        my $msg = "$PROC_NAME stopping, startup error: $_";
        st_log->error($msg);
        croak $msg;
    };

    my $main_e;
    try { $SINGLETON->cv->recv } catch { $main_e = $_ };

    $SINGLETON->_running(0);
    try { $SINGLETON->_cleanup() }
    catch { cluck "during $NAME cleanup: $_" };

    if ($main_e) {
        my $msg = "$PROC_NAME stopping, runtime error: $main_e";
        st_log->error($msg);
        cluck $msg;
        kill -9 => 0; # Terminate all workers in our process group - see "perldoc -f kill"
    }

    trace "done";
    st_log->info("$PROC_NAME done");

    kill -9 => 0; # Terminate all workers in the our process group - see "perldoc -f kill"
    #exit 0; # not reached
}

sub startup { } # override in subclass
sub _startup {
    my $self = shift;
    weaken $self;

    $self->cv->begin; # match in _shutdown()

    st_log()->info("$PROC_NAME starting on ".$self->host." port ".$self->port);
    trace "starting on ".$self->host." port ".$self->port.
        " Feersum $Feersum::VERSION";
    $self->listen();

    $self->guards->{stats_ticker} =
        AE::timer $self->stats_period, $self->stats_period,
        exception_wrapper { $self->stats_ticker() } "Ticker error";

    my $shutdown_handler = exception_wrapper {
        $self->_shutdown()
    } "shutdown signal error";

    for my $sig (qw(HUP TERM INT QUIT)) {
        $self->guards->{"sig_$sig"} = AE::signal $sig, $shutdown_handler;
    }

    if ($self->NeedsWorker) {
        require Socialtext::Async::Wrapper;
        Socialtext::Async::Wrapper::worker_make_immutable($NAME);
        $self->guards->{worker_pinger} =
            AE::timer $self->worker_ping_period, $self->worker_ping_period,
            exception_wrapper {
                try { 
                    Socialtext::Async::Wrapper::ping_worker($NAME);
                    trace "Worker is OK!";
                }
                catch {
                    trace "Worker is bad! $_";
                };
            } 'Worker Pinger error';
    }

    $self->startup();
}

sub cleanup {} # override in subclass
sub _cleanup {
    my $self = shift;
    $self->_destroy_guards;
    # do this after destroying guards so we don't conflict with EV
    $SIG{$_} = 'IGNORE' for qw(TERM INT QUIT);
    $self->cleanup();
}

sub at_fork {} # override in subclass
sub _at_fork {
    my $self = shift;
    $self->_destroy_guards;
    $self->_running(0); # don't run in forked kid.
    Feersum->endjinn->unlisten(); # don't service requests in the kid
    $self->at_fork();
}

sub shutdown {} # override in subclass
sub _shutdown {
    my $self = shift;
    return if $self->guards->{shutdown_timer};
    $self->_running(0);

    trace("shutting down...");
    st_log()->info("$PROC_NAME shutting down");

    Feersum->endjinn->graceful_shutdown(sub {
        $self->cv->end; # match in run()
    });

    $self->shutdown();

    $self->guards->{shutdown_timer} = AE::timer $self->shutdown_delay,0,
        exception_wrapper {
            $self->cv->croak("timeout during shutdown");
        } "Shutdown timer error";
}

sub listen {
    my $self = shift;
    my $socket = IO::Socket::INET->new(
        LocalAddr => $self->host.':'.$self->port,
        ReuseAddr => 1,
        Proto => 'tcp',
        Listen => Socket::SOMAXCONN(),
        Blocking => 0,
    );
    die "can't create socket: $!" unless $socket;

    my $e = Feersum->endjinn;
    $e->read_timeout($self->http_read_timeout);
    $e->request_handler(sub { $self->_wrap_request(@_) });
    $e->use_socket($socket);
}

sub stats_ticker {
    my $self = shift;

    my $stats = $self->stats;

    my $rpt = Socialtext::Timer->ExtendedReport();
    delete $rpt->{overall};
    my $active = $stats->{"current connections"};

    Socialtext::Timer->Reset();

    my $ucname = uc($NAME);
    st_log->info("$ucname,STATUS,ACTOR_ID:0,".encode_json($stats));
    st_timed_log('info',$ucname,'TIMERS',0,{},undef,$rpt);

    %$stats = ("current connections" => $active);
}

sub _wrap_request {
    my ($self, $r) = @_;

    my $env = $r->env;
    my $body_ref;
    if (my $cl = $env->{CONTENT_LENGTH}) {
        my $fh = delete $env->{'psgi.input'};
        my $body = '';
        $fh->read($body,$cl);
        $fh->close();
        $body_ref = \$body;
    }

    my $req = $self->RequestClass->new(
        _r => $r, env => $env, body => $body_ref
    );

    try {
        $self->handle_request($req);
    }
    catch {
        my $e = 'handle_request: '.$_;
        st_log->error($e);
        trace($e);
        $req->simple_response('500 Server Error',
            "An error occurred when processing the $NAME request.")
            unless ($req->responding or !$req->alive);
    };
    return;
}

sub handle_request {
    my ($self,$req) = @_;
    die "WebDaemon subclass didn't override handle_request";
}

1;
__END__

=head1 NAME

Socialtext::WebDaemon - abstract base-class.

=head1 SYNOPSIS

    package 'My::Daemon';
    use Moose;
    BEGIN { extends 'Socialtext::WebDaemon' }
    use Socialtext::WebDaemon::Util;

    use constant Name => 'myd';
    use constant ProcName => 'st-myd';
    use constant 'RequestClass' => 'Socialtext::My::Request';

=head1 DESCRIPTION

Abstract base-class and factory for a number of socialtext "web daemons".

The RequestClass should sub-class L<Socialtext::WebDaemon::Request>.

=cut
