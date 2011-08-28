package Socialtext::Job::Cmd;
# @COPYRIGHT@
use Moose;
use IPC::Run ();
use Socialtext::System qw/timeout_backtick/;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

override 'keep_exit_status_for' => sub { 86400 };

sub do_work {
    my $self = shift;
    my $cmd = $self->arg->{cmd};
    my $args = $self->arg->{args} || [];
    my $timeout = $self->arg->{timeout} || 10;

    my $output = timeout_backtick($timeout, $cmd, @$args);
    if (my $err = $@) {
        $output ||= "rc=$?";
        $self->failed($output,$?);
    }
    else {
        $self->completed($output);
    }
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;
