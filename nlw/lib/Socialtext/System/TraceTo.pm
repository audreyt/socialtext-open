package Socialtext::System::TraceTo;
# @COPYRIGHT@
use warnings;
use strict;
use PerlIO::via::Logger format => '[%d/%b/%Y:%H:%M:%S %z] ';

sub import {
    my $class = shift;
    my $logname = shift;
    return unless $logname;
    logfile($logname);
}

our $LogFH;
sub logfile ($) {
    return if $ENV{PERLCHECK};
    my $logname = shift;
    open $LogFH, '>>', $logname
        or die "can't open log '$logname' for appending";
    select $LogFH; $|=1;
    open STDERR, '>&', $LogFH;
    select STDERR; $|=1;
    open STDOUT, '>&', $LogFH;
    select STDOUT; $|=1; # make sure to select STDOUT last

    use POSIX ();
    POSIX::setlocale(&POSIX::LC_ALL, 'en_US.UTF-8');
    PerlIO::via::Logger::logify(*STDERR);
    PerlIO::via::Logger::logify(*STDOUT);
}

1;
__END__

=head1 NAME

Socialtext::System::TraceTo - Redirect STDOUT/ERR to a log file

=head1 SYNOPSIS

To make *all* STDOUT/STDERR go to a logfile (including syntax errors):

  #!perl
  use warnings;
  use strict;
  INIT { use Socialtext::System::TraceTo '/path/to/logfile' }

To make STDOUT/STDERR go to a log file at some point:

  #!perl
  use warnings;
  use strict;
  use Socialtext::System::TraceTo;
  # ... yada yada yada ...
  Socialtext::System::TraceTo::logfile('/path/to/logfile');

=head1 DESCRIPTION

Redirects STDOUT and STDERR to a log file.  Turns on autoflush for both
filehandles as well as the third log filehandle.  The opened filehandle will
be used by all C<exec()> commands; it's not closed-on-exec.

This simulates saying the following in bash:

  command >>/path/to/logfile 2>&1

=cut
