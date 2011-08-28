package Socialtext::File;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Exporter';

our @EXPORT_OK = qw/get_contents set_contents catdir mime_type
                    get_contents_utf8 set_contents_utf8 set_contents_utf8_atomic/;

our %CONTENT;
our %SYMLINK;

sub get_contents {
    my $filename = shift;
    my $content;
    $filename = $SYMLINK{$filename} if $SYMLINK{$filename};
    if ($content = $CONTENT{$filename}) {
        return $content;
    }
    warn "Returning mock content for path: '$filename'";
    return 'empty mock content';
}

sub set_contents {
    my $filename = shift;
    my $content = shift;
    $CONTENT{$filename} = $content;
}

sub get_contents_utf8 { get_contents(@_) }
sub set_contents_utf8 { set_contents(@_) }
sub set_contents_utf8_atomic { set_contents(@_) }

sub catdir { join('/',@_) }
sub catfile { join('/',@_) }

sub ensure_directory { 1 }

sub safe_symlink {
    my $filename = shift;
    my $symlink = shift;
    $SYMLINK{$symlink} = $filename;
}

sub write_lock { 1 }

sub mime_type { 'text/blah' }

1;
