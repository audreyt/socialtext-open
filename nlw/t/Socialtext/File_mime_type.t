#!perl
# @COPYRIGHT@
use warnings;
use strict;

use Test::More tests => 24;
use ok 'Socialtext::File', 'mime_type';

my %files_and_types = (
    'sample.pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'sample.ppsx' => 'application/vnd.openxmlformats-officedocument.presentationml.slideshow',
    'sample.potx' => 'application/vnd.openxmlformats-officedocument.presentationml.template',
    'sample.xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'sample.xltx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.template',
    'sample.docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'sample.dotx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.template',
    'docx.png'    => 'image/png',
    'sample.doc'  => 'application/x-msword', # it's maybe OOXML tho
    'sample.ppt'  => 'application/vnd.ms-powerpoint', # it's maybe OOXML tho
    'sample.xls'  => 'application/vnd.ms-excel', # it's maybe OOXML tho
    'test.bin'    => 'application/octet-stream',
    'test.doc'    => 'application/x-msword',
    'test.html'   => 'text/html',
    'test.mp3'    => 'audio/mpeg',
    'test.pdf'    => 'application/pdf',
    'test.ppt'    => 'application/vnd.ms-powerpoint',
    'test.ps'     => 'application/postscript',
    'test.rtf'    => 'text/rtf',
    'test.txt'    => 'text/plain',
    'test.xls'    => 'application/vnd.ms-excel',
    'test.xml'    => 'application/xml',
    'test.zip'    => 'application/zip',
);

for my $file (sort keys %files_and_types) {
    my $expected = $files_and_types{$file};
    my $type = mime_type("t/Socialtext/File/stringify_data/$file",
        $file, 'xxx/type-not-found'
    );
    is $type, $expected, "file type for $file";
}
