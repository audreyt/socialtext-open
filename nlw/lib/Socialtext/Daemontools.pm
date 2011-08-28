package Socialtext::Daemontools;
# @COPYRIGHT@
use warnings;
use strict;
use Carp qw/confess/;

sub RunSupervised {
    my $class = shift;
    my %p = @_;
    my $port_name = $p{port_name} or confess 'port_name is required';
    my $run = $p{cb} or confess 'cb (callback) is required';
    my $log_file = $p{log_file}
        or confess 'log_file is required (relative path)';

    require Socialtext::AppConfig;
    require Socialtext::Paths;
    require Socialtext::HTTP::Ports;
    require POSIX;

    my $root_dir = Socialtext::AppConfig->data_root_dir();
    my ($uid, $gid) = (stat $root_dir)[4,5];

    $log_file = Socialtext::Paths::log_directory().'/'.$log_file;
    unless ($ENV{ST_DAEMON_DEBUG}) {
        eval "use Socialtext::System::TraceTo qw($log_file);";
    }

    my $port = Socialtext::HTTP::Ports->$port_name;

    # If we're root, switch to the www-data user.
    if ($< == 0) {
        chown $uid, $gid, $log_file;
        require POSIX;
        POSIX::setgid($gid);
        POSIX::setuid($uid);
    }

    open STDIN, '<', '/dev/null';
    POSIX::setsid();

    @_ = ($port);
    goto $run;
}

1;
__END__

=head1 NAME

Socialtext::Daemontools - tools for daemontools

=head1 SYNOPSIS

    use Socialtext::Daemontools;
    Socialtext::Daemontools->RunSupervised(
        log_file => 'st-foo.log', # STDERR/STDOUT go here
        port_name => 'foo_port', # calls this method on Socialtext::HTTP::Ports
        cb => sub {
            # result of calling Socialtext::HTTP::Ports->foo_port:
            my $port = shift;
            # run some perl or exec a script here
        }
    );

=head1 DESCRIPTION

Daemontools utility functions.

=cut
