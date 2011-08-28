#!perl -w
# @COPYRIGHT@
use strict;
use warnings;
use Test::More tests => 139;
use File::Basename qw(dirname);
use FindBin;
use Socialtext::File::Stringify;

# We need to specify a full lib path, as the stringify code will chdir
# elsewhere, but we need to load some libraries at run time.
use lib "$FindBin::Bin/../../../lib";

my @should_not_stringify = (
    # We don't index any type of image/
    'image/tiff', 'image/png', 'image/jpeg', 'image/gif', 'image/x-ms-bmp',
    'image/x-portable-greymap\0117bit', 'image/vnd.ms-modi',
    'image/vnd.microsoft.icon', 'image/x-photoshop',
    'image/vnd.dwg',

    # We only index audio/mpeg (.mp3)
    'audio/x-wav', 'audio/ogg', 'audio/x-ms-wma', 'audio/x-sd2',
    'audio/mp4', 'audio/x-aiff\011', 'audio/unknown\011',
    'audio/x-pn-realaudio', 'audio/x-aiff',

    # We don't index any kind of video
    'video/unknown', 'video/mpeg', 'video/x-ms-wmv', 'video/quicktime',
    'video/x-msvideo', 'video/mp4', 'video/mp2p', 'video/x-flv',
    'video/mpv', 'video/3gpp', 'video/x-ms-asf',

    # Other random things we don't index:
    'application/x-qgis',
    'application/x-dosexec',
    'application/binary',
    'application/octet-stream',
    'application/vnd.yamaha.smaf-phrase',
    'x-chemical/x-pdb',
    'application/x-empty',
    'application/x-shockwave-flash',
    'application/x-java-archive',
    'application/msaccess',
    'application/vnd.visio',
    'chemical/x-cache',
    'application/x-rar',
    'application/x-java-vm',
    'application/vnd.oasis.opendocument.spreadsheet',
    'application/vnd.ms-pki.seccat',
    'application/x-msdos-program',
    'application/vnd.oasis.opendocument.text',
    'application/x-gzip',
    'x-drawing/dwf',
    'application/x-font',
    'application/vnd.ms-project',
    'application/x-msi',
    'application/x-zip',
    'very short file (no magic)',
    'application/x-executable, statically linked, stripped',
    'application/x-archive application/x-debian-package',
    'application/x-executable, for GNU/Linux 2.4.1, dynamically linked (uses shared libs), for GNU/Linux 2.4.1, not stripped',
    'text/PGP armored data  message',
    'text/PGP armored data  public key block',
);

for my $mime_type (@should_not_stringify) {
    my $got = Socialtext::File::Stringify->Load_class_by_mime_type($mime_type);
    ok(!$got, $mime_type);
}

