package Socialtext::IndexingJob;
# @COPYRIGHT@
use Moose::Role;

requires 'do_work';

override 'keep_exit_status_for' => sub { 24 * 60 * 60 };
override 'retry_delay'          => sub { 60 * 60 };
override 'max_retries'          => sub { 14 * 24 };

around 'do_work' => sub {
    my $code = shift;
    my $self = shift;

    eval {
        $self->$code(@_);
    };
    if ($@ && $@ =~ /500 (?:read timeout|Can't connect)/i) {
        # tempfail
        $self->failed($@,1);
        return;
    }
    die $@ if $@;
};

no Moose::Role;
1;

=head1 NAME

Socialtext::IndexingJob

=head1 SYNOPSIS

    package MyJob;
    use Moose;
    extends 'Socialtext::Job';
    with 'Socialtext::IndexingJob';

    sub do_work { ... }

=head1 DESCRIPTION

Sets retry and failure behaviour for Index jobs.

=cut
