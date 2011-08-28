# @COPYRIGHT@
package Socialtext::File;
use strict;
use warnings;
use base 'Exporter';
our @EXPORT_OK = qw(
    set_contents set_contents_utf8 set_contents_binary set_contents_utf8_atomic
    get_contents get_contents_utf8 get_contents_binary
    ensure_directory mime_type
);

=head1 NAME

Socialtext::File - Assorted file and I/O utility routines.

=cut

use Carp qw(confess);
use Fcntl qw(:flock);
use File::Path;
use File::Spec;
use File::Temp;
use File::Find;
use Encode::Guess;
use List::Util qw/reduce/;

# NOTE: Please don't add any Socialtext::* dependencies.  This module
# should be able to be used by any other socialtext code without
# worrying about what dependencies are getting pulled in.

use namespace::clean;

=head1 SUBROUTINES

=head2 set_contents( $filename, $content [, $is_utf8 ] )

Creates file at C<$filename>, dumps C<$content> into the file, and
closes it.  If C<$is_utf8> is set, sets the C<:utf8> binmode on the file.

I<$content> may be a scalar reference.

Returns I<$filename>.

=head2 set_contents_utf8( $filename, $content )

A simple UTF8 wrapper around L<set_contents()>.

=head2 set_contents_based_on_encoding( $filename, $content, $encoding )

