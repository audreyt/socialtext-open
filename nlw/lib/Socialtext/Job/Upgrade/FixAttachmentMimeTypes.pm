package Socialtext::Job::Upgrade::FixAttachmentMimeTypes;
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

=head1 NAME

Socialtext::Job::Upgrade::FixAttachmentMimeTypes 

=head1 SYNOPSIS

  Rewrite -mime files for attachments when neccessary, for a single workspace 

=head1 DESCRIPTION

Updates the mime types stored on disk (as -mime files next to the actual attachments) for workspace attachments, now that a new MIME detection library/tool is being used 

=cut

sub do_work {
    my $self = shift;
    my $ws   = $self->workspace;

    my $dir = File::Spec->catdir(
        Socialtext::Paths::plugin_directory($ws->name), 'attachments');

    my $files = $self->_attachments_for($dir);
    for my $file (@$files) {

        my $mtype_file = $file . "-mime";
        next unless -e $mtype_file;
        my $extension  = (File::Basename::fileparse($file, qr/[^\.]+$/))[2];

        my $cached  = Socialtext::File::get_contents($mtype_file);
        my $current = Socialtext::File::mime_type(
            $file, $extension, 'application/binary');

        if ($cached ne $current) {
            my ($page_id, $attachment_id) =
                ($file =~ m{$dir/([^/]+)/([^/]+)/});

            Socialtext::File::set_contents($mtype_file, $current);
            Socialtext::JobCreator->index_attachment_by_ids(
                workspace_id => $ws->workspace_id,
                page_id      => $page_id,
                attach_id    => $attachment_id,
                priority     => 54,
            );
        }
    }

    $self->completed();
}

sub _attachments_for {
    my ($self, $dir) = @_;

    my @files = File::Find::Rule->file()
       ->mindepth(3) # exclude metadata files
       ->not_name(qr/-mime$/) # exclude mime-type caches.
       ->in($dir);

    return \@files;
}

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;
