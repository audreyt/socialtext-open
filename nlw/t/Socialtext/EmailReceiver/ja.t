#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 251;
use Socialtext::Account;
use Socialtext::Workspace;

use_ok('Socialtext::EmailReceiver::Factory');

###############################################################################
# Fixtures: empty
# - need *some* Workspace, so the "devnull1" User has been created
fixtures(qw( empty ));

my $test_locale = 'ja';
my $wksp = Socialtext::Workspace->create(
    name => "ja$$",
    title => "Ja$$",
    account_id => Socialtext::Account->Default->account_id,
    skip_default_pages => 1,
);
my $wksp_name = $wksp->name;
my $hub = new_hub($wksp_name);
isa_ok( $hub, 'Socialtext::Hub' );
$wksp->add_user( user => $hub->current_user );

RECEIVE_STRING_SIMPLE: {
    my $file = 't/test-data/email/EmailReceiver';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";
    my $email = do { local $/ = undef; <$fh> };

    allow_guest_email_in($wksp);

    receive_ok(string => $email);

    tests_for_email();

    my $user = Socialtext::User->new( email_address => 'williams@tni.com' );
    isa_ok( $user, 'Socialtext::User',
        'A new user was created because of an accepted email' );

    my $page = $hub->pages->new_from_name('[monkey] CVS monkey and ape2');
    isa_ok( $page, 'Socialtext::Page' );
    $page->purge();

    remove_guest_email_in($wksp);
}

RECEIVE_HANDLE_SIMPLE: {
    my $file = 't/test-data/email/EmailReceiver';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    allow_guest_email_in($wksp);

    receive_ok( handle => $fh );

    tests_for_email();

    remove_guest_email_in($wksp);
}

sub tests_for_email {
    my $page = $hub->pages()->new_from_name('[monkey] CVS monkey and ape2');
    isa_ok( $page, 'Socialtext::Page' );

    ok( $page->active(), "Found a page with the name '[monkey] CVS monkey and ape2'" );
    is( $page->title(), '[monkey] CVS monkey and ape2',
        'check that page title matches subject' );
    like( $page->content(), qr{From:\s+"John Williams"\s+<mailto:williams\@tni.com>},
          'content includes email sender name & address' );
    like( $page->content(), qr{Date:\s+\QWed, 15 Sep 2004 13:32:14 -0600 (MDT)\E},
          'content includes date from email headers' );
    like( $page->content(), qr{API changed},
          'content includes string "API changed"' );

    my $categories = $page->tags;
    ok( scalar @$categories, 'page has tags' );
    is_deeply( [ sort @$categories ],
               [ 'Email', 'ape', 'monkey' ],
               'categories are ape, Email, & monkey' );

    my $attachments = $page->hub()->attachments()->all( page_id => $page->id );
    is( @$attachments, 0,
        'an email without attachments generates a page without attachments' );
}

WS_INCOMING_EMAIL_PLACEMENT_REPLACE: {
    $wksp->update( incoming_email_placement => 'replace' );

    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name\@example.com
Subject: Start Here

This replaces the start here page.
EOF
    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('Start Here');
    isa_ok( $page, 'Socialtext::Page' );
    like( $page->content(), qr/\QThis replaces the start here page.\E/,
          'page contains content from email' );
    unlike( $page->content(), qr/quick tour/,
            'page does not contain content not from email' );
}

WS_INCOMING_EMAIL_PLACEMENT_TOP: {
    $wksp->update( incoming_email_placement => 'top' );

    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name\@example.com
Subject: Start Here

This goes at the top.
EOF
    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('Start Here');
    like( $page->content(),
          qr/\QThis goes at the top.\E
             \s+---\s+
             .+? # email header bits
             \QThis replaces the start here page.\E/xs,
          'page contains content from email, appended to the top' );
}


