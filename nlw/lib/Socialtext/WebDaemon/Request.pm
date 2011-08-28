package Socialtext::WebDaemon::Request;
# @COPYRIGHT@
use Moose;
use MooseX::StrictConstructor;
use Encode qw/is_utf8 encode_utf8/;
use Socialtext::Async::HTTPD qw/serialize_response/;
use Socialtext::WebDaemon::Util; # auto-exports
use namespace::clean -except => 'meta';

has 'env' => (is => 'ro', isa => 'HashRef', required => 1);
has 'query' => (is => 'rw', isa => 'HashRef', lazy_build => 1);
has 'body' => (is => 'ro', isa => 'Maybe[ScalarRef]', required => 1);
has 'for_user_id' => (is => 'rw', isa => 'Int', default => 0,
    trigger => \&update_ident);

has 'log_params' => (is => 'rw', isa => 'HashRef', default => sub {{}});
has 'started_at' => (is => 'rw', isa => 'Num');
has '_pid' => (is => 'rw', isa => 'Int');

has 'log_successes' => (is => 'rw', isa => 'Bool', default => 1);

has 'ident' => (
    is => 'ro', isa => 'ScalarRef',
    default => sub {my $x=''; \$x},
);
has 'responding' => (is => 'ro', isa => 'Bool', writer => '_responding');

has '_r' => (is => 'ro', isa => 'Feersum::Connection', required => 1,
    clearer => '_clear_r', predicate => 'alive');
has '_w' => (
    is => 'rw', isa => 'Feersum::Connection::Writer',
    clearer => '_clear_w',
    predicate => 'streaming',
    handles => {
        stream_write => 'write',
    },
);

sub BUILD {
    my $self = shift;
    weaken $self;

    my $ident_ref = $self->update_ident;

    DAEMON()->stats->{"current connections"}++;
    $self->_r->response_guard(guard {
        trace "=> DROP $$ident_ref\n";
        DAEMON()->stats->{"current connections"}--;
    });

    $self->started_at(AE::now);
    my $env = $self->env;
    $self->_pid($$); # for detecting forks
    trace "=> REQUEST ".$$ident_ref.": ".
        "$env->{REQUEST_METHOD} $env->{PATH_INFO} $env->{QUERY_STRING}\n";
}

sub _build_query {
    my $self = shift;
    my $qstr = $self->env->{QUERY_STRING} || '';
    my @qp = split /[;&=]/, $qstr;
    return { nowait => 0, client_id => '', @qp }
        if (@qp % 2 == 0);
    return {};
}

sub update_ident {
    my $self = shift;
    my $user_id = shift || $self->for_user_id;
    my $ident_ref = $self->ident;
    $$ident_ref = "fd=".$self->_r->fileno().', user_id='.$user_id;
    return $ident_ref;
}

sub log_start {
    my $self = shift;
    st_log->debug(join(',',
        uc(NAME()),'START_'.$self->env->{REQUEST_METHOD},
        uc($self->env->{PATH_INFO}),
        "ACTOR_ID:".$self->for_user_id,
        encode_json($self->log_params)
    ));
}

sub log_done {
    my ($self,$code) = @_;
    return if ((200 <= $code && $code <= 399) && !$self->log_successes);
    $self->log_params->{timers} = 'overall(1):'.
        sprintf('%0.3f', AE::now - $self->started_at);
    DAEMON()->stats->{"error responses"}++ if $code >= 400;
    st_log->info(join(',',
        'WEB',$self->env->{REQUEST_METHOD},
        uc($self->env->{PATH_INFO}),
        $code,
        "ACTOR_ID:".$self->for_user_id,
        encode_json($self->log_params)
    ));
}

sub simple_response {
    my ($self, $message, $content_or_ref, $ct) = @_;

    $ct ||= 'text/plain; charset=UTF-8';
    $ct = 'application/json; charset=UTF-8' if $ct eq 'JSON';
    my $ref = ref($content_or_ref) ? $content_or_ref : \$content_or_ref;
    $ref = \encode_utf8($$ref) if is_utf8($$ref);
    $self->respond($message, ['Content-Type' => $ct], $ref);
    return;
}

sub _finishing {
    my ($self, $code, $cb) = @_;

    # This is faster assuming none of these are lazy-built (but breaks
    # encapsulation):
    my $r = delete $self->{_r}; # break encapsulation for speed
    my $w = delete $self->{_w}; # break encapsulation for speed

    # replace the default guard so we can log a completion message (strong
    # reference is OK).
    $r->response_guard->cancel;
    $r->response_guard(guard {
        $self->log_done($code);
        $cb->() if $cb;
        DAEMON()->stats->{"current connections"}--;
        undef $self; # important reference closure.
    });

    return ($r,$w);
}

sub respond {
    my ($self, $message, $hdrs, $content, $cb) = @_;

    confess "attempted to respond twice to a request"
        unless ($self->alive && !$self->responding);

    no warnings 'numeric';
    my $code = 0 + $message;
    my ($r,$w) = $self->_finishing($code, $cb);

    $r->send_response($message, $hdrs, $content);
    $self->_responding(1);
    trace "<= RESPONSE ".${$self->ident}.": ".$message.$/;

    return;
}

sub stream_start {
    my ($self,$message,$headers) = @_;
    confess "can't start streaming: a response is already started"
        unless ($self->alive && !$self->responding);
    my $w = $self->_r->start_streaming($message,$headers);
    confess "couldn't start streaming" unless $w;
    $self->_w($w);
    $self->_responding(1);
    trace "<= STREAM START ".${$self->ident}.": ".$message;
}

sub trickle {
    my ($self, $every, $ignorable) = @_;
    weaken $self;
    my $w = $self->_w;
    weaken $w;
    my $ident_ref = $self->ident;
    my $t; $t = AE::timer($every, $every, sub {
        # cancel if request was finished
        return undef $t unless ($self && $w && $self->alive);
        try {
            $w->write($ignorable);
        }
        catch {
            trace "<= STREAM FAIL ".$$ident_ref." $_";
            $self->_finishing(499);
        };
    });
}

sub stream_end {
    my ($self, $cb) = @_;
    my ($r,$w) = $self->_finishing(200, $cb);
    $w->close;
    trace "<= STREAM END ".${$self->ident};
}

__PACKAGE__->meta->make_immutable;
1;
__END__

=head1 NAME

Socialtext::WebDaemon::Request - WebDaemon request object

=head1 SYNOPSIS

    my $req = Socialtext::WebDaemon::Request->new(
        env => $env, _r => $feersum_connection, body => $body
    );

To give a simple response and close the connection:

    $req->simple_response(403, 'go away'); # text/plain
    $req->simple_response(403, '{"go":"away"}', 'JSON');

To give a response with custom headers and a callback:

    $req->respond(200, ['Content-Type'=>'application/json'],
        \'{"this is":"the response body"}',
        \&optional_completion_callback);

To stream a response (works well with timers/events):

    $req->stream_start(200, ['Content-Type'=>'text/html']);
    $req->stream_write(\$header_and_start_of_body);
    $req->trickle(2.0, "<!-- ignorable content -->");
    $req->stream_end(\&optional_completion_callback);

=head1 DESCRIPTION

Abstracts the L<Feersum::Connection> object for use in WebDaemons.  The
streaming mode uses L<Feersum::Connection::Writer>.

The trickle method will send some ignorable content every so often to keep the
HTTP connection from timing out.

=cut
