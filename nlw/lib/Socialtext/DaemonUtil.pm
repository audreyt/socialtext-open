package Socialtext::DaemonUtil;
# @COPYRIGHT@
use warnings;
use strict;
use Carp qw/carp/;

sub Check_and_drop_privs {
    if ($>) {
        _check_privs();
    }
    else {
        _drop_privs();
    }
}

sub _check_privs {
    my $self = shift;

    my $data_root = Socialtext::AppConfig->data_root_dir();
    return if -w $data_root;

    unless (-d $data_root) {
        carp <<"EOF";

 The data root dir at $data_root does not exist!

EOF
        _exit(1);
    }

    my $uid      = ( stat $data_root )[4];
    my $username = getpwuid $uid;

    carp <<"EOF";

 The data root dir at $data_root is not writeable by this process.

 It is owned by $username.

 You can either run this process as $username or root in order to run
 this command.

EOF

    _exit(1);
}

sub _drop_privs {
    my ( $uid, $gid )
        = ( stat Socialtext::AppConfig->data_root_dir() )[ 4, 5 ];

    require POSIX;
    POSIX::setgid($gid);
    POSIX::setuid($uid);
}

# This exists so it can be overridden by tests and from_input.
sub _exit { exit shift; }

1;
