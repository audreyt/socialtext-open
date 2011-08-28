#!/usr/bin/env perl
# @COPYRIGHT@
use warnings FATAL => 'all';
use strict;

=head1 NAME

cranky.pl - an ornery daemon

=head1 SYNOPSIS

  cranky.pl
  cranky.pl --ram 512 --fds 256 --after 5 --serv http --http ok

Options:
  --help    brief help message
  --man     full documentation
  --ram     consume this much RAM (in MiB)
  --fds     open at least this many file descriptors
  --after   exit abruptly after this many seconds (Default: 60 seconds)
  --serv    Run the specified dummy server
  --http    Send this HTTP response ('ok' = 200, everything else = 403).

=cut

use FindBin;
use lib "$FindBin::Bin/../lib";
use Coro;
use AnyEvent;
use Coro::AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Guard;
use Getopt::Long;
use Pod::Usage;

my $man = 0;
my $help = 0;
my $ram = 0; # in MiB
my $fds = 0; # in MiB
my $after = 60;
my $serv = 'stall';
my $port = ($> + 26000);
my $http_opts = '';

GetOptions(
    'help|?' => \$help,
    man      => \$man,
    'ram=i'  => \$ram,
    'fds=i'  => \$fds,
    'after=i' => \$after,
    'serv=s'  => \$serv,
    'port=i' => \$port,
    'http=s' => \$http_opts,
)
or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

use constant MiB => 1024 * 1024;

AnyEvent::detect;

our $death_clock;
if ($after) {
    $death_clock = AE::timer $after, 0, sub { print "death!\n"; exit 9; };
}

our $server;
if ($serv eq 'stall') {
    $server = tcp_server '127.0.0.1', $port, sub {
        print "$0: stall connection\n";
        my $fh = shift;
        async {
            scope_guard { close $fh };
            Coro::AnyEvent::sleep 15;
        };
    };
    print "$0: set up sink $server\n";
}
elsif ($serv eq 'http') {
    require Socialtext::Async::HTTPD;
    $server = Socialtext::Async::HTTPD::http_server(
        '127.0.0.1', $port, sub {
            eval {handle_http(@_)};
            warn "$0: http error $@" if $@;
        });
}
else {
    print "$0: no server\n";
}

sub handle_http {
    my ($handle, $env, $body, $fatal, $msg) = @_;
    my $status = ($http_opts =~ /\bok\b?/) ? '200 OK' : '403 Go Away';
    if ($handle && $env) {
        my $go_away = <<"EOM";
HTTP/1.0 $status
Content-Type: text/plain
Connection: close

Go away!
EOM
        $go_away =~ s/\n/\015\012/gsm;
        $handle->push_write($go_away);
        # important to make a closure here:
        $handle->on_drain(sub { shutdown $handle->fh, 1; $handle->destroy });
    }
    else {
        die "$msg ($fatal)";
    }
}

our @sigs;

# For simulating a graceful shutdown:
push @sigs, AE::signal 'HUP' => unblock_sub {
    print "$0: Got HUP\n";
    undef $server if $server;
    Coro::AnyEvent::sleep 2;
    print "$0: HUP done\n";
    exit 1;
};

push @sigs, AE::signal 'USR1' => sub { print "$0: Got USR1\n" };
push @sigs, AE::signal 'USR2' => sub { print "$0: Got USR2\n" };
push @sigs, AE::signal 'TERM' => sub { print "$0: Got TERM\n"; exit 3; };
push @sigs, AE::signal 'INT'  => sub { print "$0: Got INT\n";  exit 4; };

sub mem_hog {
    my $hog = 'z' x ($ram * MiB);
    AE::cv->recv; # wait forever
}

sub fd_hog {
    my @fh;
    for (1 .. $fds) {
        open my $fh, '>', '/dev/null';
        push @fh, $fh;
    }
    AE::cv->recv; # wait forever
}

async \&mem_hog if $ram;
async \&fd_hog if $fds;

print "$0: waiting\n";
AE::cv->recv; # wait forever

__END__


=head1 OPTIONS

=over 8

=item B<--ram> NNN

Consume this much RAM in MiB (C<2**20>).  Allocates a single scalar with this
many characters.

Default: 0

=item B<--fds> NNN

Open C</dev/null> this many times.

Default: 0

=item B<--after> NNN

Exit with code "9" after this many seconds.  Use 0 to disable.

Default: 60

=item B<--serv> kind

Turn on a socket server.  Listens on port C<< $> + 6000 >> (your user
ID plus 6000).

Using C<--serv http> will receive HTTP requests and send an HTTP response.
See C<--http>.

Using C<--serv stall> will set up a "stalling" TCP server.  No response is
given and requests are ignored.

Using C<--serv none> will disable this feature.

Default: stall

=item B<--http> ok

Controls the HTTP response.  An argument of "ok" will cause a "200 OK"
response to be sent.  By default a "403 Go Away" response will be sent.

Default: 403

=item B<--help>

Print a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

The default invocation of cranky.pl will exit after 5 seconds with code 9.
During this time, it will listen on a TCP port of your user ID plus 6000.  The
"stall" server will be used; any data written is ignored.

=head2 Signals

All signals not explicitly ignored will cause the daemon to exit.

=over 8

=item SIGUSR1 SIGUSR2

Ignored.

=item SIGTERM

Daemon exits with code 3.

=item SIGINT

Daemon exits with code 4.

=item SIGHUP

Closes the server socket (if started), waits 2 seconds, then exits with code 1.

=back

=cut
