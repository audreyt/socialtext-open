package Socialtext::WebDaemon::Util;
# @COPYRIGHT@
use warnings;
use strict;
use base 'Exporter';
use Try::Tiny;
use POSIX 'strftime';
use Coro qw/async async_pool unblock_sub/;
use Guard qw/guard scope_guard/;
use Socialtext::SQL ();
use Socialtext::Log qw/st_log st_timed_log/;
use Socialtext::JSON;
use Socialtext::Timer qw/time_scope/;
use Socialtext::IntSet;
use Socialtext::AppConfig;
use Scalar::Util qw/blessed weaken/;
use Socialtext::TimestampedWarnings;

our $VERSION = 1.0;

my $CRLF = "\015\012";
our @EXPORT = qw(
    trace exception_wrapper DAEMON NAME
    ignored

    try catch
    async async_pool unblock_sub
    guard scope_guard
    blessed weaken

    st_log st_timed_log
    decode_json encode_json json_true json_false json_bool
    time_scope
    $CRLF
);

 # don't do a HARNESS_ACTIVE check; debug output can interfere with some TAP
 # parsers
our $DEBUG = $ENV{ST_DEBUG_ASYNC};

sub ignored {}

# Trace left intentionally disabled. It is only for debugging and is enabled
# using the env-vars above.
sub trace (@) { }
sub _setup_trace {
    no warnings qw/redefine once/;
    no strict 'refs';
    *{'trace'} = sub (@) {
        my $msg = join(' ', "($$)", $Socialtext::WebDaemon::NAME, @_);
        chomp $msg;
        $msg .= "\n";
        warn $msg; # will get a timestamp from TimestampedWarnings
    };
}
_setup_trace() if $DEBUG;

{
    no warnings 'once';
    sub DAEMON { $Socialtext::WebDaemon::SINGLETON }
    sub NAME   { $Socialtext::WebDaemon::NAME }
}

sub exception_wrapper(&$) {
    my $code = shift;
    my $exception_prefix = shift;

    return sub {
        my @args = @_;
        # unblock since these are intended to be used as event callbacks.
        my $c; $c = async {
            $c->{desc} = "wrapper for '$exception_prefix'";
            scope_guard { undef $c; };
            # db might have restarted while waiting for this callback to fire.
            Socialtext::SQL::invalidate_dbh();
            try { $code->(@args) }
            catch {
                my $e = "$$ ${exception_prefix}: $_";
                if ($DEBUG) {
                    DAEMON()->cv->croak($e);
                }
                else {
                    trace $e;
                }
            };
            return;
        };
        Coro::cede;
    };
}

1;
__END__

=head1 NAME

Socialtext::WebDaemon::Util - pushd utility code

=head1 SYNOPSIS

    use Socialtext::WebDaemon::Util;

    my $cb = exception_wrapper { $self->deadly } 'Exception prefix';
    my $timer = AE::timer 5, 5, $cb; # or whatever wants a callback
    trace "some message to STDERR";
    HANDLER()->cv->croak("WTH?");

=head1 DESCRIPTION

C<trace> writes a message to STDERR prefixed with a timestamp and pid.

C<exception_wrapper> will cause the web daemon to exit when running under
HARNESS_ACTIVE, PUSHD_DEBUG or ST_DEBUG_ASYNC.  The sub returned is equivalent
to C<unblock_sub> (see L<Coro>).

C<DAEMON> is a convenience function for the current active web daemon.

C<NAME> is a convenience function for the current active web daemon's short
name (useful for log messages and the like).

For convenience, Also exports C<weaken> from L<Scalar::Util>; C<try> and
C<catch> from L<Try::Tiny>; C<async>, C<async_pool> and C<unblock_sub> from
L<Coro>; and C<guard> and C<scope_guard> from L<Guard>.

For even more convenience, also exports these common socialtext functions:

    st_log st_timed_log
    decode_json encode_json
    time_scope

=cut
