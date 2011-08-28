package Socialtext::Rest::PageAttachment;
# @COPYRIGHT@
use warnings;
use strict;
use base 'Socialtext::Rest::Attachment';
use Socialtext::String ();

sub allowed_methods { 'GET' }
sub permission { +{ GET => 'read' } }

sub _get_attachment {
    my $self = shift;
    my $page_uri = $self->pname;
    my $filename = $self->filename;
    my $page_id =  Socialtext::String::title_to_id($page_uri);
    return $self->hub->attachments->latest_with_filename(
        page_id => $page_id, filename => $filename);
}

1;
__END__

=head1 NAME

Socialtext::Rest::PageAttachment - Grab the latest attachment by name

=head1 SYNOPSIS

    GET /data/workspaces/:ws/pages/:pname/attachments/:filename

=head1 DESCRIPTION

This module offers an attachment permalink capability.  You can specify
the attachment by name, and the latest version of that attachment will be returned.

=cut