WS_INCOMING_EMAIL_PLACEMENT_BOTTOM: {
    $wksp->update( incoming_email_placement => 'bottom' );

    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name\@example.com
Subject: Start Here

This goes at the bottom.
EOF

    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('Start Here');
    isa_ok( $page, 'Socialtext::Page' );
    like( $page->content(),
          qr/\QThis goes at the top.\E
             \s+---\s+
             .+? # email header bits
             \QThis replaces the start here page.\E
             \s+---\s+
             .+? # email header bits
             \QThis goes at the bottom.\E/xs,
          'page contains content from email, appended to the bottom' );
}

OVERRIDE_PLACEMENT_REPLACE: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name\@example.com
Subject: Start Here

Replace: 1

This replaces the existing text.
EOF

    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('Start Here');
    isa_ok( $page, 'Socialtext::Page' );
    like( $page->content(), qr/\QThis replaces the existing text.\E/,
          'new text is in page content' );
    unlike( $page->content(), qr/\QReplace: 1\E/,
            'page content does not include replace command' );
    unlike( $page->content(), qr/\QThis goes at the top.\E/,
            'page does not include old content' );
}

OVERRIDE_PLACEMENT_TOP: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name\@example.com
Subject: Start Here

Append: Top

And this goes at the top.
EOF
    
    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('Start Here');
    isa_ok( $page, 'Socialtext::Page' );
    like( $page->content(),
          qr/\QAnd this goes at the top.\E
             \s+---\s+
             .+? # email header bits
             \QThis replaces the existing text.\E/xs,
          'new content is appended to top of page' );
    unlike( $page->content(), qr/\QAppend: Top\E/,
            'page content does not include replace command' );
}

CATEGORY_IN_TO_ADDRESS: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name+New=20Cat\@example.com
Subject: In New Cat

Blah blah
EOF

    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('In New Cat');
    isa_ok( $page, 'Socialtext::Page' );
    is_deeply(
        [ sort @{ $page->tags } ],
        [ 'Email', 'New Cat' ],
        'page is in Email and New Cat categories'
    );
}

CATEGORY_IN_CC_ADDRESS: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: bubba\@example.com
Cc: $wksp_name+New=20Cat2\@example.com
Subject: In New Cat2

Blah blah
EOF

    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('In New Cat2');
    isa_ok( $page, 'Socialtext::Page' );
    is_deeply(
        [ sort @{ $page->tags } ],
        [ 'Email', 'New Cat2' ],
        'page is in Email and New Cat2 categories'
    );
}

CATEGORY_IN_ADDRESS_WITH_DOT: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: bubba\@example.com
Cc: $wksp_name.New=20Cat3\@example.com
Subject: In New Cat3

Blah blah
EOF

    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('In New Cat3');
    isa_ok( $page, 'Socialtext::Page' );
    is_deeply(
        [ sort @{ $page->tags } ],
        [ 'Email', 'New Cat3' ],
        'page is in Email and New Cat3 categories'
    );
}

CATEGORY_IN_ADDRESS_UTF8: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name+=E6=96=B0=E5=8A=A0=E5=9D=A1_Blog\@test.socialtext.com
Subject: utf8 category

Blah blah
EOF

    receive_ok( string => $email );

    my $singapore = join '', map { chr($_) } 26032, 21152, 22369;
    my $singapore_category = "$singapore Blog";

    my $page = $hub->pages()->new_from_name('utf8 category');
    isa_ok( $page, 'Socialtext::Page' );
    is_deeply(
        [ sort @{ $page->tags } ],
        [ 'Email', $singapore_category ],
        'page is in Email and {Singapore Blog} categories'
    );

}

CATEGORY_IN_TO_ADDRESS_WS_MIXED_CASE: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name+New=20Cat\@example.com
Subject: mixed case ws name

Blah blah
EOF

    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('mixed case ws name');
    isa_ok( $page, 'Socialtext::Page' );
    is_deeply(
        [ sort @{ $page->tags } ],
        [ 'Email', 'New Cat' ],
        'mixed case ws name - page is in Email and New Cat categories'
    );
}

