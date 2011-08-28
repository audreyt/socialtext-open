package Socialtext::Job::Upgrade::SwitchToSolr;
# @COPYRIGHT@
use Moose;
use Socialtext::JobCreator;
use Socialtext::Log qw/st_log/;
use Socialtext::System qw/shell_run/;
use Socialtext::User;
use Socialtext::EmailSender::Factory;
use Clone qw/clone/;
use namespace::clean -except => 'meta';

# Note: if you'd like to write a recurring monitor job, you should be
# consuming the new Socialtext::Job::Upgrade::Monitor role. Please see
# Socialtext::Job::Upgrade::MakeExplorePublic for an example.

extends 'Socialtext::Job';

# Try this every 2 minutes.
my $Job_delay = 2 * 60;

override 'retry_delay' => sub { $Job_delay };
override 'max_retries' => sub {0x7fffffff};

sub do_work {
    my $self = shift;

    # find the count of PageReIndex and AttachmentReIndex jobs
    my $jobs = Socialtext::Jobs->new;
    my $count = 0;
    for my $type (qw(PageReIndex AttachmentReIndex Upgrade::ReIndexWorkspace)) {
        $count += $jobs->job_count("Socialtext::Job::$type");
    }
    if ($count) {
        st_log->info(
            "SEARCH UPGRADE: There are $count re-index jobs remaining.");

        my @clone_args = map { $_ => $self->job->$_ }
            qw(funcid funcname priority uniqkey coalesce);
        my $next_job = TheSchwartz::Moosified::Job->new({
            @clone_args,
            run_after => time + $Job_delay,
            arg => {
                %{clone($self->arg)},
                last_count => $count,
            }
        });
        $self->replace_with($next_job);
    }
    else {
        st_log->info("SEARCH UPGRADE: ".
            "There are no more re-index jobs. ".
            "Enabling Solr for workspace search now.");
        $self->_enable_solr();
        $self->_email_technical_admins();
        $self->completed();
    }
}

sub _enable_solr {
    my $self = shift;

    shell_run("sudo st-appliance-set-config search_factory_class "
                . "Socialtext::Search::Solr::Factory");
}

sub _email_technical_admins {
    my $self = shift;

    my $admin_cursor = Socialtext::User->AllTechnicalAdmins;

    my $email_sender = Socialtext::EmailSender::Factory->create('en');
    $email_sender->send(
        from      => Socialtext::User->SystemUser->email_address,
        to        => [
            map { $_->name_and_email } $admin_cursor->all()
        ],
        subject   => "Your Socialtext Appliance search migration is complete",
        text_body => <<EOT,
Hello Socialtext Appliance Technical admin,

The search re-indexing of the workspace content in your Socialtext Appliance
has finished. Your appliance is now using the upgraded search capability.

Sincerely,
Your Socialtext Appliance
EOT
    );
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::Upgrade::SwitchToSolr - When the time is right, make Solr the
                                         default for workspace search.

=head1 SYNOPSIS

  use Socialtext::JobCreator;

    Socialtext::JobCreator->insert(
        'Socialtext::Job::Upgrade::SwitchToSolr'
    );

=head1 DESCRIPTION

Looks for outstanding *ReIndex jobs and when they are done
it switches workspace search over to Solr.

=cut
