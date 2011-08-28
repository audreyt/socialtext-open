package Socialtext::Job::Test::ShortLived;
# @COPYRIGHT@
use Moose;
use Socialtext::Log qw(st_log);
use Time::HiRes qw/sleep/;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

override 'is_long_running' => sub { 0 };

sub do_work {
    my $self  = shift;
    my $delay = $self->arg->{'sleep'} || 0.2;
    st_log->debug("start short-lived job");
    sleep $delay;
    st_log->debug("finish short-lived job");
    $self->completed();
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::Test::ShortLived - Test/sample Short-Lived Job

=head1 SYNOPSIS

  use Socialtext::JobCreator;

  Socialtext::JobCreator->insert(
    'Socialtext::Job::Test::ShortLived',
    { sleep => 1 },
  );

=head1 DESCRIPTION

Schedules a Job which is "short running" and can run in B<any> of the
available Workers.

=head1 SEE ALSO

L<Socialtext::Job::Test::LongLived>.

=cut