my @tests = (
    ['text/comma-separated-values' => 'text_plain'],
    ['text/html' => 'text_html'],
    ['application/pdf' => 'application_pdf'],
    ['application/x-msword' => 'application_msword'],
    ['application/json' => 'text_plain'],
    ['text/plain' => 'text_plain'],
    ['application/vnd.ms-excel' => 'application_vnd_ms_excel'],
    ['text/csv' => 'text_plain'],
    ['application/xml' => 'text_xml'],
    ['text/x-c; charset=us-ascii' => 'text_plain'],
    ['application/vnd.ms-powerpoint' => 'Tika'],
    ['text/plain; charset=us-ascii' => 'text_plain'],
    ['text/html; charset=us-ascii' => 'text_html'],
    ['application/x-awk' => 'text_plain'],
    ['application/vnd.openxmlformats-officedocument.wordprocessingml.document' => 'Tika'],
    ['application/zip' => 'application_zip'],
    ['text/plain; charset=utf-8' => 'text_plain'],
    ['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' => 'Tika'],
    ['text/html; charset=iso-8859-1' => 'text_html'],
    ['application/vnd.openxmlformats-officedocument.presentationml.presentation' => 'Tika'],
    ['text/html; charset=unknown' => 'text_html'],
    ['text/x-c++; charset=us-ascii' => 'text_plain'],
    ['text/html; charset=utf-8' => 'text_html'],
    ['text/rtf' => 'text_rtf'],
    ['text/css' => 'text_plain'],
    ['audio/mpeg' => 'audio_mpeg'],
    ['application/javascript' => 'text_plain'],
    ['application/x-ns-proxy-autoconfig' => 'text_plain'],
    ['text/x-chdr' => 'text_plain'],
    ['application/msword' => 'application_msword'],
    ['text/x-c; charset=unknown' => 'text_plain'],
    ['text/x-c; charset=utf-16' => 'text_plain'],
    ['application/x-perl' => 'text_plain'],
    ['text/x-c; charset=utf-8' => 'text_plain'],
    ['text/x-java' => 'text_plain'],
    ['text/x-c++; charset=utf-8' => 'text_plain'],
    ['text/x-c; charset=iso-8859-1' => 'text_plain'],
    ['application/postscript' => 'application_postscript'],
    ['text/html; charset=utf-16' => 'text_html'],
    ['application/xslt+xml' => 'text_xml'],
    ['text/x-java; charset=us-ascii' => 'text_plain'],
    ['text/x-tex' => 'text_plain'],
    ['text/plain; charset=utf-16' => 'text_plain'],
    ['text/cache-manifest' => 'text_plain'],
    ['message/rfc822' => 'text_plain'], # but maybe an archive extractor l8r
    ["message/rfc822\0117bit" => 'text_plain'],
    ['text/x-mail; charset=us-ascii' => 'text_plain'],
    ['application/x-shellscript' => 'text_plain'],
    ['application/x-httpd-php' => 'text_plain'],
    ['text/x-java; charset=iso-8859-1' => 'text_plain'],
    ['text/scriptlet' => 'text_plain'],
    ['text/x-vCard' => 'text_plain'],
    ['application/vnd.ms-excel.sheet.binary.macroEnabled.12' => 'application_vnd_ms_excel'],
    ['application/vnd.ms-excel.sheet.macroEnabled.12' => 'application_vnd_ms_excel'],
    ['application/vnd.openxmlformats-officedocument.wordprocessingml.template' => 'Tika'],
    ['application/vnd.ms-powerpoint.presentation.macroEnabled.12' => 'Tika'],
    ['text/x-c++src' => 'text_plain'],
    ['text/x-mail; charset=iso-8859-1' => 'text_plain'],
    ['text/x-python' => 'text_plain'],
    ['text/x-component' => 'text_html'], # .htc files are html
    ['application/vnd.openxmlformats-officedocument.presentationml.slideshow' => 'Tika'],
    ['text/plain; charset=iso-8859-1' => 'text_plain'],
    ['text/x-makefile; charset=us-ascii' => 'text_plain'],
    ['application/x-troff' => 'text_plain'],
    ['text/x-c++; charset=unknown' => 'text_plain'],
    ['text/plain; charset=unknown' => 'text_plain'],
    ['text/x-mail; charset=unknown' => 'text_plain'],
    ['application/x-ruby' => 'text_plain'],
    ['application/vnd.ms-word.document.macroEnabled.12' => 'application_msword'],
    ['text/x-asm; charset=utf-8' => 'text_plain'],
    ['text/x-c++; charset=utf-16' => 'text_plain'],
    ['text/x-java; charset=unknown' => 'text_plain'],
    ['text/x-c++; charset=iso-8859-1' => 'text_plain'],
    ['application/vnd.openxmlformats-officedocument.spreadsheetml.template' => 'Tika'],
    ['text/x-mail; charset=utf-8' => 'text_plain'],
    ["message/news\0118bit" => 'text_plain'],
    ['application/x-sh' => 'text_plain'],
    ['application/vnd.openxmlformats-officedocument.presentationml.template' => 'Tika'],
    ['image/svg+xml' => 'text_xml'],
);

for my $test (@tests) {
    my ($mime_type, $expected_class) = @$test;

    my $got = Socialtext::File::Stringify->Load_class_by_mime_type($mime_type);
    $got =~ s/^Socialtext::File::Stringify:://;
    is($got, $expected_class, $mime_type);

    exit -1 unless $got eq $expected_class;
}

