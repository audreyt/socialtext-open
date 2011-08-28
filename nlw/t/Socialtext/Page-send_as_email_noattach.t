#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext;
fixtures( 'admin', 'foobar' );

BEGIN {
    unless ( eval { require Email::Send::Test; 1 } ) {
        plan skip_all => 'These tests require Email::Send::Test to run.';
    }
}

use Socialtext::Page;

plan tests => 6;

$Socialtext::EmailSender::Base::SendClass = 'Test';

my $hub   = new_hub('admin');
my $pages = $hub->pages;

my $junk = q(!@#$%^&*()[]{}\\|'");
my $utf8_subject = Encode::decode_utf8("Groß Send ($junk) Email Test");

Socialtext::Page->new(hub => $hub)->create(
    title   => $utf8_subject,
    content => <<'EOF',
    _Back to [Help]._

In Socialtext, categories help you identify information so it can be found later on. Every page can have any number of categories. Pages can have many categories, and categories can overlap. Categories appear underneath the page name.

> *NOTE* All workspace blog names are also category names. Assigning a blog as a category publishes the page to that blog.

> *View all categories.* Select *"Categories"* from the top menu.  You will see an alphabetical list of all of the defined categories.  Clicking on any category will show a list of pages in that category.

[WikiLink]
{link: foobar [InterWikiLink]}

{file: socialtext-logo.gif}
{image: socialtext-logo.gif}
EOF
    creator => $hub->current_user,
);

{
    Email::Send::Test->clear;

    my $page = $pages->new_from_name($utf8_subject);
    my $attachment = $hub->attachments->create(
        page => $page,
        filename => 'socialtext-logo.gif',
        fh => 't/attachments/socialtext-logo-30.gif',
    );

    $page->send_as_email
        ( from => 'devnull1@socialtext.com',
          to   => 'devnull2@socialtext.com',
          include_attachments => 0,
        );

    my @emails = Email::Send::Test->emails;

    is( scalar @emails, 1,
        'one email was sent' );

    my @parts = $emails[0]->parts;
    is( scalar @parts, 2,
        'email has two parts' );
    like( $parts[0]->content_type, qr{text/plain;},
        q{first part content type is 'text/plain;'} );
    is( $parts[1]->content_type, 'text/html; charset="UTF-8"',
        q{second part content type is 'text/html; charset="UTF-8"'} );

    like( $parts[1]->body, qr/<img[^>]*src="http/, "The image link is a http link, not cid link");
    like( $parts[1]->body, qr/<a[^>]*href="http[^>]*>socialtext-logo.gif/, "The file link is a http link, not cid link");
}
