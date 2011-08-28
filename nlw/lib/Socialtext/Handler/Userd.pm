package Socialtext::Handler::Userd;
# @COPYRIGHT@
use Moose;
BEGIN { extends 'Socialtext::WebDaemon'; }
use Socialtext::WebDaemon::Util; # auto-exports
use Socialtext::Async::Wrapper; # auto-exports
use Socialtext::CredentialsExtractor;

use namespace::clean -except => 'meta';

our $VERSION = 1.1;

has '+port' => (default => 8084);

has 'extract_q' => (
    is => 'rw', isa => 'Socialtext::Async::WorkQueue',
    lazy_build => 1
);

use constant ProcName => 'st-userd';
use constant Name => 'st-userd';

sub Getopts { }

sub ConfigForDevEnv {
    my ($class, $args) = @_;
}

sub handle_request {
    my ($self,$req) = @_;

    my $path = $req->env->{PATH_INFO};
    if ($path eq '/ping') {
        $self->stats->{"pings"}++;
        $req->simple_response(
            "200 Pong",
            qq({"ping":"ok", "service":"st-userd"}),
            'JSON'
        );
    }
    elsif ($path eq '/stuserd' && $req->env->{REQUEST_METHOD} eq 'POST') {
        $self->stats->{"client conns"}++;
        my $params = decode_json(${$req->body});
        $req->log_successes(0) unless $ENV{ST_DEBUG_ASYNC}; # don't spew
        my $now = AE::time;
        $self->extract_q->enqueue( [$params, $req, $now] );
    }
    else {
        $self->stats->{"bad requests"}++;
        $req->simple_response(
            "400 Bad Request",
            qq(You send a request this server didn't understand),
        );
    }

    return;
}

sub _build_extract_q {
    my $self = shift;
    weaken $self;
    my $cb = exception_wrapper {
        my ($params,$req,$queued_at) = @_;
        return unless $self;
        Socialtext::Timer->Add('queued_for',AE::time-$queued_at);
        $self->extract_creds($params,$req);
    } 'extract queue error';
    return Socialtext::Async::WorkQueue->new(
        name => 'extract',
        prio => Coro::PRIO_LOW(),
        cb => $cb,
    );
}

sub extract_creds {
    my ($self, $params, $req) = @_;
    my $result;
    try {
        my $t = time_scope 'work_extract';
        $result = worker_extract_creds($params);
        $self->stats->{"extracted"}++;
    }
    catch {
        my $e = $_;
        trace $e;
        st_log()->error('when trying to extract creds: '.$e);
        $self->stats->{"extract failure"}++;
        $result = {
            code => 500,
            body => {
                'error' => 'Could not extract creds',
                'details' => $e,
            },
        };
    };

    my $json = encode_json($result->{body});
    $req->simple_response($result->{code}, \$json, 'JSON');
}

worker_function worker_extract_creds => sub {
    my $params = shift;
    my $creds;
    my $code = 200;
    try {
        $creds = Socialtext::CredentialsExtractor->ExtractCredentials($params)
    }
    catch {
        my $e = $_;
        st_log()->error('when worker trying to extract creds: '.$e);
        return {
            code => 500,
            body => { error => $e },
        };
    };
    return { code => $code, body => $creds };
};

1;

=head1 NAME

Socialtext::Handler::Userd - Credentials Extraction handler

=head1 SYNOPSIS

  # see st-userd

=head1 DESCRIPTION

Credentials Extraction handler, as C<st-userd> daemon

=cut
