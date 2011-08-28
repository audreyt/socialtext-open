package Socialtext::Job::FixMimeType;
use Moose;
use Socialtext::SQL qw/sql_execute/;
use Socialtext::File qw/mime_type/;
use Socialtext::Search::AbstractFactory;
use Guard;
use File::Temp qw/tempfile/;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

sub do_work {
    my $self = shift;
    my $args = $self->arg;
    my $page = $self->page;

    my $attachment = $page->hub->attachments->load(
        id => $args->{id},
        page_id => $page->id,
        deleted_ok => 0,
    );
    $attachment->_page($page); # avoid lazy-loading

    if (update_mime_type($attachment)) {
        my @indexers = Socialtext::Search::AbstractFactory->GetIndexers(
            $self->workspace->name);

        $_->index_attachment($page->id, $attachment) for @indexers;
    }

    $self->completed();
}

sub update_mime_type {
    my $att = shift;

    my ($fh, $tmpfile) = tempfile();
    my $guard = scope_guard { unlink $tmpfile };
    $att->upload->copy_to_fh($fh);

    my $new_type = mime_type($tmpfile, $att->filename, $att->mime_type);

    if ($new_type ne $att->mime_type) {
        $att->mime_type($new_type);
        save_mime_type($att->attachment_id => $new_type);
        return 1;
    }
    else {
        return 0;
    }
}

sub save_mime_type {
    my $id = shift;
    my $mime_type = shift;

    sql_execute(qq{
        UPDATE attachment
           SET mime_type = ?
         WHERE attachment_id = ?
    }, $mime_type, $id);
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::FixMimeType - Fix "mime_type" field for attachments in database

=head1 SYNOPSIS

    use Socialtext::JobCreator;

    Socialtext::JobCreator->insert(
        'Socialtext::Job::FixMimeType => {
            workspace_id => $ws_id,
            page_id => $page_id,
            id => $attachment_id,
        }
    );

=head1 DESCRIPTION

Re-index old attachment's MIME types in the database, for the
[Task: fix mime-type mismatch of attachments] story.

=cut
