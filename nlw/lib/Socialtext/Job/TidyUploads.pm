package Socialtext::Job::TidyUploads;
# @COPYRIGHT@
use Moose;
use Socialtext::SQL qw/sql_execute sql_txn/;
use Socialtext::Upload;
use Socialtext::Theme;

extends 'Socialtext::Job';
with 'Socialtext::CoalescingJob';

use constant AT_A_TIME => 100; # just to limit the run-time of the select

sub do_work {
    my $self = shift;

    my @references = map {
          "attachment_id IN (SELECT attachment_id FROM $_)"
    } Socialtext::Upload::TABLE_REFS;


    push @references, map { "attachment_id IN (SELECT ". $_ ."_id FROM theme)" }
        @Socialtext::Theme::UPLOADS; 

    my $referenced = join "\nOR\n", @references;

    my $sth = sql_execute(qq{
        SELECT attachment_id FROM attachment a
        WHERE NOT ( $referenced )
        LIMIT ?
    }, AT_A_TIME);

    return $self->completed if $sth->rows == 0;

    while (my $row = $sth->fetchrow_arrayref) {
        my $att_id = $row->[0];
        # run in a txn to avoid conflicts with things picking abandoned rows
        sql_txn {
            sql_execute(q{
                DELETE FROM attachment WHERE attachment_id = ?
            }, $att_id)
        };
    }

    # Now clean up temp attachments
    Socialtext::Upload->CleanTemps();

    # Check again in FREQUENCY seconds.  We'll stop when there's no more work
    # to do.
    my $next = TheSchwartz::Moosified::Job->new({
        run_after => time + Socialtext::Upload::TIDY_FREQUENCY,
        (map { $_ => $self->job->$_ }
         qw(funcid funcname priority uniqkey coalesce)),
    });
    $self->job->replace_with($next);
}

__END__

=head1 NAME

Socialtext::Job::TidyUploads - Creature of the Sea

=head1 SYNOPSIS

  use Socialtext::JobCreator;
  my $jc = Socialtext::JobCreator->new;
  $jc->tidy_uploads($attachment_id);

=head1 DESCRIPTION

When we purge page_attachments, signal_attachments, or signal_assets we may
leave dangling attachment entries.  Guard against excessive attachments by
trying to clean up a few at a time in a job.

=cut