CATEGORY_COMMANDS: {
    # This tests several aspects - multiple Category commands,
    # multiple categories in one command, and case-insensitivity for
    # command names
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name\@example.com
Subject: Cats in Body

Category: Cat1
Category: Cat2, Cat4
category: Cat3

Blah blah
EOF

    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('Cats in Body');
    isa_ok( $page, 'Socialtext::Page' );
    is_deeply(
        [ sort @{ $page->tags } ],
        [ 'Cat1', 'Cat2', 'Cat3', 'Cat4', 'Email' ],
        'page is in Cat1, Cat2, Cat3, Cat4 & Email categories'
    );

    unlike( $page->content(), qr/Category:/,
            'category commands are not in the page body' );
}

TAG_COMMANDS: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name\@example.com
Subject: Tags in Body

Tag: Cat1
Tag: Cat2, Cat4
tag: Cat3

Blah blah
EOF

    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('Tags in Body');
    is_deeply(
        [ sort @{ $page->tags } ],
        [ 'Cat1', 'Cat2', 'Cat3', 'Cat4', 'Email' ],
        'page is in Cat1, Cat2, Cat3, Cat4 & Email categories'
    );

    unlike( $page->content(), qr/tag:/,
            'category commands are not in the page body' );
}

CATEGORY_COMMAND_NO_BLANK_LINES: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name\@example.com
Subject: Cats in Body2

Category: Cat1
Blah blah
EOF

    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('Cats in Body2');
    isa_ok( $page, 'Socialtext::Page' );
    is_deeply(
        [ sort @{ $page->tags } ],
        [ 'Cat1', 'Email' ],
        'page is in Cat1 & Email categories'
    );

    unlike( $page->content(), qr/Category:/,
            'category commands are not in the page body' );
    like( $page->content(), qr/Blah blah/,
          'non-command content is in page' );
}

# REVIEW - the emails being tested here have interesting flowed bodies
# but I'm not sure what exactly to test for in the content.
BAD_FLOWED_CATEGORIES: {
    my %tests = (
        '1' => [ 'Email', 'Test1' ],
        '2' => [ 'Email', 'Test1', 'Test2' ],
        '3' => [ 'Email', 'Testing webmail' ],
    );

    for my $num ( sort keys %tests ) {
        my $file = 't/test-data/email/bad-format-flowed-category-' . $num ;
        open my $fh, '<', $file
            or die "Cannot read $file: $!";

        receive_ok( handle => $fh );

        my $page = $hub->pages()->new_from_name("Bad Format=Flowed Category $num");
        isa_ok( $page, 'Socialtext::Page' );
        is_deeply(
            [ sort @{ $page->tags } ],
            $tests{$num},
            "bad flowed $num is in correct categories"
        );
    }
}

ONE_ATTACHMENT: {
    my $file = 't/test-data/email/one-attachment';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    receive_ok( handle => $fh );

    my $page = $hub->pages()->new_from_name('attachments');
    isa_ok( $page, 'Socialtext::Page' );

    ok( $page->active(), 'Found a page with the name of "attachments"' );
    is( $page->title(), 'attachments',
        'check that page title matches subject' );

    my $attachments
        = $page->hub()->attachments()->all( page_id => $page->id );
    is( @$attachments, 1, 'page generated from email has one attachment' );

    like( $page->content(), qr/\Q{file: http-recorder}\E/,
          'check that page content contains link to attached file' );

    my $all = $hub->attachments->all_attachments_in_workspace();
    is( @$all, 1,
        'only one attachment in workspace' );

    $page->purge();
}

