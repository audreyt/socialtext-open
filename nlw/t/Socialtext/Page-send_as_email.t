#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext;
use IO::File;
fixtures( 'admin', 'foobar' );

BEGIN {
    unless ( eval { require Email::Send::Test; 1 } ) {
        plan skip_all => 'These tests require Email::Send::Test to run.';
    }
}

use Socialtext::Page;

plan tests => 58;

$Socialtext::EmailSender::Base::SendClass = 'Test';

my $hub   = new_hub('admin');
my $pages = $hub->pages;

my $junk = q(!@#$%^&*()[]{}\\|'");
my $utf8_subject = Encode::decode_utf8("Groß Send ($junk) Email Test $$");

Socialtext::Page->new(hub => $hub)->create(
    title   => $utf8_subject,
    content => <<'EOF',
    _Back to [Help]._

In Socialtext, categories help you identify information so it can be found later on. Every page can have any number of categories. Pages can have many categories, and categories can overlap. Categories appear underneath the page name.

> *NOTE* All workspace blog names are also category names. Assigning a blog as a category publishes the page to that blog.

> *View all categories.* Select *"Categories"* from the top menu.  You will see an alphabetical list of all of the defined categories.  Clicking on any category will show a list of pages in that category.

[WikiLink]
{link: foobar [InterWikiLink]}

{image: socialtext-logo.gif}
{file: socialtext-logo.gif}
EOF
    creator => $hub->current_user,
);

{
    Email::Send::Test->clear;

    my $page = $pages->new_from_name($utf8_subject);

    open my $fh, '<', 't/attachments/socialtext-logo-30.gif'
        or die $!;

    my $attachment = $hub->attachments->create(
        fh => $fh,
        content_type => 'image/gif',
        filename => 'socialtext-logo.gif',
        page => $page,
        user => $hub->current_user,
    );
    ok $attachment, 'created attachment';

    $page->send_as_email(
        from => 'devnull1@socialtext.com',
        to   => 'devnull2@socialtext.com',
        include_attachments => 1,
    );

    my @emails = Email::Send::Test->emails;

    is( scalar @emails, 1, 'one email was sent' );

    my @parts = $emails[0]->parts;
    is( scalar @parts, 2, 'email has two parts' );
    my ($message,$att) = @parts;

    check_attachment_part($att);

    my @msg_parts = $message->parts;
    is( scalar @msg_parts, 2, 'mp/related has two parts' );
    my $wiki = $msg_parts[0];
    my $html = $msg_parts[1];

    diag "checking wikitext";
    like $wiki->header('Content-Type'), qr{^text/plain}, '... type';
    is $wiki->header('Content-Disposition'), 'inline', '... disposition';
    like $wiki->body, qr{WikiLink}, '... body';

    my ($msg,$logo) = $html->parts;

    diag "checking html message";
    like $msg->header('Content-Type'), qr{^text/html}, '... type';
    is $msg->header('Content-Disposition'), 'inline', '... disposition';
    like $msg->body, qr{;page_name=WikiLink}, '... body';
    like $msg->body, qr{href="cid:socialtext-logo.gif"}, '... a ctag';
    like $msg->body, qr{src="cid:socialtext-logo.gif"}, '... img ctag';

    check_attachment_part($logo);
}

{
    Email::Send::Test->clear;

    my $page = $pages->new_from_name($utf8_subject);
    $pages->current($page);

    my $buncha_recipients = join ', ', map { "frog$_\@sharpsaw.org" } (0..10);
    $page->send_as_email(
        from => 'devnull1@socialtext.com',
        to   => $buncha_recipients,
    );

    my @emails = Email::Send::Test->emails;

    is( scalar @emails, 1,
        'one email was sent' );
    is( $emails[0]->header('From'), 'devnull1@socialtext.com',
        'email is from correct sender' );
    is( $emails[0]->header('To'), $buncha_recipients,
        'email is addressed to proper recipients' );

    is( $emails[0]->header('Subject'), $utf8_subject,
        "subject is $utf8_subject" );
    like( $emails[0]->header('Content-Type'), qr{multipart/alternative},
        'content type is multipart/alternative' );

    my @parts = $emails[0]->parts;
    is( scalar @parts, 2,
        'email has two parts' );
    like( $parts[0]->content_type, qr{text/plain;},
        q{first part content type is 'text/plain;'} );
    is( $parts[1]->content_type, 'text/html; charset="UTF-8"',
        q{second part content type is 'text/html; charset="UTF-8"'} );

    like( $parts[0]->body, qr/In Socialtext, categories help you identify information/,
          'check plain body - 1' );
    like( $parts[0]->body, qr/\Q*NOTE*\E/,
          'check plain body - 2' );
    like( $parts[0]->body, qr/\n> \*View[^\n]+\n> will[^\n]+\n> Clicking/s,
          'check that plain text version was reformatted to 72 chars per line' );

    like( $parts[1]->body, qr/In Socialtext, categories help you identify information/,
        'check html body - 1' );
    like( $parts[1]->body, qr{\Q<strong>NOTE</strong>\E},
        'check html body - 2' );

    my $server_root = qr{https?://[-\w\.:]+\w+};
    like( $parts[1]->body, qr{href="$server_root/admin/\?[^"]+page_name=WikiLink"},
        'check wiki link in html body' );
    like( $parts[1]->body, qr{href="$server_root/\Qfoobar/InterWikiLink"},
        'check inter-wiki link in html body' );
}

{
    Email::Send::Test->clear;

    my $page = $pages->new_from_name($utf8_subject);
    $pages->current($page);

    $page->send_as_email( from => 'devnull1@socialtext.com',
                          to   => 'devnull2@socialtext.com',
                          subject => 'Subject Override',
                        );

    my @emails = Email::Send::Test->emails;

    is( scalar @emails, 1,
        'one email was sent' );
    is( $emails[0]->header('Subject'), 'Subject Override',
        'subject is Subject Override' );
}

{
    Email::Send::Test->clear;

    my $page = $pages->new_from_name($utf8_subject);
    $pages->current($page);

    $page->send_as_email
        ( from => 'devnull1@socialtext.com',
          to   => [ 'devnull2@socialtext.com', 'devnull3@socialtext.com' ],
        );

    my @emails = Email::Send::Test->emails;

    is( scalar @emails, 1,
        'one email was sent' );

    like( $emails[0]->header('To'), qr/devnull2\@socialtext\.com/,
        'devnull2@socialtext.com is in recipient list' );
    like( $emails[0]->header('To'), qr/devnull3\@socialtext\.com/,
        'devnull3@socialtext.com is in recipient list' );
}

send_copy: {
    Email::Send::Test->clear;

    my $page = $pages->new_from_name($utf8_subject);
    $pages->current($page);

    $page->send_as_email
        ( from => 'devnull1@socialtext.com',
          to   => [ 'devnull2@socialtext.com', 'devnull3@socialtext.com' ],
          send_copy => 1
        );

    my @emails = Email::Send::Test->emails;

    is( scalar @emails, 1,
        'one email was sent' );

    like( $emails[0]->header('To'), qr/devnull2\@socialtext\.com/,
        'devnull2@socialtext.com is in recipient list' );
    like( $emails[0]->header('To'), qr/devnull3\@socialtext\.com/,
        'devnull3@socialtext.com is in recipient list' );
    like( $emails[0]->header('To'), qr/devnull1\@socialtext\.com/,
        'devnull1@socialtext.com is in recipient list' );
}

send_copy_one_receiver: {
    Email::Send::Test->clear;

    my $page = $pages->new_from_name($utf8_subject);
    $pages->current($page);

    $page->send_as_email
        ( from => 'devnull1@socialtext.com',
          to   => 'devnull2@socialtext.com',
          send_copy => 1
        );

    my @emails = Email::Send::Test->emails;

    is( scalar @emails, 1,
        'one email was sent' );

    like( $emails[0]->header('To'), qr/devnull2\@socialtext\.com/,
        'devnull2@socialtext.com is in recipient list' );
    like( $emails[0]->header('To'), qr/devnull1\@socialtext\.com/,
        'devnull1@socialtext.com is in recipient list' );
}

send_copy_duplicate_copy: {
    Email::Send::Test->clear;

    my $page = $pages->new_from_name($utf8_subject);
    $pages->current($page);

    $page->send_as_email
        ( from => 'devnull1@socialtext.com',
          to   => [ 'devnull2@socialtext.com', 'devnull1@socialtext.com' ],
          send_copy => 1
        );

    my @emails = Email::Send::Test->emails;

    is( scalar @emails, 1,
        'one email was sent' );

    like( $emails[0]->header('To'), qr/devnull2\@socialtext\.com/,
        'devnull2@socialtext.com is in recipient list' );
    like( $emails[0]->header('To'), qr/devnull1\@socialtext\.com/,
        'devnull1@socialtext.com is in recipient list' );
    unlike( $emails[0]->header('To'), qr/devnull1.*devnull1/,
        'devnull1@socialtext.com appears once in recipient list' );
}


{
    Email::Send::Test->clear;

    my $page = $pages->new_from_name($utf8_subject);
    $pages->current($page);

    $page->send_as_email
        ( from => 'devnull1@socialtext.com',
          to   => 'devnull2@socialtext.com',
          body_intro => "Some extra text up front, can have *wiki formatting*\n",
        );
    my @emails = Email::Send::Test->emails;

    is( scalar @emails, 1,
        'one email was sent' );

    my @parts = $emails[0]->parts;
    is( scalar @parts, 2,
        'email has two parts' );

    like( $parts[0]->body, qr/\QSome extra text up front, can have *wiki formatting*\E/,
        'check plain body intro' );
    like( $parts[1]->body,
          qr{Some extra text up front, can have <strong>wiki formatting</strong>},
          'check html body intro' );
}

{
    Email::Send::Test->clear;

    my $page = $pages->new_from_name($utf8_subject);
    $pages->current($page);

    $page->send_as_email
        ( from => 'devnull1@socialtext.com',
          to   => 'devnull1@socialtext.com',
          cc   => 'devnull2@socialtext.com',
        );

    my @emails = Email::Send::Test->emails;

    is( scalar @emails, 1,
        'one email was sent' );
    is( $emails[0]->header('Cc'), 'devnull2@socialtext.com',
        'email is addressed to proper recipient in cc' );
}

{
    Email::Send::Test->clear;

    Socialtext::Page->new(hub => $hub)->create(
        title   => 'Has Table',
        content => <<'EOF',

In Socialtext, categories help you identify information so it can be found later on. Every page can have any number of categories. Pages can have many categories, and categories can overlap. Categories appear underneath the page name.

| This | Is | A | Table |
| Do   | Not | F It | Up |

EOF
        creator => $hub->current_user,
    );

    my $page = $pages->new_from_name('Has Table');
    $pages->current($page);

    $page->send_as_email(
        from => 'devnull1@socialtext.com',
        to   => 'devnull1@socialtext.com',,
    );

    my @emails = Email::Send::Test->emails;

    is( scalar @emails, 1,
        'one email was sent' );

    my $text = ($emails[0]->parts())[0]->body();

    unlike( $text, qr/^.{80,}/m, 'no lines longer than 79 characters' );
    
    like( $text, qr/\Q| This | Is | A | Table |\E\n\Q| Do   | Not | F It | Up |\E/,
          'the table in the page was not reformatted.' );
}

exit;

sub check_attachment_part {
    my $part = shift;

    diag 'checking attachment part';
    is $part->header('Content-Type'), 'image/gif', "... type";
    is $part->header('Content-Transfer-Encoding'), 'base64', '... encoding';
    is $part->header('Content-Disposition'),
        'attachment; filename="socialtext-logo.gif"', '... disposition';
}

