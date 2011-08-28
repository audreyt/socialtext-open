#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::More;

BEGIN {
    unless ( eval { require Email::Send::Test; 1 } ) {
        plan skip_all => 'These tests require Email::Send::Test to run.';
    }
}

plan tests => 41;

use Socialtext::EmailSender::Factory;
use File::Copy ();
use File::Slurp ();
use File::Temp ();

use_ok('Socialtext::EmailSender::Factory');

$Socialtext::EmailSender::Base::SendClass = 'Test';

{

    Email::Send::Test->clear();

    my $email_sender = Socialtext::EmailSender::Factory->create('en');

    $email_sender->send(
       to        => 'test1@example.com',
       from      => 'test2@example.com',
       subject   => 'test subject',
       text_body => 'small body',
    );
    my @emails = Email::Send::Test->emails();

    is( scalar @emails, 1, 'one email was sent' );

    is( $emails[0]->header('To'), 'test1@example.com',
        'check To header' );
    is( $emails[0]->header('From'), 'test2@example.com',
        'check From header' );
    is( $emails[0]->header('Subject'), 'test subject',
        'check Subject header' );
    is( $emails[0]->header('Content-Transfer-Encoding'), '8bit',
        'check Content-Transfer-Encoding header' );
    like( $emails[0]->header('Date'), qr/\d+ \w+ \d{4} \d\d:\d\d:\d\d/,
          'check Date header' );
    like( $emails[0]->header('X-Sender'), qr/Socialtext::EmailSender v.+/,
          'check Date header' );
    # N.B.: The Message-ID angle brackets aren't optional!
    # See RFC 2822, 3.6.4. -mml 20070504 (thx johnt)
    like( $emails[0]->header('Message-ID'), qr/^\<.*[^@]+\@[^@]+.*\>$/,
          'check Message-ID header' );
    like( $emails[0]->header('Content-Type'), qr{text/plain},
          'check Content-Type header' );
    like( $emails[0]->header('Content-Type'), qr{charset="UTF-8"},
          'check charset in Content-Type header' );
    is( $emails[0]->body(), 'small body',
        'check body' );
}

{
    Email::Send::Test->clear();

    my $email_sender = Socialtext::EmailSender::Factory->create('en');

    $email_sender->send(
       to        => [ 'test1@example.com', 'test2@example.com' ],
       subject   => 'test',
       text_body => 'small body',
    );

    my @emails = Email::Send::Test->emails();

    is( $emails[0]->header('To'), 'test1@example.com, test2@example.com',
        'check To header for multiple recipients' );
    like( $emails[0]->header('From'), qr/noreply\@socialtext\.com/,
          'check for default From header' );
}

{
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('en');

    $email_sender->send(
       to        => 'test1@example.com',
       cc        => 'test2@example.com',
       from      => 'test2@example.com',
       subject   => 'test',
       text_body => 'small body',
    );

    my @emails = Email::Send::Test->emails();

    is( $emails[0]->header('Cc'), 'test2@example.com',
        'check Cc header' );
}


{
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('en');

    $email_sender->send(
       to        => [ 'test1@example.com', 'test2@example.com' ],
       from      => 'test2@example.com',
       subject   => 'test',
       text_body => 'small body',
    );

    my @emails = Email::Send::Test->emails();

    is( $emails[0]->header('To'), 'test1@example.com, test2@example.com',
        'check To header for multiple recipients' );
}

{
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('en');

    $email_sender->send(
       to        => 'test1@example.com',
       subject   => 'test',
       html_body => '<a href="#">hello</a>',
    );

    my @emails = Email::Send::Test->emails();

    like( $emails[0]->header('Content-Type'), qr{text/html},
          'check Content-Type header is text/html' );
    like( $emails[0]->header('Content-Type'), qr{charset="UTF-8"},
          'check charset in Content-Type header' );
}

{
    Email::Send::Test->clear();
    binmode STDOUT, ':utf8';
    my $email_sender = Socialtext::EmailSender::Factory->create('en');

    my $subject = "utf-8 \x80 @! \x{5000}";
    $subject .= 'x x' x 30;

    $email_sender->send(
       to        => [ 'test1@example.com', 'test2@example.com' ],
       subject   => $subject,
       text_body => 'small body',
    );
    my @emails = Email::Send::Test->emails();
    is( $emails[0]->header('Subject'), $subject,
        'check Subject header which contains utf8 chars' );
}