ATTACHMENT_DF_CHECK: {
    my $file = 't/test-data/email/one-attachment';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    no warnings 'redefine', 'once';
    local *Filesys::DfPortable::dfportable = sub { return { bavail => 5 } };

    receive_ok( handle => $fh );

    my $page = $hub->pages()->new_from_name('attachments');
    isa_ok( $page, 'Socialtext::Page' );

    ok( $page->active(), "Found a page with the name of 'attachments'" );
    is( $page->title(), 'attachments',
        'check that page title matches subject' );

    my $attachments
        = $page->hub()->attachments()->all( page_id => $page->id );
    is( @$attachments, 0, 'page generated from email has no attachments' );
}

ATTACHED_IMAGE: {
    my $file = 't/test-data/email/attached-image';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    receive_ok( handle => $fh );

    my $page = $hub->pages()->new_from_name('Attached Image');
    isa_ok( $page, 'Socialtext::Page' );

    ok( $page->active(), "Found a page with the name of 'Attached Image'" );
    is( $page->title(), 'Attached Image',
        'check that page title matches subject' );

    my $attachments
        = $page->hub()->attachments()->all( page_id => $page->id );
    is( @$attachments, 1, 'page generated from email has one attachment' );

    like( $page->content(), qr/\Q{image: alevinphotoedit.jpg}\E/,
          'check that page content contains image link to attached image' );
}

NESTED_MULTIPART_ATTACHMENT: {
    # This email's structure looks like this:
    #
    # multipart/alternative
    #  |
    #  |-- text/plain
    #  |
    #  |-- multipart/related
    #      |
    #      |-- text/html
    #      |
    #      |-- image/jpeg
    #
    # Based on this, we expect to toss save the HTML piece and image
    # as attachments, but use the text body for the page content.
    my $file = 't/test-data/email/nested-multipart-with-attachment';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    receive_ok( handle => $fh );

    my $subject = 'Nested Multipart with Attachment';

    my $page = $hub->pages()->new_from_name($subject);
    isa_ok( $page, 'Socialtext::Page' );

    ok( $page->active(), "Found a page with the name of '$subject'" );
    is( $page->title(), $subject, 'check that page title matches subject' );

    my @attachments = sort { $a->mime_type() cmp $b->mime_type() }
        @{ $page->hub()->attachments()->all( page_id => $page->id ) };
    is( @attachments, 2, 'page generated from email has two attachments' );

    my $img = $attachments[0];
    is( $img->mime_type(), 'image/jpeg', 'image mime_type' );
    ok( $img->content(), 'image is not empty' );

    my $html = $attachments[1];
    is( $html->mime_type(), 'text/html', 'html mime_type' );
    ok( $html->content(), 'html is not empty' );
}

BIG5_IN_BODY: {
    my $file = 't/test-data/email/big5';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    receive_ok( handle => $fh );

    my $page = $hub->pages()->new_from_name('bIG5 eMAIL');
    isa_ok( $page, 'Socialtext::Page' );

    ok( $page->active(), "Found a page with the name of 'Big5 Email'" );
    is( $page->title(), 'Big5 email',
        'check that page title matches subject in mail' );

    my $singapore = join '', map { chr($_) } 26032, 21152, 22369;

    like( $page->content, qr/$singapore/,
          'check that page content contains UTF-8 encoded chinese for Singapore.' );
}

TEXT_HTML_BODY_ONLY: {
    my $file = 't/test-data/email/text-html-body';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    receive_ok( handle => $fh );

    my $page = $hub->pages()->new_from_name('Text/HTML Body');
    isa_ok( $page, 'Socialtext::Page' );

    ok( $page->active(), 'Found a page with the name of "Text/HTML Body"' );
    is( $page->title(), 'Text/HTML Body', 'title matches subject' );

    like( $page->content(),
          qr{\*Some bold text\*},
          'page contains expected HTML content as wikitext' );

    my $attachments = $page->hub()->attachments()->all( page_id => $page->id );
    is( @$attachments, 1,
        'when using html body, it is also saved as an attachment' );

    is( $attachments->[0]->mime_type(), 'text/html', 'attachment type is text/html' );
    ok( $attachments->[0]->content(), 'html attachment has some content' );

    unlike( $page->content(), qr/{file: .+}/,
            'saving HTML body as an attachment does not create a file wafl in the body' );
}

