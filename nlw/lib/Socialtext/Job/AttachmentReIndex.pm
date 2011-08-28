package Socialtext::Job::AttachmentReIndex;
# @COPYRIGHT@
use Moose;
use Socialtext::Job::AttachmentIndex;

extends 'Socialtext::Job', 'Socialtext::Job::AttachmentIndex::Base';
with 'Socialtext::ReIndexJob', 'Socialtext::IndexingJob';

use constant 'check_skip_index' => 0;

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
no Moose;
1;
__END__

=head1 NAME

Socialtext::Job::AttachmentReIndex - do it again

=head1 SYNOPSIS

  use Socialtext::JobCreator;
  Socialtext::JobCreator->index_attachment(
    $attachment, $config,
    attachment_job_class => 'Socialtext::Job::AttachmentReIndex'
  );

=head1 DESCRIPTION

Exactly like AttachmentIndex but with special "bulk re-indexing" logic.

=cut
