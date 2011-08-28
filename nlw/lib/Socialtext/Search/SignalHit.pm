package Socialtext::Search::SignalHit;
# @COPYRIGHT@
use Moose;
use Socialtext::Signal;

=head1 NAME

Socialtext::Search::SignalHit - A search result hit.

=head1 SYNOPSIS

    $hit = Socialtext::Search::SignalHit->new(
       signal_id => $signal_id,
       score => $score,
    );

    my $score = $hit->score()
    my $signal = $hit->signal();

=head1 DESCRIPTION

This represents a search result hit and provides handy accessors.

=cut

has 'score' => (is => 'ro', isa => 'Num', required => 1);
has 'signal_id' => (is => 'ro', isa => 'Int', required => 1);
has 'signal' => (is => 'ro', isa => 'Socialtext::Signal', lazy_build => 1);

sub _build_signal {
    my $self = shift;
    return Socialtext::Signal->Get(signal_id => $self->signal_id);
}

package Socialtext::Search::SignalAttachmentHit;
# @COPYRIGHT@
use Moose;
use Socialtext::Signal::Attachment;

=head1 NAME

Socialtext::Search::SignalAttachmentHit - A search result hit.

=head1 SYNOPSIS

    $hit = Socialtext::Search::SignalAttachmentHit->new(
       signal_id => $signal_id,
       filename => $filename,
       score => $score,
    );

    my $score = $hit->score;
    my $signal = $hit->signal;
    my $attachment = $hit->attachment;

=head1 DESCRIPTION

This represents a search result hit and provides handy accessors.

=cut

has 'score' => (is => 'ro', isa => 'Num', required => 1);
has 'signal_id' => (is => 'ro', isa => 'Int', required => 1);
has 'filename' => (is => 'ro', isa => 'Str', required => 1);
has 'signal' => (is => 'ro', isa => 'Socialtext::Signal', lazy_build => 1);
has 'attachment' => (is => 'ro', isa => 'Socialtext::Signal::Attachment', lazy_build => 1);

sub _build_signal {
    my $self = shift;
    return Socialtext::Signal->Get(signal_id => $self->signal_id);
}

sub _build_attachment {
    my $self = shift;
    return Socialtext::Signal::Attachment->GetForSignalFilename(
        $self->signal, $self->filename);
}

1;