MP_ALT_PREFER_PLAIN: {
    my $file = 't/test-data/email/mp-alt-plain-html';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    receive_ok( handle => $fh );

    my $page = $hub->pages()->new_from_name('MP Alt');
    isa_ok( $page, 'Socialtext::Page' );

    ok( $page->active(), "Found a page with the name of 'MP Alt'" );

    like( $page->content(),
          qr{\Q1. one\E\n
             \Q2. two\E\n
             \Q3. three\E\n
             \s+
             \Qorange!\E
            }xs,
          'page contains expected plaintext content' );

    my $attachments = $page->hub()->attachments()->all( page_id => $page->id );
    is( @$attachments, 1,
        'when using plain body, html body is saved as an attachment' );

    is( $attachments->[0]->mime_type(), 'text/html', 'attachment type is text/html' );
    ok( $attachments->[0]->content(), 'html attachment has some content' );

    $page->purge();
}

MP_ALT_PREFER_HTML: {
    my $file = 't/test-data/email/mp-alt-plain-html';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    $wksp->update( prefers_incoming_html_email => 1 );

    receive_ok( handle => $fh );

    my $page = $hub->pages()->new_from_name('MP Alt');
    isa_ok( $page, 'Socialtext::Page' );

    ok( $page->active(), "Found a page with the name of 'MP Alt'" );

    like( $page->content(),
          qr{\#\ one\n
             \#\ two\n
             \#\ three\n
            }xs,
          'page contains expected HTML content as wikitext' );

    my $attachments = $page->hub()->attachments()->all( page_id => $page->id );
    is( @$attachments, 1,
        'when using html body, it is also saved as an attachment' );

    is( $attachments->[0]->mime_type(), 'text/html', 'attachment type is text/html' );
    ok( $attachments->[0]->content(), 'html attachment has some content' );

    unlike( $page->content(), qr/{file: .+}/,
            'saving HTML body as an attachment does not create a file wafl in the body' );

    $page->purge();

    $wksp->update( prefers_incoming_html_email => 0 );
}

# This is included because in QA we found that this email generated a
# page with screwed up wikitext and 3 attachments, not one.
GMAIL_HTML_MAIL: {
    my $file = 't/test-data/email/gmail';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    $wksp->update( prefers_incoming_html_email => 1 );

    receive_ok( handle => $fh );

    my $page = $hub->pages()->new_from_name('Gmail HTML');
    isa_ok( $page, 'Socialtext::Page' );
    ok( $page->active(), "Found a page with the name of 'Gmail HTML'" );

    my $attachments = $page->hub()->attachments()->all( page_id => $page->id );
    is( @$attachments, 1,
        'when using html body, it is also saved as an attachment' );

    is( $attachments->[0]->mime_type(), 'text/html', 'attachment type is text/html' );
    ok( $attachments->[0]->content(), 'html attachment has some content' );

    $wksp->update( prefers_incoming_html_email => 0 );

    $page->purge();
}

NO_SUBJECT: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name\@example.com
Date: Thu, 20 Jul 2006 12:00:00

No subject
EOF
    receive_ok(string => $email);

    my $subject = 'Mail from devnull1, Thu, 20 Jul 2006 12:00:00';

    my $page = $hub->pages()->new_from_name($subject);
    isa_ok( $page, 'Socialtext::Page' );
    ok( $page->active(), "found a page with the name '$subject'" );
    is( $page->title(), $subject, 'page title is default subject' );
}

