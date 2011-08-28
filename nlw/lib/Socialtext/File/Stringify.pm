# @COPYRIGHT@
package Socialtext::File::Stringify;
use strict;
use warnings;

use Socialtext::MIME::Types ();
use Socialtext::System;
use Socialtext::File::Stringify::Default;
use Socialtext::Encode qw/ensure_ref_is_utf8/;
use Socialtext::File qw/mime_type/;
use Socialtext::Log qw/st_log/;
use File::Temp qw/tempdir/;
use File::chdir;
use File::Path qw/rmtree/;

sub to_string {
    my ( $class, $buf_ref, $filename, $type ) = @_;
    return unless defined $filename;

    $filename = Cwd::abs_path($filename);

    $type ||= mime_type($filename, $filename);
    st_log()->info("Stringify: $type - $filename");

    # some stringifiers emit a bunch of junk into the cwd/$HOME
    # (I'm looking at you, ELinks)
    my $tmpdir = tempdir(CLEANUP=>1);
    my $text;
    {
        local $ENV{HOME} = $tmpdir;
        local $CWD = $tmpdir;

        # default 5 minute timeout for backticked scripts
        local $Socialtext::System::TIMEOUT = 300;
        # default 2 GiB (minus 4kiB) virtual memory space for backticked scripts.
        # subtract 4kiB so we don't overflow a 32-bit signed integer.
        local $Socialtext::System::VMEM_LIMIT = (2 * 2**30) - 4096;

        my $convert_class = $class->Load_class_by_mime_type($type);
        if ($convert_class) {
            $convert_class->to_string($buf_ref, $filename, $type);
        }
        else {
            $$buf_ref = '';
        }
    }

    # Proactively cleanup, to avoid temp files left by long running processes
    rmtree $tmpdir;

    ensure_ref_is_utf8($buf_ref);
    st_log()->info("Stringify: done $filename - ".length($$buf_ref)." characters");
    return;
}

{
    my %special_converters = (
        'audio/mpeg'                    => 'audio_mpeg',
        'application/pdf'               => 'application_pdf',
        'application/postscript'        => 'application_postscript',
        'application/vnd.ms-excel'      => 'application_vnd_ms_excel',
        'application/x-msword'          => 'application_msword',
        'application/msword'            => 'application_msword',
        'application/vnd.ms-word'       => 'application_msword',
        'application/xml'               => 'text_xml',
        'application/zip'               => 'application_zip',
        'application/xml'               => 'text_xml',
        'application/json'              => 'text_plain',
        'application/javascript'        => 'text_plain',
        'application/x-ns-proxy-autoconfig' => 'text_plain',
        'application/x-perl'            => 'text_plain',
        'application/x-shellscript'     => 'text_plain',
        'application/x-httpd-php'       => 'text_plain',
        'application/x-troff'           => 'text_plain',
        'application/x-ruby'            => 'text_plain',
        'application/x-python'          => 'text_plain',
        'application/x-sh'              => 'text_plain',
        'text/html'                     => 'text_html',
        'text/x-component'              => 'text_html', # .htc
        'text/rtf'                      => 'text_rtf',
        'text/xml'                      => 'text_xml',
        'text/pgp'                      => undef,
        'message/rfc822'                => 'text_plain',
        'message/news'                  => 'text_plain',
        'application/x-awk'             => 'text_plain', # .vcf, usually
    );

    sub Load_class_by_mime_type {
        my ($class, $type) = @_;

        $type = lc $type;
        $type =~ s/[[:space:][:cntrl:];,].+$//;

        return unless $type =~ m!/!;

        my $default = join('::', $class, 'Default');
        return $default unless $type;

        my $converter;
        if (exists $special_converters{$type}) {
            $converter = $special_converters{$type};
            return unless defined $converter;
        }
        else {
            if ($type =~ m#^text/#) {
                $converter = 'text_plain';
            }
            elsif ($type =~ m#\+xml$#) {
                $converter = 'text_xml';
            }
            elsif ($type =~ m#^application/vnd.openxmlformats-officedocument#) {
                $converter = 'Tika';
            }
            elsif ($type =~ m#^application/(?:x-|vnd\.)?ms-?powerpoint#) {
                $converter = 'Tika';
            }
            elsif ($type =~
                m#^application/(?:x-|vnd\.)?ms-?(excel|powerpoint|word)#)
            {
                my $subtype = $1;
                if ($subtype eq 'word') {
                    $converter = 'application_msword';
                }
                elsif ($subtype eq 'powerpoint') {
                    $converter = 'application_vnd_ms_powerpoint';
                }
                elsif ($subtype eq 'excel') {
                    $converter = 'application_vnd_ms_excel';
                }
                else {
                    return;
                }
            }
            elsif ($type =~ m#^(?:image|video|audio|application|
                                  x-.*|chemical)/#x) {
                return;
            }
            else {
                $converter = 'Default';
            }
        }
        my $class_name = join('::', $class, $converter);

        eval "use $class_name;";
        warn $@ if $@;
        return $@ ? $default : $class_name;
    }
}

sub PreLoad {
    my $class = shift;
    # pre-load any predominantly Perl-based stringifiers here.
    require Socialtext::File::Stringify::Default;
    require Socialtext::File::Stringify::text_plain;
    require Socialtext::File::Stringify::text_html;
    require Socialtext::File::Stringify::text_xml;
}

1;
__END__

=pod

=head1 NAME

Socialtext::File::Stringify - Convert various file types to strings.

=cut

=head1 SUBROUTINES

=head2 to_string ( filename, [type] )

The file's MIME type is computed and used to dispatch to a specific method
that knows how to convert files of that type.  If type is passed in then it
overrides what MIME::Type would return.

=head1 SEE ALSO

L<Socialtext::MIME::Types>, L<Socialtext::File::Stringify::*>

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT

Copyright 2006 Socialtext, Inc., all rights reserved.

=cut
