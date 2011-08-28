package Socialtext::Job::Upgrade::IndexOffice2007SignalAttachments;
# @COPYRIGHT@
use Moose;
use Socialtext::JobCreator;
use Socialtext::SQL qw(sql_execute);
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';
with 'Socialtext::CoalescingJob';

sub do_work {
    my $self = shift;

    my $sig_list = $self->_signal_ids();
    foreach my $signal_id (@{$sig_list}) {
        Socialtext::JobCreator->index_signal($signal_id, priority => 54);
    }

    $self->completed();
}

sub _signal_ids {
    my $self = shift;
    my $sth  = sql_execute( q{
        SELECT signal_id
          FROM signal_attachment
          JOIN attachment USING (attachment_id)
         WHERE attachment.filename ~* '\.(xls|doc|ppt)x$'
           AND NOT attachment.is_temporary;
    } );

    my $rows = $sth->fetchall_arrayref();
    my @ids  = map { $_->[0] } @{$rows};
    return \@ids;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::Upgrade::IndexOffice2007SignalAttachments - Index Office 2007 signal attachments

=head1 SYNOPSIS

  use Socialtext::JobCreator;

    Socialtext::JobCreator->insert(
        'Socialtext::Job::Upgrade::IndexOffice2007SignalAttachments',
    );

=head1 DESCRIPTION

Finds all Signals that have an Office 2007 document attached to them, and
creates jobs to have those signals indexed.

Up until this point we weren't indexing Office 2007 documents, so there
shouldn't be anything in the search index for them.

=cut