UTF8_SUBJECT_AND_BODY: {
    my $file = 't/test-data/email/french-utf8';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    receive_ok( handle => $fh );

    my $subject = Encode::decode( 'utf8', "HÉY" );

    my $page = $hub->pages->new_from_name($subject);
    isa_ok( $page, 'Socialtext::Page' );
    ok( $page->active(), 'page with expected title was created' );
    is( $page->title(), $subject, 'check that title matches email subject' );

    like( $page->content(),
          qr/Th\x{00C9} walls in th\x{00C9} mall are totally totally tall\./,
          'check that page content contains expected latin text' );
    like( $page->content(), qr/\x{30DB}\x{30DC}/,
          'check that page content contains expected katakana text' );
}

CID_IMG_URIS: {
    my $file = 't/test-data/email/html-mail-with-image';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    $wksp->update( prefers_incoming_html_email => 1 );

    receive_ok( handle => $fh );

    my $page = $hub->pages()->new_from_name('HTML with cid: image');
    isa_ok( $page, 'Socialtext::Page' );

    unlike( $page->content(),
          qr/\Q{image: cid:.+}/,
          'cid: for image uri is converted to image WAFL without cid: scheme' );

    unlike( $page->content(),
          qr/Date:.+\n{image: attachment-.+}/,
          'embedded image does is not also embedded in wafl at the top of the page' );

    my $attachments = $page->hub()->attachments()->all( page_id => $page->id );
    my $filename;
    # There will be two attachments - the html & the image, and their
    # order is unpredictable
    for my $att (@$attachments) {
        $filename = $att->filename()
            if $att->filename() =~ /\.jpeg$/;
    }

    like( $page->content(), qr/test {image: \Q$filename\E}/ ,
        '{image} wafl refers to attachment by correct filename in page body' );

    $wksp->update( prefers_incoming_html_email => 0 );
}

# See RT 20857
FOWARDED_HTML_EMAIL: {
    my $file = 't/test-data/email/forwarded-gmail';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    $wksp->update( prefers_incoming_html_email => 1 );

    receive_ok( handle => $fh );

    my $page = $hub->pages()->new_from_name('Forwarded gmail');
    isa_ok( $page, 'Socialtext::Page' );
    unlike( $page->content(), qr{\Q&lt;},
            'page does not contain HTML entities (&lt;)' );
    like( $page->content(), qr{\QTo: Ken Pier <},
          'page contains headers from forwarded mail' );

    $wksp->update( prefers_incoming_html_email => 0 );
}

ACL_CHECKS: {
    $wksp->permissions->remove(
        role       => Socialtext::Role->AuthenticatedUser(),
        permission => Socialtext::Permission->new( name => 'email_in' ),
    );

    my $email = <<EOF;
From: i.love.you\@spam.com
To: $wksp_name\@example.com
Date: Thu, 20 Jul 2006 12:00:00

No subject
EOF

    eval {
        receive_ok( string => $email );
    };

    ok( $@, 'exception was thrown delivering mail from guest to $wksp_name' );
    isa_ok( $@, 'Socialtext::Exception::Auth', 'exception is an Auth exception' );
    ok( ! defined Socialtext::User->new( email_address => 'i.love.you@spam.com' ),
        'no new user is created when the sender does not have email_in permission' );

    $email = <<EOF;
From: devnull2\@socialtext.com
To: $wksp_name\@example.com
Date: Thu, 20 Jul 2006 12:00:00

No subject
EOF

    eval {
        receive_ok( string => $email );
    };

    ok( $@, 'exception was thrown delivering mail from authenticated user to $wksp_name' );
    isa_ok( $@, 'Socialtext::Exception::Auth', 'exception is an Auth exception' );
}

sub allow_guest_email_in {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $perm = Socialtext::Permission->new( name => 'email_in' );
    isa_ok( $perm, 'Socialtext::Permission' );

    $_[0]->permissions->add(
        role       => Socialtext::Role->Guest(),
        permission => $perm,
    );
}

sub remove_guest_email_in {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $perm = Socialtext::Permission->new( name => 'email_in' );
    isa_ok( $perm, 'Socialtext::Permission' );

    $_[0]->permissions->remove(
        role       => Socialtext::Role->Guest(),
        permission => $perm,
    );
}

