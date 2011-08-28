package Socialtext::Async;
# @COPYRIGHT@
use warnings;
use strict;

use EV (); # so that AnyEvent will use this engine
use AnyEvent ();
use Async::Interrupt (); # for handling signals "safer"
use Coro (); # needed for Socialtext::Async::Syslog
use Coro::State (); # needed for spin_down_coros
use Coro::AnyEvent (); # make Coro use AnyEvent/EV for timers/io/etc.

sub spin_down_coros {
    #require Coro::Debug;

    # Avoid core dumps by waiting for certain coros to finish during global
    # destruction.
    SPIN_DOWN: while (1) {
        #print STDERR "spindown\n";
        #Coro::Debug::command('ps w');
        for my $coro (Coro::State::list()) {
            next if $coro == $Coro::current;
            if ($coro->is_ready) {
                # Some coro is about to be woken up.  Give it a timeslice to
                # finish up.
                next SPIN_DOWN;
            }

            my $desc = $coro->{desc} || '';
            if ($desc =~ /^\[async.pool\]$/) {
                #print STDERR "\tdesc: $desc\n";
                # interrupting an [async_pool] thread that's not idle (desc:
                # "[async pool idle]") causes core dumps deep in Coro.  Wait
                # for them to become idle.
                next SPIN_DOWN;
            }
        }

        last;
    }
    continue {
        #print STDERR "spindown wait\n";
        Coro::AnyEvent::sleep 0.125;
    }
    #print STDERR "spindown done\n";
    #Coro::Debug::command('ps w');
}

END { spin_down_coros() }

1;
__END__

=head1 NAME

Socialtext::Async - async programming pragma.

=head1 SYNOPSIS

    use Socialtext::Async;

=head1 DESCRIPTION

Use this module to load up a number of commonly-used 3rd-party "async"
libraries: C<EV>, C<Coro>, C<AnyEvent>, C<Async::Interrupt>, and C<IO::AIO>.

Using this module will also make calls to C<st_log> asynchronous via
C<Socialtext::Async::Syslog> (which is why we require C<Coro> to be loaded).
You must still C<< use Socialtext::Log qw/st_log/; >> to import the funciton,
however.

In the future, this module may patch other "blocking" routines to be more
async-friendly (e.g. database access).

During global destruction (Perl's) this module will wait for any outstanding
"[async_pool]" or ready coro-threads to finish, since occasionally cancelling
these will cause a core-dump.

Currently there are no callable functions/methods in this class.

=cut
