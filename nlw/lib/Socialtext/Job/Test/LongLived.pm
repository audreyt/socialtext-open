package Socialtext::Job::Test::LongLived;
# @COPYRIGHT@
use Moose;
use Socialtext::Log qw(st_log);
use Time::HiRes qw/sleep/;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

override 'is_long_running' => sub { 1 };

sub do_work {
    my $self  = shift;
    my $delay = $self->arg->{'sleep'} || 10;
    st_log->debug("start long-lived job");
    sleep $delay;
    st_log->debug("finish long-lived job");
    $self->completed();
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::Test::LongLived - Test/sample Long-Lived Job

=head1 SYNOPSIS

  use Socialtext::JobCreator;

  Socialtext::JobCreator->insert(
    'Socialtext::Job::Test::LongLived',
    { sleep => 5 },
  );

=head1 DESCRIPTION

Schedules a Job which is "long running" and as such only runs in a percentage
of the available Workers (so that long-running Jobs don't inadvertently clog
or stall the rest of the queue).

=head1 SEE ALSO

L<Socialtext::Job::Test::ShortLived>.

=cut