use utf8;

TITLE_IS_JAPANESE: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name\@example.com
Subject: 日本語タイトル

abcdefg
EOF

    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('日本語タイトル');
    isa_ok( $page, 'Socialtext::Page' );
    like( $page->content(), qr/\Qabcdefg\E/,
          'new text is in page content' );
}
 
TITLE_IS_JAPANESE_HANKAKU: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name\@example.com
Subject: 日本語ﾀｲﾄﾙ

abcdefg
EOF

    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('日本語ﾀｲﾄﾙ');
    isa_ok( $page, 'Socialtext::Page' );
    like( $page->content(), qr/\Qabcdefg\E/,
          'new text is in page content' );
}
 
BODY_IS_JAPANESE: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name\@example.com
Subject: Start Here by Japanese 1

日本語ボディ
EOF
    
    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('Start Here by Japanese 1');
    like( $page->content(), qr/\Q日本語ボディ\E/,
          'new text is in page content' );
}
 
BODY_IS_JAPANESE_HANKAKU: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name\@example.com
Subject: Start Here by Japanese 2

日本語ﾎﾞﾃﾞｨ
EOF
    
    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('Start Here by Japanese 2');
    like( $page->content(), qr/\Q日本語ﾎﾞﾃﾞｨ\E/,
          'new text is in page content' );
}

CATEGORY_IS_JAPANESE_IN_TO_ADDRESS: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name+New=20=E3=82=BF=E3=82=B0\@example.com
Subject: In New Cat by Japanese

Blah blah
EOF

    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('In New Cat by Japanese');
    isa_ok( $page, 'Socialtext::Page' );
    is_deeply(
        [ sort @{ $page->tags } ],
        [ 'Email', 'New タグ' ],
        'page is in Email and New Cat categories'
    );
}

CATEGORY_IS_JAPANESE_IN_CC_ADDRESS: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: bubba\@example.com
Cc: $wksp_name+New=20=E3=82=BF=E3=82=B0\@example.com
Subject: In New Cat2 by Japanese

Blah blah
EOF

    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('In New Cat2 by Japanese');
    isa_ok( $page, 'Socialtext::Page' );
    is_deeply(
        [ sort @{ $page->tags } ],
        [ 'Email', 'New タグ' ],
        'page is in Email and New Cat2 categories'
    );
}

CATEGORY_COMMANDS_JA: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name\@example.com
Subject: Cats in Body by Japanese

Category: タグ１
Category: タグ２, タグ４
category: タグ３

Blah blah
EOF

    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('Cats in Body by Japanese');
    isa_ok( $page, 'Socialtext::Page' );
    is_deeply(
        [ sort @{ $page->tags } ],
        [ 'Email', 'タグ１', 'タグ２', 'タグ３', 'タグ４' ],
        'page is in  Email, タグ１, タグ２, タグ３ and タグ４ categories'
    );

    unlike( $page->content(), qr/Category:/,
            'category commands are not in the page body' );
}

TAG_COMMANDS_JA: {
    my $email = <<EOF;
From: devnull1\@socialtext.com
To: $wksp_name\@example.com
Subject: Tags in Body by Japanese

Tag: タグ１
Tag: タグ２, タグ４
tag: タグ３

Blah blah
EOF

    receive_ok( string => $email );

    my $page = $hub->pages()->new_from_name('Tags in Body by Japanese');
    is_deeply(
        [ sort @{ $page->tags } ],
        [ 'Email', 'タグ１', 'タグ２', 'タグ３', 'タグ４' ],
        'page is in  Email, タグ１, タグ２, タグ３ and タグ４ categories'
    );

    unlike( $page->content(), qr/tag:/,
            'category commands are not in the page body' );
}

