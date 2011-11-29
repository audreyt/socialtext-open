# @COPYRIGHT@
package Socialtext::PdfExportPlugin;
use warnings;
use strict;
use base 'Socialtext::Plugin';

use Socialtext::PdfExport::LinkDictionary;
use File::chdir;
use Socialtext::l10n qw(loc __);
use Socialtext::Log qw(st_log);
use IPC::Run 'run';
use Readonly;
use Class::Field 'const';

=head1 NAME

Socialtext::PdfExportPlugin - Export a Workspace Page to PDF

=head1 DESCRIPTION

This module provides a system for outputting a PDF version of
a workspace page or pages that the user may save. The system
works by creating an HTML version of the pages and then
translating that version to PDF.

The translation is performed by calling the external command
C<htmldoc>.

=head1 METHODS

=cut

const class_id => 'pdf_export';
const class_title => __('class.pdf_export');
const cgi_class   => 'Socialtext::PdfExportPlugin::CGI';

# The full command for converting html files to PDF.  Set TMPDIR since htmldoc
# tends to create lots of temp files in some random compliation-specific
# place, and then doesn't clean them up.  At least this way the temp files go
# in a deterministic spot and standard utilities can clean up tmp regularly.
Readonly my @COMMAND => qw(
    env TMPDIR=/tmp htmldoc -t pdf
    --verbose --footer '' --header ''
    --path / --textfont helvetica --bodyfont helvetica --headingfont helvetica
    --no-strict --no-title --no-toc --no-compression --webpage
);

sub register {
    my $self     = shift;
    my $registry = shift;

    $registry->add( action => 'pdf_export' );
}

=head2 pdf_export

An action callable by the web interface to return a PDF
version of the page or pages named in the CGI page variable
C<page_selected>.

=cut
sub pdf_export {
    my $self = shift;

    my @page_names = $self->cgi->page_selected;
    if (0 == @page_names) {
        return loc("error.page-for-export-required");
    }

    # If there is only one page to be exported, set the current
    # page to the export page so TOC links render properly.
    if (1 == @page_names) {
        $self->hub->pages->current($self->hub->pages->new_page($page_names[0]));
    }

    my $pdf_content;

    if ($self->multi_page_export(\@page_names, \$pdf_content)) {
        my $filename = $self->cgi->filename || "$page_names[0].pdf";
        $self->hub->headers->add_attachment(
            filename => $filename,
            len      => length($pdf_content),
            type     => 'application/pdf',
        );
        return $pdf_content;
    }
    return loc("error.pdf-conversion-failed");
}

=head2 multi_page_export($page_names, \$output)

Puts a PDF representation of the the pages names in C<$page_names> into C<$output>. The
pages are placed on new pages. This method returns TRUE if the creation of the PDF file
was successul. If there was an error, an error message is placed in C<$output> and
C<multi_page_export> returns FALSE.

=cut
sub multi_page_export {
    my $self       = shift;
    my $page_names = shift;
    my $out_ref    = shift;

    return _run_htmldoc(
        '', $out_ref, @COMMAND,
        map { $self->_create_html_file($_) } @$page_names
    );
}


# _run_htmldoc( $input, $output_ref, @command )
#
# Runs the htmldoc command @command using the given input and output ref.
# Returns TRUE if a valid PDF file is created and false otherwise.
sub _run_htmldoc {
    my ( $input, $output_ref, @command ) = @_;

    # We ignore the exit code because htmldoc sometimes exits nonzero even
    # when a PDF was created.  We check for the '%PDF' magic number at the top
    # of the output instead. -mml
    {
        local $ENV{HTMLDOC_NOCGI} = 1;
        local $ENV{HTMLDOC_DEBUG} = 'all';

        # We must set our working directory to '/' because (and this is
        # undocumented, AFAICT; I got it from the source) if htmldoc reads
        # from STDIN, it forcibly sets '.' (the current working directory) to
        # be the root where it begins looking for files. -mml
        local $CWD = '/';

        # When htmldoc generates output, we *expect* some error output
        # indicating "Unable to connect to...".  Sucks, but htmldoc tries to
        # do HTTP lookups based on file paths.  We'll ignore these errors, but
        # anything else should be treated as an actual error condition.
        my $failures = 0;
        while ($failures < 5) {
            my $err;
            run \@command, \$input, $output_ref, \$err;

            my @stderr =
                grep { !/^\s*$/ }
                split /[\r\n]/, $err;
            my @errors =
                grep { !/Unable to connect to/ }
                grep { /^ERR/ }
                @stderr;

            if (@errors || $ENV{NLW_DEV_MODE}) {
                st_log->error("@command");
                st_log->error($_) for @stderr;
            }

            last unless @errors;

            $failures ++;
        }
    }

    return '%PDF' eq substr $$output_ref, 0, 4;
}
# EXTRACT: This probably belongs as a special method on either the formatter # or the page.
sub _get_html {
    my $self = shift;
    my $page_name = shift;

    my $initial_ws = $self->hub->current_workspace;

    my ($workspace_name, $page_id);

    if ($page_name =~ /:/) {
        ($workspace_name, $page_id) = split(/:/, $page_name, 2);

        if ($workspace_name && $workspace_name ne $self->hub->current_workspace->name) {
            my $ws = Socialtext::Workspace->new(name => $workspace_name);
            $self->hub->current_workspace($ws);
        }
        else {
            $workspace_name = $initial_ws->name;
        }

    }
    else {
        $workspace_name = $initial_ws->name;
        $page_id = $page_name;
    }

    my $page = $self->hub->pages->new_from_name( $page_id );

    # Old school here.  htmldoc doesn't support the &trade; entitity, and it
    # doesn't support Unicode.
    my $content = do {
        no warnings 'redefine';
        local *Socialtext::Formatter::TradeMark::html = sub {'<SUP>TM</SUP>'};
        $page->to_absolute_html(
            undef,
            link_dictionary => Socialtext::PdfExport::LinkDictionary->new,
        );
    };

    my $html = "<html><head><title>"
        . $page->name
        . "</title></head><body><h1>"
        . $page->name
        . "</h1>"
        . $content
        . "</body></html>";
    $self->hub->current_workspace($initial_ws) if ($initial_ws->name ne $workspace_name);
    return $html;    
}


sub _create_html_file {
    my $self = shift;
    my $page_name = shift;

    my $html = $self->_get_html($page_name);
    my $temp_file = File::Temp->new(UNLINK => 0, DIR => '/tmp', SUFFIX => '.html');
    binmode $temp_file, ':utf8';
    print $temp_file $html;
    return $temp_file->filename;
}

package Socialtext::PdfExportPlugin::CGI;
use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'page_selected';
cgi 'filename';


1;

=head1 AUTHOR

Socialtext, C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc. All Rights Reserved.

=cut