{
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('en');

    $email_sender->send(
       to        => 'test1@example.com',
       subject   => 'test',
       text_body => 'hello',
       html_body => '<a href="#">hello</a>',
    );

    my @emails = Email::Send::Test->emails();
    like( $emails[0]->header('Content-Type'), qr{multipart/alternative},
          'check Content-Type header is multipart/alternative' );

    my @parts = $emails[0]->parts;
    like( $parts[0]->header('Content-Type'), qr{text/plain},
          'first part is text/plain' );
    like( $parts[1]->header('Content-Type'), qr{text/html},
          'second part is text/html' );
    is( $parts[0]->header('Content-Disposition'), 'inline',
        'first part Content-Disposition is inline' );
    is( $parts[1]->header('Content-Disposition'), 'inline',
        'second part Content-Disposition is inline' );
}

my $tempdir = File::Temp::tempdir( CLEANUP => 1 );
my $hundred_k = "$tempdir/hundred_k.txt";
open my $fh, '>', $hundred_k
    or die $!;
print $fh 'x' x ( 1024 * 100 )
    or die $!;
close $fh or die $!;

my $two_mb = "$tempdir/two_mb.txt";
open $fh, '>', $two_mb
    or die $!;
print $fh 'x' x ( 1024 * 1024 * 2 )
    or die $!;
close $fh or die $!;

my $four_mb = "$tempdir/four_mb.txt";
open $fh, '>', "$tempdir/four_mb.txt"
    or die $!;
print $fh 'x' x ( 1024 * 1024 * 4 )
    or die $!;
close $fh or die $!;

my $image = "$tempdir/socialtext-logo-30.gif";
File::Copy::copy( 't/attachments/socialtext-logo-30.gif', $tempdir )
    or die $!;

{
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('en');

    $email_sender->send(
       to          => 'test1@example.com',
       subject     => 'test',
       text_body   => 'hello',
       attachments => [ $hundred_k, $two_mb, $four_mb, $image ],
    );

    my @emails = Email::Send::Test->emails();
    like( $emails[0]->header('Content-Type'), qr{^multipart/mixed},
          'Content-Type is multipart/mixed when we have attachments' );

    my @parts = $emails[0]->parts;
    my @att = @parts[1..$#parts];

    is( scalar @att, 3, 'three attachments' );
    like( $att[0]->header('Content-Type'), qr{text/plain},
          'Content-Type for first attachment' );
    like( $att[1]->header('Content-Type'), qr{text/plain},
          'Content-Type for second attachment' );
    like( $att[2]->header('Content-Type'), qr{image/gif},
          'Content-Type for third attachment' );

    is( $att[2]->body, File::Slurp::read_file($image),
        'image in attachment matches original' );

    ok( ( ! grep { $_->filename eq 'four_mb.txt' } @att ),
        'four_mb.txt was not included in attachments' );
}

{
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('en');

    $email_sender->send(
       to          => 'test1@example.com',
       subject     => 'test',
       text_body   => 'hello',
       attachments => [ $two_mb, $four_mb ],
       max_size    => 0,
    );

    my @emails = Email::Send::Test->emails();
    my @parts = $emails[0]->parts;
    my @att = @parts[1..$#parts];

    is( scalar @att, 2, 'two attachments' );
}

{
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('en');

    $email_sender->send(
       to          => 'test1@example.com',
       subject     => 'test',
       text_body   => 'hello',
       html_body   => '<b>hello</b>',
       attachments => [ $hundred_k ],
    );

    my @emails = Email::Send::Test->emails();
    like( $emails[0]->header('Content-Type'), qr{^multipart/mixed},
          'text + html + attachments Content-Type is multipart/mixed' );

    my @parts = $emails[0]->parts;
    like( $parts[0]->header('Content-Type'), qr{^multipart/alternative},
          'first part Content-Type is multipart/alternative' );

    my @subparts = $parts[0]->parts;
    like( $subparts[0]->header('Content-Type'), qr{^text/plain},
          'first subpart of mp/alt part Content-Type is text/plain' );
    like( $subparts[1]->header('Content-Type'), qr{^text/html},
          'second subpart of mp/alt part Content-Type is text/html' );

    my @att = @parts[1..$#parts];

    is( scalar @att, 1, 'one attachment' );
}

{
    Email::Send::Test->clear();
    my $email_sender = Socialtext::EmailSender::Factory->create('en');

    $email_sender->send(
       to          => 'test1@example.com',
       subject     => 'test',
       html_body   => 'has an image <img src="cid:socialtext-logo-30.gif" />',
       attachments => [ $image ],
    );

    my @emails = Email::Send::Test->emails();
    like( $emails[0]->header('Content-Type'), qr{^multipart/related},
          'html + image attachment & img tag in source Content-Type is multipart/related' );
    like( $emails[0]->header('Content-Type'), qr{type="text/html"},
          'html + image attachment & img tag in source Content-Type specifies first related part type as text/html' );

    my @parts = $emails[0]->parts;
    like( $parts[0]->header('Content-Type'), qr{^text/html},
          'first part Content-Type is text/html' );
    like( $parts[1]->header('Content-Type'), qr{^image/gif},
          'second part Content-Type is image/gif' );
}
