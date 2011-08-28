package Socialtext::Job::Upgrade::FixBrokenStringifiersForWorkspace;
# @COPYRIGHT@
use Moose;
use File::Basename;
use File::Find::Rule;
use File::Spec;
use Socialtext::File;
use Socialtext::JobCreator;
use Socialtext::Paths;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

override 'keep_exit_status_for' => sub { 86400 };

sub do_work {
    my $self = shift;
    my $ws   = $self->workspace;

    my $dir = File::Spec->catdir(
        Socialtext::Paths::plugin_directory($ws->name), 'attachments');

    my $files = $self->_attachments_for($dir);
    for my $file (@$files) {
        my ($page_id, $attachment_id) =
            ($file =~ m{$dir/([^/]+)/([^/]+)/});

        Socialtext::JobCreator->index_attachment_by_ids(
            workspace_id => $ws->workspace_id,
            page_id      => $page_id,
            attach_id    => $attachment_id,
            priority     => 54,
        );
    }

    $self->completed();
}

sub _attachments_for {
    my ($self, $dir) = @_;

    my @files = File::Find::Rule->file()
       ->name(qr/\.(doc|xml)$/i)
       ->in($dir);

    return \@files;
}

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::Upgrade::FixBrokenStringifiersForWorkspace - Re-Index workspace page attachments that had broken stringifiers.

=head1 SYNOPSIS

  use Socialtext::JobCreator;

    Socialtext::JobCreator->insert(
        'Socialtext::Job::Upgrade::FixBrokenStringifiersForWorkspace', {
            workspace_id => $workspace_id,
        },
    );

=head1 DESCRIPTION

Finds all Pages in the specified Workspace that have a 'doc' or 'xml' document
attached to them, and creates jobs to have those attachments indexed.

=cut
