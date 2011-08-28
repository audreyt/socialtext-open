# @COPYRIGHT@
package Socialtext::Handler::Cleanup;
use strict;
use warnings;

use Apache;
use File::Temp 0.16 ();
use Socialtext::Cache ();
use Socialtext::SQL ();

BEGIN {
    my $s = Apache->server();
    my $max_process  = $s->dir_config('st_max_process_size');
    my $max_unshared = $s->dir_config('st_max_unshared_size');
    my $min_shared   = $s->dir_config('st_min_shared_size');
    require Apache::SizeLimit;
    Apache::SizeLimit->set_max_process_size($max_process) if $max_process;
    Apache::SizeLimit->set_max_unshared_size($max_unshared) if $max_unshared;
    Apache::SizeLimit->set_min_shared_size($min_shared) if $min_shared;
}

sub handler {
    my $r = shift;

    # Clean up lookup caches
    Socialtext::Cache->clear();

    File::Temp::cleanup();

    Socialtext::SQL::invalidate_dbh();

    @Socialtext::Rest::EventsBase::ADD_HEADERS = ();

    my ($size, $shared, $unshared) = Apache::SizeLimit->_check_size();
    Socialtext::Log::st_log()->debug("Size: process $size kiB, shared $shared kiB, unshared $unshared kiB");

    if (Apache::SizeLimit->VERSION >= 0.95) {
        Apache::SizeLimit::handler($r);
    }
    else {
        Apache::SizeLimit->handler($r);
    }
}

1;

__END__


=head1 NAME

Socialtext::Handler::Cleanup - a CleanupHandler for NLW

=head1 SYNOPSIS

  PerlCleanupHandler  Socialtext::Handler::Cleanup

=head1 DESCRIPTION

A handler to which we can add cleanup code and have it run for all
requests.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=cut