Set the contents of a file, using the requested C<$binmode> (which will have
C<:mmap> prepended to it.  See L<PerlIO>.

=head2 set_contents_binary ( $filename )

Set the contents of a binary file.

=head2 set_contents_binmode( $filename, $content, $binmode )

Set the contents of a file, using the requested C<$binmode>.  If the binmode
is omitted or is 'UTF-8', it will have C<:mmap> prepended to it.  See
L<PerlIO>.

=cut

sub set_contents_binmode {
    my $filename = shift;
    my $content  = shift;
    my $binmode  = shift || '';
    $binmode = ":mmap$binmode"
        if (length($binmode) == 0 or $binmode eq 'UTF-8');

    my $fh;
    open $fh, ">$binmode", $filename
        or confess( "unable to open $filename for writing: $!" );
    print $fh ref($content) ? $$content : $content
        or confess "Can't write $filename: $!";
    close $fh or confess "Can't write $filename: $!";
    return $filename;
}

sub set_contents {
    splice(@_,2,1, ($_[2]) ? ':utf8' : '');
    goto &set_contents_binmode;
}

sub set_contents_utf8 {
    splice(@_,2,1,':utf8');
    goto &set_contents_binmode;
}

sub set_contents_utf8_atomic {
    my $filename = shift;
    my ($dir,$file) = ($filename =~ m#^((?:.+)/)?([^/]+)$#);
    $dir ||= '.';
    my (undef, $temp) = File::Temp::tempfile("$file.tmpXXXXXX", DIR => $dir);
    set_contents_utf8($temp, @_);
    rename $temp => $filename
        or confess "Can't rename $temp to $filename: $!";
}

sub set_contents_binary {
    splice(@_,2,1,':mmap');
    goto &set_contents_binmode;
}

sub set_contents_based_on_encoding {
    splice(@_,2,1,":mmap:encoding($_[2])");
    goto &set_contents_binmode;
}

=head2 get_contents( $filename, [, $is_utf8 ] )

Slurps the file at C<$filename> and returns the content.  In list context,
returns a list of the lines in the file.  In scalar context, returns a
big string.

In either case, if C<$is_utf8> is set, sets the C<:utf8> binmode on
the file.

=head2 get_contents_utf8( $filename )

A simple UTF8 wrapper around L<get_contents()>.

=head2 get_contents_based_on_encoding( $filename, $encoding )

Slurp the contents of C<$filename> using C<$encoding> to transcode the chars.

=head2 get_contents_or_empty( $filename, ... )

Slurp the contents of a file, returning C<''> if there was any trouble (will
not raise an exception).  Parameters are passed to L<get_contents>.

=head2 get_contents_binary ( $filename )

Slurp a binary file.

=head2 get_contents_binmode( $filename, $binmode )

Slurp the contents of a file, using the requested C<$binmode> (which will have
C<:mmap> prepended to it).  See L<PerlIO>.

=cut

sub get_contents_binmode {
    my $filename = shift;
    my $binmode  = shift || '';
    $binmode = ":mmap$binmode";

    my $fh;
    open $fh, "<$binmode", $filename
        or confess( "unable to open $filename: $!" );

    if (wantarray) {
        my @contents = <$fh>;
        return @contents;
    }
    else {
        local $/;
        my $contents = <$fh>;
        return $contents;
    }
}

sub get_contents {
    splice(@_,1,1, ($_[1]) ? ':utf8' : '');
    goto &get_contents_binmode;
}

sub get_contents_based_on_encoding {
    splice(@_,1,1, ":encoding($_[1])");
    goto &get_contents_binmode;
}

sub get_contents_or_empty {
    my $contents = eval { get_contents(@_) };
    $contents = '' if ($@);
    return $contents;
}

sub get_contents_utf8 {
    splice(@_,1,1, ':utf8');
    goto &get_contents_binmode;
}

sub get_contents_binary {
    splice(@_,1,1,':mmap');
    goto &get_contents_binmode;
}

my $locale_encoding_names = {
    'ja' => 'euc-jp shiftjis cp932 iso-2022-jp utf8',
    'en' => 'utf8',
};


=head2 get_guess_encoding ( $locale, $file_full_path )

Guess the encoding of a file.  Suitable for use with L<get_contents_based_on_encoding>.

=cut

sub get_guess_encoding {
    my $locale = shift;
    my $file_full_path = shift;

    my $data;

    unless ( -e $file_full_path ) {
        return 'utf8';
    }

    open (FH, $file_full_path);
    my $len = -s $file_full_path;
    read FH, $data, $len;
    close FH;

    return guess_string_encoding($locale, \$data);
}

sub guess_string_encoding {
    my $locale = shift;
    my $data_ref = shift;
    my $encoding_names = $locale_encoding_names->{$locale};
    if ( ! defined $encoding_names) {
        return 'utf8';
    }
    my @match_list = split(/\s/, $encoding_names);
    my $enc = Encode::Guess::guess_encoding($$data_ref, @match_list);
    if ( ref($enc) ) {
        return $enc->name;
    } else {
        foreach (@match_list) {
            if ( $enc =~ /$_/ ) {
                return $_;
            }
        }
        return 'utf8';
    }
}

=head2 ensure_directory ( $path, [ $mode ] )

Make sure that the directory exists.  If C<$mode> is not specified it defaults
to C<0755>.

=cut

sub ensure_directory {
    my $directory = shift;
    my $mode = shift || 0755;
    return if -e $directory;
    eval { File::Path::mkpath $directory, 0, $mode };
    confess( "unable to create directory path $directory: $@" ) if $@;
}

=head2 ensure_empty_file($path, $tmp_path)

Attempts to ensure that $path exists on disk.  The mechanism is to first try
to create $tmp_path (unlinking any old, existing $tmp_path first), then link
it to $path.  If the link is either created or fails due to a link already
being present, $tmp_path is unlinked and the subroutine returns successfully.
If another process is racing to create the file at the same time, only one
will win, but both processes can then see and use the same file.  This is
particularly useful for ensuring two processes are using the same lock file.

If $tmp_path is not given, then ".$$" is appended to $path instead.

If any unexpected errors occur, this subroutine C<die()>s.

=cut

sub ensure_empty_file {
    my $path = shift;
    my $tmp_path = shift || "$path.$$";

    unless (unlink $tmp_path) {
        # The only acceptable error here is that the file didn't exist to
        # begin with.
        confess( "unlink '$tmp_path': $!" ) unless $!{ENOENT};
    }

    # XXX fix the perms here
    open my $l, '>', $tmp_path or confess( "create '$tmp_path': $!" );
    close $l or confess( "create '$tmp_path': $!" );
    unless (link $tmp_path, $path) {
        # The only acceptable error here is that the target ($path) already
        # existed.
        confess( "link '$tmp_path' -> '$path': $!" ) unless $!{EEXIST};
    }

    # REVIEW: This isn't really fatal, but I don't like to warn() in library
    # code.  How should we warn the caller?
    confess( "unlink '$tmp_path': $!" ) unless unlink $tmp_path;
}

sub directory_is_empty {
    my $directory = shift;
    opendir my $dh, $directory or confess( "unable to open directory: $!\n" );
    for my $e ( readdir $dh ) {
        return 0 unless $e =~ /^\.\.?$/;
    }
    return 1;
}

sub all_directory_files {
    my $directory = shift;
    opendir my $dh, $directory or confess( "unable to open directory: $!\n" );
    return grep { !/^(?:\.|\.\.)$/ && -f catfile( $directory, $_ ) }
        readdir $dh;
}

sub all_directory_directories {
    my $directory = shift;
    opendir my $dh, $directory or confess( "unable to open directory: $!\n" );
    return grep { !/^(?:\.|\.\.)$/ && -d catfile( $directory, $_ ) }
        readdir $dh;
}

sub catdir {
    if ( grep { ! defined } @_ ) {
        Carp::cluck('Undefined value passed to Socialtext::File::catdir');
    }
    return join('/', @_);
}

sub catfile {
    if ( grep { ! defined } @_ ) {
        Carp::cluck('Undefined value passed to Socialtext::File::catfile');
    }
    return join('/', @_);
}

sub tmpdir {
    return File::Spec->tmpdir;
}

sub temp_template_for {
    my $usage_string = shift;
    my $temptemplate = "/tmp/nlw-$usage_string-$$-$<-XXXXXXXXXX";
}

sub update_mtime {
    my $file = shift;
    my $time = shift || time;

    # REVIEW - there's a race condition here, but does it actually
    # matter? I don't think it does for files that are only being used
    # as timestamps, without any actual content (as in
    # Socialtext::EmailNotifyPlugin)
    unless ( -f $file ) {
        open my $fh, '>', $file
            or confess( "Cannot write to $file: $!" );
        close $fh;
    }

    utime $time, $time, $file
        or confess( "Cannot call utime on $file: $!" );
}

=head2 write_lock($file)

Given a file, attempts to lock this file for writing. Returns a
filehandle opened for writing to the file.

=cut

sub write_lock {
    my $file = shift;

    open my $fh, '>', $file
        or confess( "Cannot write to $file: $!" );
    flock $fh, LOCK_EX
        or confess( "Cannot lock $file for writing: $!" );

    return $fh;
}

=head2 files_under( @dirs )

Given a list of directories, returns a list of all the files in those
directories and below.

=cut

sub files_under {
    my @starting = @_;

    my @files;

    my $sub = sub { push @files, $File::Find::name if -f };
    find( { untaint => 1, wanted => $sub }, @starting );

    return @files;
}

=head2 files_and_dirs_under( @dirs )

Given a list of directories, returns a list of all the files and
directories in those directories and below.

=cut

sub files_and_dirs_under {
    my @starting = @_;

    my @files;

    my $sub = sub { push @files, $File::Find::name if -f || -d };
    find( { untaint => 1, wanted => $sub }, @starting );

    return @files;
}

=head2 clean_directory($path)

Remove all files and subdirectories from the specified directory.

If any unexpected errors occur, this subroutine C<die()>s.

=cut

sub clean_directory {
    my $directory = shift;

    rmtree($directory);
    ensure_directory($directory);
}

=head2 remove_directory($path)

Delete a directory.

If any unexpected errors occur, this subroutine C<die()>s.

=cut

sub remove_directory {
    my $directory = shift;

    eval { rmtree($directory) };
    confess( "unable to remove directory path $directory: $@" ) if $@;
}

=head2 safe_symlink($filename, $symlink)

Safely create a symlink 'symlink' that refers to 'filename'.

=cut

sub safe_symlink {
    my $filename = shift;
    my $symlink = shift;
    my $tmp_symlink = "$symlink.$$";
    symlink $filename, $tmp_symlink
        or die "Can't create symlink '$tmp_symlink': $!";
    rename $tmp_symlink => $symlink
        or die "Can't rename '$tmp_symlink' to '$symlink': $!";
}

sub newest_directory_file {
    my $directory = shift;

    return '' unless -e $directory;

    my @files = Socialtext::File::all_directory_files( $directory );
    return '' unless scalar( @files );

    return reduce { ( $a gt $b ) ? $a : $b } @files;
}

=head2 mime_type($path, $file_extension, $type_hint)

Returns the mime type of the file.

The algorithm is roughly as follows.  A "basic" type is defined to be either
"text/plain" or "application/octet-stream", or some other type that mime-magic
detection uses as a fallback (e.g. application/msword for OLE documents,
application/x-zip for everything zip-compressed).

First, we check the file "signature" using a mime-magic database.  If this
finds a type that B<isn't> a "basic" type, that type is returned.  Otherwise,
the function falls through to the next check.

If a C<$file_extension> isn't given, this check is skipped.  The file extension
is given as input to the C<Socialtext::MIME::Types> module.  If this check finds
a type, that type is returned.  If no type is found, this function falls through
to the next check.

If a C<$type_hint> isn't given, this check is skipped.  The type hint is for
example what an uploading browser or external system considers this file to be
typed as.  If present, it's returned instead of a "basic" type.

Finally, if no better type could be found using the above two checks, the
"basic" type that was found by the mime-magic check is returned.

=cut

# application/msword is detected for a number of OLE-type documents it seems.
our $is_basic_type = qr{^(?:
    text/(?:plain|html) | # non-anchored
    application/(?:
        octet-stream | # aka "binary"
        xml | # another basic type for lucid
        vnd\.ms-office | # lucid's magic db calls all OLE docs this
        zip | # lucid calls ZIP containers this
        msword | # dapper's magic db calls OLE docs this
        x-zip # dapper's magic db calls all ZIP magic this
    )$ # anchored
)}x;

sub mime_type {
    my ($path_to_file, $filename, $type_hint) = @_;

    local $@;
    my $magic_type = eval {
        require Socialtext::System;
        Socialtext::System::backtick('/usr/bin/file', '-Lib', $path_to_file);
    };
    chomp $magic_type if defined $magic_type;
    if ($magic_type) {
        $magic_type =~ s/; charset=(?:binary|us-ascii)$//;
            # Lucid's file adds this and is usually wrong when it does
        return $magic_type unless $magic_type =~ $is_basic_type;
    }

    if ($filename and $filename =~ m/.+\.([^.]+)$/) {
        my $file_ext = lc $1;
        $file_ext = 'eml' if $file_ext eq 'mht'; # {bz: 4257}
        my $type = eval {
            require Socialtext::MIME::Types;
            my $mt = Socialtext::MIME::Types::mimeTypeOf($file_ext);
            $mt->type;
        };
        return $type if ($type);
    }
    elsif ($filename) {
        # Filename without an extension; use the magic type from `file`
        return $magic_type if $magic_type;
    }

    return $type_hint if $type_hint;
    return $magic_type;
}

=head1 SEE ALSO

L<Socialtext::Paths>

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006-2010 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
