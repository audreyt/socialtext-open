#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::More tests => 122;
use Test::Socialtext::Fatal;
use File::Basename qw(dirname);
use File::Temp;
use File::Copy;
use utf8;

use ok 'Socialtext::System';
use ok 'Socialtext::File::Stringify';
use ok 'Socialtext::File::Stringify::text_html';

local $Socialtext::System::VMEM_LIMIT = 512 * 2**20;
local $Socialtext::System::TIMEOUT = 30; # for testing

my $base_dir = dirname(__FILE__) . "/stringify_data/html";

# not sure why, but using Test::Socialtext makes the oom test below not work.
system('make-test-fixture --fixture base_layout');

sub to_str { Socialtext::File::Stringify::text_html->to_string(@_) };

sub has_japanese_content ($$;$) {
    my ($buf, $ct, $name) = @_;
    $name ||= $ct;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    ok $buf !~ /<html>/, "$name didn't hit default stringifier";
    ok $buf =~ /\Q日本語/, "$name found decoded title"; # "Japanese"
    ok $buf =~ /\Qキーワード/, "$name found meta keywords"; # "keywords"
    ok $buf =~ /\Q説明/, "$name found meta description"; # "description"
    ok $buf =~ /\Qこのページは${ct}でいる/,
        "$name body text"; # "this page is $charset"
    ok $buf =~ m#\Qhttp://socialtext.com/?$ct リンクテキスト#i,
        "$name a-tag link plus text"; # "link text"
    ok $buf !~ /\Qconsole.log/, "$name no script content";
    ok $buf !~ /\QIgnored/, "$name no style content";
}

sub has_danish_content ($$;$) {
    my ($buf, $ct, $name) = @_;
    $name ||= $ct;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    ok $buf !~ /<html>/, "$name didn't hit default stringifier";
    ok $buf =~ /\QDansk/, "$name decoded title";
    ok $buf =~ /\Qsøgeord/, "$name meta keywords"; # "keywords"
    ok $buf =~ /\Qbeskrivelse/, "$name meta description"; # "description"
    like $buf, qr/\Qdenne side er $ct. Her er et billede af en kanin med en pandekage på hovedet. Æ!/, "$name body text"; # "this page is $charset. Here is a picture of a rabbit with a pancake on it's head. Ae!"
    ok $buf =~ m#\Qhttp://socialtext.com/?$ct linktekst#i,
        "$name a-tag link href plus text"; # "link text"
    ok $buf !~ /\Qconsole.log/, "$name no script content";
    ok $buf !~ /\QIgnored/, "$name no style content";
    ok $buf !~ m#\Qrelative#, "$name no relative links output";
}

missing: {
    my $filename = $base_dir .'/does-not-exist.html';
    my $buf;
    ok !exception {
        to_str(\$buf, $filename, 'text/html; charset=UTF-8');
    }, 'stringify with explicit charset';
    ok $buf eq '', "empty buffer on missing file";
}

oom_fail: {
    local $Socialtext::System::VMEM_LIMIT = 4096; # one page
    local $Socialtext::File::Stringify::text_html::DEFAULT_OK = 0;
    local $@;
    my $filename = $base_dir .'/japanese-utf8.html';
    my $buf;
    eval {
        to_str(\$buf, $filename, 'text/html; charset=UTF-8');
    }; ok $@, 'dies because of memory limit';
    ok $buf eq '', "empty buffer on oom";
}

utf8: {
    my $filename = $base_dir .'/japanese-utf8.html';
    my $buf;
    ok !exception {
        to_str(\$buf, $filename, 'text/html; charset=UTF-8');
    }, 'stringify with explicit charset';
    has_japanese_content($buf, 'UTF-8');
}

utf8_with_guess: {
    my $filename = $base_dir .'/japanese-utf8.html';
    my $buf;
    ok !exception {
        to_str(\$buf, $filename, 'text/html');
    }, 'stringify with absent charset (derived by meta header), guess utf8';
    has_japanese_content($buf, 'UTF-8', "UTF-8-guessed");
}

