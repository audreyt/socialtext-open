package Socialtext::HTMLArchive;
# @COPYRIGHT@
use Moose;

use File::Basename qw/basename dirname/;
use File::Copy qw/copy/;
use File::Temp ();
use Socialtext::File;
use Socialtext::Formatter::Parser;
use Socialtext::String ();
use Guard;

use namespace::clean -except => 'meta';

has 'hub' => (is => 'rw', isa => 'Socialtext::Hub', weak_ref=>1);

sub create_zip {
    my ($self, $zip_file) = @_;
    die "Path to zip file does not exist\n" unless ($zip_file);
    $zip_file .= '.zip' unless $zip_file =~ /\.zip$/;
    die "Path to zip file does not existsi\n" if (!-e dirname($zip_file));

    my $dir = File::Temp->newdir(); # will cleanup

    # XXX: we're modifying the hub pretty hard here, would be nice if we could
    # just clone it.
    my $hub = $self->hub; # keep it strong while we're using it

    my $formatter
        = Socialtext::HTMLArchive::Formatter->new(hub => $hub);
    $hub->formatter($formatter);

    my $parser = Socialtext::Formatter::Parser->new(
        table      => $formatter->table,
        wafl_table => $formatter->wafl_table,
    );
    my $viewer = Socialtext::Formatter::Viewer->new(
        hub => $hub,
        parser => $parser,
    );
    $hub->viewer($viewer);

    for my $page ( $hub->pages->all ) {

        # XXX - for the benefit of attachments (why can't we just ask
        # a page what attachments it has?)
        $hub->pages->current($page);

        # XXX - calling this on display is a hack, but we cannot call
        # it on the hub directly (it's from Socialtext::Plugin).
        my $formatted_page = $hub->display->template_process(
            'html_archive_page.html',
            # The no-args form of to_html() should skip cache-writing.
            html         => sub { $page->to_html },
            title        => $page->name,
            html_archive => $self,
        );

        my $file = Socialtext::File::catfile( $dir, $page->page_id.".htm" );
        open my $fh, '>:utf8', $file or die "Cannot write to $file: $!";
        print $fh $formatted_page or die "Cannot write to $file: $!";
        close $fh or die "Cannot write to $file: $!";

        # set its timestamp
        my $mtime = $page->modified_time;
        utime $mtime, $mtime, $file
            or die "Cannot run utime on $file: $!";

        for my $att ($page->attachments) {
            my $target = Socialtext::File::catfile($dir, $att->clean_filename);
            $att->copy_to_file($target); # dies if it can't
            my $att_mtime = $att->created_at->epoch;
            utime $att_mtime, $att_mtime, $target
                or die "Cannot run utime on $target: $!";
        }
    }

    for my $css ( $self->{hub}->skin->css_files ) {
        my $file = Socialtext::File::catfile( $dir, basename($css) );
        copy( $css => $file ) or die "can't copy skin file: $!";
    }

    system( 'zip', '-q', '-r', '-j', $zip_file, $dir )
        and die "zip of $dir into $zip_file failed: $!";

    return $zip_file;
}

sub css_uris {
    my $self = shift;

    return map { basename($_) } $self->{hub}->skin->css_files;
}

################################################################################
package Socialtext::HTMLArchive::Formatter;

use base 'Socialtext::Formatter';

sub formatter_classes {
    my $self = shift;

    map {
        s/^FreeLink$/Socialtext::HTMLArchive::Formatter::FreeLink/;
        $_
    } $self->SUPER::formatter_classes(@_);
}

sub wafl_classes {
    my $self = shift;

    map {
        s/^File$/Socialtext::HTMLArchive::Formatter::File/;
        s/^Image$/Socialtext::HTMLArchive::Formatter::Image/;
        $_
    } $self->SUPER::wafl_classes(@_);
}

################################################################################
package Socialtext::HTMLArchive::Formatter::FreeLink;

# contains Socialtext::Formatter::FreeLink:
use Socialtext::Formatter::Phrase;
use base 'Socialtext::Formatter::FreeLink';

sub html {
    my $self = shift;

    my $page_title = $self->title;
    my ( $page_disposition, $page_link, $edit_it ) =
      $self->hub->pages->title_to_disposition($page_title);
    $page_link  = $self->uri_escape($page_link);
    $page_title = $self->html_escape($page_title);
    return '<a href="' . qq{$page_link.htm" $page_disposition>$page_title</a>};
}

################################################################################
package Socialtext::HTMLArchive::Formatter::File;

# contains Socialtext::Formatter::File:
use Socialtext::Formatter::WaflPhrase;
use base 'Socialtext::Formatter::File';

sub html {
    my $self = shift;

    my ( $workspace_name, $page_title, $file_name, $page_id, $page_uri ) =
      $self->parse_wafl_reference;
    return $self->syntax_error unless $file_name;
    my $label = $file_name;
    $label = "[$page_title] $label"
      if $page_title
      and ( $self->hub->pages->current->id ne
        Socialtext::String::title_to_id($page_title) );
    $label = "$workspace_name:$label"
      if $workspace_name
      and ( $self->hub->current_workspace->name ne $workspace_name );
    return qq{<a href="$file_name">$label</a>};
}

################################################################################
package Socialtext::HTMLArchive::Formatter::Image;

# contains Socialtext::Formatter::Image:
use Socialtext::Formatter::WaflPhrase;
use base 'Socialtext::Formatter::Image';

sub html {
    my $self = shift;

    my ( $workspace_name, $page_title, $image_name, $page_id, $page_uri ) =
      $self->parse_wafl_reference;
    return $self->syntax_error unless $image_name;
    return qq{<img src="$image_name" />};
}

package Socialtext::HTMLArchive;
__PACKAGE__->meta->make_immutable;
1;
