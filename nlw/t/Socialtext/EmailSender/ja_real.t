#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::More;
use utf8;

BEGIN {
    unless ( eval { require Email::Send::Test; 1 } ) {
        plan skip_all => 'These tests require Email::Send::Test to run.';
    }
}

my $count = 1;
my $tests = 29;
plan tests => $tests + 1;

use Socialtext::EmailSender::Factory;
use File::Copy ();
use File::Slurp ();
use File::Temp ();
use Encode qw(encode);
use URI::Escape ();

use_ok('Socialtext::EmailSender::Factory');

#$Socialtext::EmailSender::Base::SendClass = 'Test';

# Please put your test email-address in below.
my $to_email_address = 'devnull1@socialtext.com';

TO_IS_ASCII: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'TO_IS_ASCII',
       text_body => 'check the to-address.',
    );
    ok(1);
    $count++;
}

TO_IS_JAPANESE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => '日本人 <' . $to_email_address . '>',
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'TO_IS_JAPANESE',
       text_body => 'check the to-address.',
    );
    ok(1);
    $count++;
}


TO_IS_OVER_80_JAPANESE_SINGLE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => 'あいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこ <' . $to_email_address . '>',
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'TO_IS_OVER_80_JAPANESE_SINGLE',
       text_body => 'check the to-addresses',
    );
    ok(1);
    $count++;
}

TO_IS_OVER_80_JAPANESE_MULTI: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => 'あいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこ <' . $to_email_address . '>,' . '亜伊卯江尾亜伊卯江尾 <' . $to_email_address . '>',
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'TO_IS_OVER_80_JAPANESE_MULTI',
       text_body => 'check the to-addresses',
    );
    ok(1);
    $count++;
}


TO_IS_OVER_80_ASCII_SINGLE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => '0123456789012345678901234567890123456789012345678901234567890123456789 <' . $to_email_address . '>',
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'TO_IS_OVER_80_ASCII_SINGLE',
       text_body => 'check the to-addresses',
    );
    ok(1);
    $count++;
}

TO_IS_OVER_80_ASCII_MULTI: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => 'abcdefghijklmnopqrstuvxyz <' . $to_email_address . '>,' . 'zyxvutsrqponmlkjihgfedcba <' . $to_email_address . '>',
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'TO_IS_OVER_80_ASCII_MULTI',
       text_body => 'check the to-addresses',
    );
    ok(1);
    $count++;
}

my $test_address = 'devnull8@socialtext.com';

CC_IS_ASCII: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $test_address,
       cc        => $to_email_address,
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'CC_IS_ASCII',
       text_body => 'check the cc-address.',
    );
    ok(1);
    $count++;
}

CC_IS_JAPANESE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $test_address,
       cc        => '日本人 <' . $to_email_address . '>',
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'CC_IS_JAPANESE',
       text_body => 'check the cc-address.',
    );
    ok(1);
    $count++;
}



CC_IS_OVER_80_JAPANESE_SINGLE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $test_address,
       cc        => 'あいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこ <' . $to_email_address . '>',
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'CC_IS_OVER_80_JAPANESE_SINGLE',
       text_body => 'check the to-addresses',
    );
    ok(1);
    $count++;
}

CC_IS_OVER_80_JAPANESE_MULTI: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $test_address,
       cc        => 'あいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこ <' . $to_email_address . '>,' . '亜伊卯江尾亜伊卯江尾 <' . $to_email_address . '>',
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'CC_IS_OVER_80_JAPANESE_MULTI',
       text_body => 'check the to-addresses',
    );
    ok(1);
    $count++;
}


CC_IS_OVER_80_ASCII_SINGLE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $test_address,
       cc        => '0123456789012345678901234567890123456789012345678901234567890123456789 <' . $to_email_address . '>',
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'CC_IS_OVER_80_ASCII_SINGLE',
       text_body => 'check the to-addresses',
    );
    ok(1);
    $count++;
}

CC_IS_OVER_80_ASCII_MULTI: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $test_address,
       cc        => 'abcdefghijklmnopqrstuvxyz <' . $to_email_address . '>,' . 'zyxvutsrqponmlkjihgfedcba <' . $to_email_address . '>',
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'TO_IS_OVER_80_ASCII_MULTI',
       text_body => 'check the to-addresses',
    );
    ok(1);
    $count++;
}

FROM_IS_ASCII: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => $test_address,
       subject   => "[$count/$tests]" . 'FROM_IS_ASCII',
       text_body => 'test',
    );
    ok(1);
    $count++;
}

FROM_IS_JAPANESE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => '日本人 <test2@example.com>',
       subject   => "[$count/$tests]" . 'FROM_IS_JAPANESE',
       text_body => 'test',
    );
    ok(1);
    $count++;
}

FROM_IS_OVER_80_JAPANESE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => 'あいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこ <test@example.com>',
       subject   => "[$count/$tests]" . 'FROM_IS_OVER_80_JAPANESE',
       text_body => 'test',
    );
    ok(1);
    $count++;
}