utf8_with_unknown: {
    my $filename = $base_dir .'/japanese-utf8.html';
    my $buf;
    ok !exception {
        to_str(\$buf, $filename, 'text/html; charset=unknown');
    }, 'stringify with "unknown" charset (derived by meta header), guess utf8';
    has_japanese_content($buf, 'UTF-8', "UTF-8-from-unknown");
}

utf16_no_guess: {
    my $filename = $base_dir .'/japanese-utf16.html';
    my $buf;
    ok !exception {
        to_str(\$buf, $filename, 'text/html; charset=UTF-16BE');
    }, 'stringify with explicit UTF-16 charset';
    has_japanese_content($buf, 'UTF-16', "UTF-16BE");
}

utf16le_no_guess: {
    my $filename = $base_dir .'/japanese-utf16le.html';
    my $buf;
    ok !exception {
        to_str(\$buf, $filename, 'text/html; charset=UTF-16LE');
    }, 'stringify with explicit UTF-16 charset';
    has_japanese_content($buf, 'UTF-16', "UTF-16LE");
}

utf16_guess: {
    my $filename = $base_dir .'/japanese-utf16.html';
    my $buf;
    ok !exception {
        to_str(\$buf, $filename, 'text/html');
    }, 'stringify UTF-16 with absent charset (derived by BOM)';
    has_japanese_content($buf, 'UTF-16', "UTF-16BE-BOM-guessed");
}

utf16le_guess: {
    my $filename = $base_dir .'/japanese-utf16le.html';
    my $buf;
    ok !exception {
        to_str(\$buf, $filename, 'text/html');
    }, 'stringify UTF-16 with absent charset (derived by BOM)';
    has_japanese_content($buf, 'UTF-16', "UTF-16LE-BOM-guessed");
}

sjis: {
    my $filename = $base_dir .'/japanese-shiftjis.html';
    my $buf;
    ok !exception {
        to_str(\$buf, $filename, 'text/html; charset=Shift_JIS');
    }, 'stringify with explicit Shift_JIS charset';
    has_japanese_content($buf, 'Shift-JIS', 'Shift_JIS');
}

sjis_with_guess: {
    my $filename = $base_dir .'/japanese-shiftjis.html';
    my $buf;
    ok !exception {
        to_str(\$buf, $filename, 'text/html');
    }, 'stringify with absent charset (derived by meta header), guess sjis';
    has_japanese_content $buf, 'Shift-JIS', 'Shift_JIS-guessed';
}

danish_utf8_with_guess: {
    my $filename = $base_dir .'/danish-utf8.html';
    my $buf;
    ok !exception {
        to_str(\$buf, $filename, 'text/html');
    }, 'stringify with absent charset (derived by meta header), guess utf8';
    has_danish_content($buf, 'UTF-8', "UTF-8-danish");
}

danish_iso_8859_1_with_guess: {
    my $filename = $base_dir .'/danish-iso-8859-1.html';
    my $buf;
    ok !exception {
        to_str(\$buf, $filename, 'text/html');
    }, 'stringify with absent charset (derived by meta header), guess iso';
    has_danish_content($buf, 'ISO-8859-1', "ISO-8859-1-danish");
}

danish_iso_8859_1_with_bogus_charset: {
    my $filename = $base_dir .'/danish-iso-8859-1.html';
    my $buf;
    ok !exception {
        to_str(\$buf, $filename, 'text/html; charset=bogus');
    }, 'stringify with bogus charset (derived by meta header), guess iso';
    has_danish_content($buf, 'ISO-8859-1', "ISO-8859-1-danish-bogus");
}

danish_utf8_with_low_limit: {
    my $filename = $base_dir .'/danish-utf8.html';
    no warnings 'redefine';
    *Socialtext::AppConfig::stringify_max_length = sub { 16 };
    my $buf;
    ok !exception {
        to_str(\$buf, $filename, 'text/html; charset=UTF-8');
    }, 'stringify with absent charset (derived by meta header), guess utf8';
    ok $buf !~ /<html>/, 'low-string limit did not use Default';
    ok $buf eq 'Dansk søgeord ', 'content was truncated just fine';
}

pass 'done';
