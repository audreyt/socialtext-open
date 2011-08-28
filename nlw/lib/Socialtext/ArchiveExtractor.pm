# @COPYRIGHT@

=head1 NAME

Socialtext::ArchiveExtractor - Extracts files from zip and tar archives

=cut

package Socialtext::ArchiveExtractor;
use strict;
use warnings;

use Archive::Zip;
use Archive::Tar;
use File::Basename ();
use File::Copy ();
use File::Find ();
use Socialtext::File;
use Readonly;
use Socialtext::Validate qw( validate FILE_TYPE );

=head1 SYNOPSIS

  my @files = Socialtext::ArchiveExtractor->extract( archive => 'foo.zip' );

=head1 DESCRIPTION

This module extracts the individual files from an archive file into a
temp directory.

=head1 FUNCTIONS

This module offers the following method:

=cut

=head2 Socialtext::ArchiveExtractor->extract( archive => $filename )

This method expects a single parameter, "archive", which should
contain the full path to an archive file in either zip or tar
format. It can handle gzip'd tarballs.

If the given archive's extension does not match one of F<.zip>,
F<.tar>, F<.tar.gz>, or F<.tgz>, this method simply returns false.

This function returns a list of paths to all of the I<files> extracted
from the archive.

=cut

=head2 Socialtext::ArchiveExtractor::valid_archivename( filename )

Returns true if the filename has a valid archive extension, false otherwise

=cut

{
    Readonly my %Extensions => (
        '.zip'    => \&_unzip,
        '.tar'    => \&_untar,
        '.tar.gz' => \&_untar,
        '.tgz'    => \&_untar,
    );

    Readonly my $spec => { archive => FILE_TYPE };
    sub extract {
        shift;
        my %p = validate( @_, $spec );

        my $target = File::Temp::tempdir(
            Socialtext::File::temp_template_for('archive'),
            CLEANUP => 1,
        );

        my $ext =
            ( File::Basename::fileparse( $p{archive}, keys %Extensions ) )[2];

        my $func = $Extensions{$ext};

        return unless $func;

        return $func->( $p{archive}, $target );
    }

    sub valid_archivename {
        my $name = shift; # [in] Name of archive file

        my $ext = ( File::Basename::fileparse( $name, keys %Extensions ) )[2];

        my $func = $Extensions{$ext};

        return defined($func);
    }
}

sub _unzip {
    my $filename = shift;
    my $target = shift;

    my $zip = Archive::Zip->new;
    $zip->read($filename) == Archive::Zip::AZ_OK
        or die "Had trouble reading zip file ($filename).";

    my @files;
    for my $member ( $zip->members ) {
        my $name = $member->fileName;
        my $dest = Socialtext::File::catfile( $target, $name );

        $zip->extractMember($member, $dest) == Archive::Zip::AZ_OK
            or die "Had trouble extracting $name from zip file ($filename).";
        push @files, $dest
            if -f $dest;
    }

    return @files;
}

sub _untar {
    my $filename = shift;
    my $target = shift;

    my $tar = Archive::Tar->new;
    $tar->read($filename) or die $tar->error(1);

    my @files;
    for my $name ( $tar->list_files ) {
        my $dest = Socialtext::File::catfile( $target, $name );

        $tar->extract_file($name, $dest) or die $tar->error(1);
        push @files, $dest
            if -f $dest;
    }

    return @files;
}


1;