TEXTBODY_IS_JAPANESE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'TEXTBODY_IS_JAPANESE',
       text_body => 'テキストボディ～終',
    );
    ok(1);
    $count++;
}

HTMLBODY_IS_JAPANESE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'HTMLBODY_IS_JAPANESE',
       html_body => '<a href="#">ＨＴＭＬボディ</a>',
    );
    ok(1);
    $count++;
}

SUBJECT_AND_BODY_IS_HANKAKU: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'HANKAKU_日本語ﾀｲﾄﾙ',
       text_body => 'ﾃｷｽﾄﾎﾞﾃﾞｨ～終',
    );
    ok(1);
    $count++;
}

my $tempdir = File::Temp::tempdir( CLEANUP => 1 );
my $hundred_k = "$tempdir/" . URI::Escape::uri_escape_utf8("１００ＫＢサイズ.txt");
open my $fh, '>', $hundred_k
    or die $!;
print $fh 'x' x ( 1024 * 100 )
    or die $!;
close $fh or die $!;

my $two_hundred_k = "$tempdir/" . URI::Escape::uri_escape_utf8("２００ＫＢサイズ.txt");
open $fh, '>', $two_hundred_k
    or die $!;
print $fh 'x' x ( 1024 * 200 )
    or die $!;
close $fh or die $!;

my $two_mb = "$tempdir/" . URI::Escape::uri_escape_utf8("２ＭＢサイズ.txt");

open $fh, '>', $two_mb
    or die $!;
print $fh 'x' x ( 1024 * 1024 * 2 )
    or die $!;
close $fh or die $!;

my $image = "$tempdir/" . URI::Escape::uri_escape_utf8("ソーシャルテキストのロゴ.gif");
#File::Copy::copy( 't/attachments/socialtext-logo-30.gif', $tempdir )
#    or die $!;
open $fh, '>', $image
    or die $!;
print $fh 'x' x ( 1024 * 10 )
    or die $!;
close $fh or die $!;


my $ppt = "$tempdir/" . URI::Escape::uri_escape_utf8("パワーポイント.ppt");
#File::Copy::copy( 't/attachments/indext.ppt', $tempdir )
#    or die $!;
open $fh, '>', $ppt
    or die $!;
print $fh 'x' x ( 1024 * 100 )
    or die $!;
close $fh or die $!;


#if(-f $hundred_k){ print "#hundred_k# $hundred_k\n"; }
#if(-f $image){ print "#image# $image\n"; }
#if(-f $ppt){ print "#ppt# $ppt\n"; }

ATTACHMENT_IS_JAPANESE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'ATTACHMENT_IS_JAPANESE',
       text_body => 'hello',
       attachments => [ $hundred_k ],
    );
    ok(1);
    $count++;
}

THREE_ATTACHMENT_IS_JAPANESE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'THREE_ATTACHMENT_IS_JAPANESE',
       text_body => 'check the attachments.',
       attachments => [ $hundred_k, $image, $ppt ],
    );
    ok(1);
    $count++;
}


TEXT_OVER_1000_ASCII: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'TEXT_OVER_1000_ASCII',
       text_body => '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789a',
   );
    ok(1);
    $count++;
}

TWO_TEXT_OVER_1000_ASCII: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'TWO_TEXT_OVER_1000_ASCII',
       text_body => "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789a" . "\n" . "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789a",
   );
    ok(1);
    $count++;
}

TEXT_OVER_1000_JAPANESE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'TEXT_OVER_1000_JAPANESE',
       text_body => "あいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこ～"
   );
    ok(1);
    $count++;
}

TWO_TEXT_OVER_1000_JAPANESE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'TWO_TEXT_OVER_1000_JAPANESE',
       text_body => "あいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこ～" . "\n" . "あいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこ～",
   );
    ok(1);
    $count++;
}

HTML_OVER_1000_ASCII: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'HTML_OVER_1000_ASCII',
       html_body => '<a href=#>0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789a</a>',
   );
    ok(1);
    $count++;
}

HTML_OVER_1000_JAPANESE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'HTML_OVER_1000_JAPANESE',
       html_body => "<p>あいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこあいうえおかきくけこ～</p>"
   );
    ok(1);
    $count++;
}

SUBJECT_IS_JAPANESE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . '日本語タイトル',
       text_body => 'hello',
    );

    ok(1);
    $count++;
}

SUBJECT_OVER_80_JAPANESE: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
       to        => $to_email_address,
       from      => 'test2@example.com',
       subject   => "[$count/$tests]" . 'あいうえおあいうえおあいうえおあいうえおあいうえおあいうえおあいうえおあいうえおあいうえおあいうえおあいうえおあいうえおあいうえおあいうえおあいうえおあいうえお終',
       text_body => 'check the subject',
   );
    ok(1);
    $count++;
}

SUBJECT_INCLUDE_EN_JA: {
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('ja');

    $email_sender->send(
        to        => $to_email_address,
        from      => 'test2@example.com',
        subject   => "[$count/$tests]" . 'helloこんにちは ～　こんにちは ～',
        text_body => 'SUBJECT_INCLUDE_EN_JA', 
    );
    ok(1);
    $count++;
}


