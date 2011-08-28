#!perl -w
# @COPYRIGHT@
use strict;
use warnings;
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext tests => 58;
use Test::Warn;
use File::Basename qw(dirname);
use FindBin;

# We need to specify a full lib path, as the stringify code will chdir
# elsewhere, but we need to load some libraries at run time.
use lib "$FindBin::Bin/../../../lib";

fixtures('base_layout');

my $data_dir = dirname(__FILE__) . "/stringify_data";
my %ext_deps = (
    html => 'HTML::Parser',
    doc  => 'wvText',
    rtf  => 'unrtf',
    pdf  => 'pdftotext',
    ps   => 'ps2ascii',
    xls  => 'xls2csv',
    mp3  => 'MP3::Tag',
    xml  => 'XML::LibXML',
    zip  => 'unzip',
);

BEGIN {
    use_ok("Socialtext::File::Stringify");
}

for my $ext (qw(txt html doc rtf pdf ps xls ppt xml mp3)) {
    my $file = $data_dir . "/test.$ext";

    my $text;
    warning_is { Socialtext::File::Stringify->to_string(\$text, $file); }
        undef, "no warnings";

    SKIP: {
        skip( "$ext_deps{$ext} not installed.", 3 ) if should_skip($ext);
        ok( $text =~ /This file is a \"$ext\" file/, "Test $ext marker" );
        ok( $text =~ /linsey-woolsey/, "Shakespeare 1 ($ext)" );
        ok( $text =~ /Their force, their purposes;.+nay, I'll speak that/s,
            "Shakespeare 2 ($ext)" );
    };
}

for my $ext (qw(bin)) {
    my $file = $data_dir . "/test.$ext";
    my $text; Socialtext::File::Stringify->to_string(\$text, $file);
    ok !length($text), "didn't try to decode an $ext file";
}

office_2007_documents: {
    my $text;
    my %extensions = (
        docx => 'Word',
        xlsx => 'Excel',
        pptx => 'PowerPoint',
    );
    for my $ext (keys %extensions) {
        my $type = $extensions{$ext};
        undef $text;
        Socialtext::File::Stringify->to_string(\$text, "$data_dir/sample.$ext");

        clear_log();
        ok(
            $text =~
            /This\s+is\s+Brandon.\s*s\s+test\s+\Q$type\E\s+document\.\s+Yay/,
            "content for $type document is correct"
        );
        logged_unlike 'error', qr{st-tika failed on ".+/bad.docx": },
            "st-tika didn\'t log an error for $type doc";
    }

    clear_log();
    undef $text;
    Socialtext::File::Stringify->to_string(\$text, "$data_dir/bad.docx");
    logged_like 'error', qr{st-tika failed on ".+/bad.docx": },
        'st-tika logged an error for bad docx';

    clear_log();
    undef $text;
    Socialtext::File::Stringify->to_string(\$text, "$data_dir/just-pic.docx");
    logged_like 'warning', qr{No text found in file ".+/just-pic.docx"},
        'got no text warning';
    ok !$text, '... and got no text back from Tika';
}

# Test zip file indexing 
zip_file: {
    skip( "$ext_deps{zip} not installed.", 6 ) if should_skip("zip");
    my $zip_text;
    Socialtext::File::Stringify->to_string(\$zip_text, "$data_dir/test.zip");

    # these ext correspond to files in the zipfile)
    for my $ext (qw(doc ppt ps html txt xls)) {
        sub_zip_file: {
            skip( "$ext_deps{$ext} not installed.", 1 ) if should_skip($ext);
            ok(
                $zip_text =~ /This file is a \"$ext\" file/,
                "Test $ext marker in zip"
            );
        }
    }

    PW_PROTECTED: {
        my $protected_zip = "$data_dir/password-vegan.zip";
        die unless -e $protected_zip;
        diag("IF THIS TEST HANGS, HIT ENTER");
        my $text;
        Socialtext::File::Stringify->to_string(\$text, $protected_zip);
        ok(1, "Process a PW protected zip file w/o hanging");
    }
}

sub should_skip {
    my $ext = shift;
    return 0 unless exists $ext_deps{$ext};
    if ( $ext_deps{$ext} =~ /:/ ) {
        eval "require $ext_deps{$ext}; 1;";
        return $@ ? 1 : 0;
    }
    else {
        chomp( my $prog = `which $ext_deps{$ext} 2>/dev/null` );
        return $? || length($prog) == 0;
    }
}