ONE_ATTACHMENT_JA: {
    my $file = 't/test-data/email/one-attachment-japanese';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    receive_ok( handle => $fh );

    my $page = $hub->pages()->new_from_name('添付ファイル１');
    isa_ok( $page, 'Socialtext::Page' );

    ok( $page->active(), 'Found a page with the name of "attachments"' );
    is( $page->title(), '添付ファイル１',
        'check that page title matches subject' );

    my $attachments
        = $page->hub()->attachments()->all( page_id => $page->id );
    is( @$attachments, 1, 'page generated from email has one attachment' );

    like( $page->content(), qr/\Q{file: 日本語.doc}\E/,
          'check that page content contains link to attached file' );

    my $all = $hub->attachments->all_attachments_in_workspace();
    is( @$all, 1+7,
        'only one attachment in workspace' );

    $page->purge();
}

ATTACHED_IMAGE_JA: {
    my $file = 't/test-data/email/attached-image-japanese';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    receive_ok( handle => $fh );

    my $page = $hub->pages()->new_from_name('添付ファイル２');
    isa_ok( $page, 'Socialtext::Page' );

    ok( $page->active(), "Found a page with the name of '添付ファイル２'" );
    is( $page->title(), '添付ファイル２',
        'check that page title matches subject' );

    my $attachments
        = $page->hub()->attachments()->all( page_id => $page->id );
    is( @$attachments, 1, 'page generated from email has one attachment' );

    like( $page->content(), qr/\Q{image: 日本語イメージ.JPG}\E/,
          'check that page content contains image link to attached image' );
}

TEXT_HTML_BODY_ONLY_JA: {
    my $file = 't/test-data/email/text-html-body-japanese';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    receive_ok( handle => $fh );

    my $page = $hub->pages()->new_from_name('Text/HTML Body by Japanese');
    isa_ok( $page, 'Socialtext::Page' );

    ok( $page->active(), 'Found a page with the name of "Text/HTML Body by Japanese"' );
    is( $page->title(), 'Text/HTML Body by Japanese', 'title matches subject' );

    like( $page->content(),
          qr{\*ボールドテキスト\*},
          'page contains expected HTML content as wikitext' );

    my $attachments = $page->hub()->attachments()->all( page_id => $page->id );
    is( @$attachments, 1,
        'when using html body, it is also saved as an attachment' );

    is( $attachments->[0]->mime_type(), 'text/html', 'attachment type is text/html' );
    ok( $attachments->[0]->content(), 'html attachment has some content' );

    unlike( $page->content(), qr/{file: .+}/,
            'saving HTML body as an attachment does not create a file wafl in the body' );
}

TEXT_HTML_BODY_DIALECT: {
    my $file = 't/test-data/email/text-html-body-dialect';
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    receive_ok( handle => $fh );

    my $page = $hub->pages()->new_from_name('Text/HTML Dialect');
    isa_ok( $page, 'Socialtext::Page' );

    ok( $page->active(), 'Found a page with the name of "Text/HTML Dialect"' );
    is( $page->title(), 'Text/HTML Dialect', 'title matches subject' );

    like( $page->content(),
              qr{Heading1},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Heading2},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Heading3},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Heading4},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Heading5},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Heading6},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Paragraph},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Bold},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Strong},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Italic},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{EMphasis},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Under-line},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{strike-through},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Strike-through\(s\)},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{TeleType},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{code},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{TeleType},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{PREformatted text},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{A1},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{A2},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{A3},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{B1},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{B2},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{B3},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{C1},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{C2},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{C3},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Unordered List 1},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Unordered List 2},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Ordered List 1},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Ordered List 2},
                        'page contains expected HTML content as wikitext' );

    like( $page->content(),
              qr{Definition List},
                        'page contains expected HTML content as wikitext' );
}

sub receive_ok {
    my $args = {
        locale => $test_locale,
        workspace => $wksp,
        @_
    };
    my $email_receiver = Socialtext::EmailReceiver::Factory->create($args);
    isa_ok( $email_receiver, 'Socialtext::EmailReceiver::ja' );
    $email_receiver->receive();
    return;
}

