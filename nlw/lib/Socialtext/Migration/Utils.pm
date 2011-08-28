package Socialtext::Migration::Utils;
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::Schema;
use Socialtext::JobCreator;
use Socialtext::Workspace;
use List::MoreUtils qw(any);
use base 'Exporter'; 
our @EXPORT_OK = qw/socialtext_schema_version ensure_socialtext_schema
                    create_job_for_each_workspace create_job
                    create_job_for_each_account/;

sub socialtext_schema_version {
    my $schema = Socialtext::Schema->new;
    return $schema->current_version;
}

sub ensure_socialtext_schema {
    my $max_version = shift || die 'A maximum version number is mandatory';

    my $schema = Socialtext::Schema->new;
    return if $schema->current_version >= $max_version;

    print "Ensuring socialtext schema is at version $max_version\n";
    $schema->sync( to_version => $max_version );
}

sub _create_job_for_all {
    my ($all, $key, $class, $prio, %opts) = @_;
    die 'A job class is mandatory' unless $class;
    $prio = 31 unless defined $prio;
    my $except = $opts{except} || [];

    my $class_path = $opts{not_upgrade}
        ? 'Socialtext::Job::'
        : 'Socialtext::Job::Upgrade::';
    my $job_class = $class_path . $class;

    my $job_count = 0;
    while (my $obj = $all->next) {
        my $name = $obj->name;
        next if any { $_ eq $name } @$except;
        Socialtext::JobCreator->insert( $job_class,
            { 
                $key => $obj->$key, # workspace_id or account_id
                job => {
                    coalesce => $name,
                    ($prio ? (priority => $prio) : ()),
                },
                %{$opts{args} || {}}, # extra args
            },
        );
        $job_count++;
    }

    $job_count++;

    print "Inserted $job_count $job_class jobs\n";
}

sub create_job_for_each_workspace {
    _create_job_for_all(Socialtext::Workspace->All, 'workspace_id', @_);
}

sub create_job_for_each_account {
    _create_job_for_all(Socialtext::Account->All, 'account_id', @_);
}

sub create_job {
    my $class = shift || die 'A job class is mandatory';
    my $prio  = shift;
    $prio = 31 unless defined $prio;
    my $arg = shift || {};
    my $job_class = 'Socialtext::Job::Upgrade::' . $class;

    Socialtext::JobCreator->insert( $job_class, {%$arg, job => {coalesce => 'only', priority => $prio}} );

    print "Inserted $job_class job\n";
}

1;
