#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 16;
use YAML;
use URI::Escape qw(uri_escape);

fixtures(qw( admin ));

###############################################################################
# TEST: ability to convert a page to HTML, from "admin" Workspace.
convert_page_to_html: {
    my $hub  = new_hub('admin');
    my $file = $hub->pdf_export->_create_html_file('Conversations');
    ok $file, 'Got file from converting wikipage to HTML';
    ok -s $file, '... which is not an empty file';
}

###############################################################################
# TEST: convert to HTML, with attached image w/spaces in filename
convert_to_html_w_spaces_in_image_filename: {
    my $imgfile = 'socialtext-logo-30.gif';
    my $imgpath = "t/attachments/$imgfile";
    my $newname = 'name with spaces in filename.gif';
    my $wiki    = "{image: $newname}";

    my $hub  = create_test_hub();
    my $page = Socialtext::Page->new(hub => $hub)->create(
        creator => $hub->current_user,
        title   => 'Test Page',
        content => $wiki,
    );
    ok $page, 'Created test page';

    open my $fh, '<', $imgpath or die "$imgpath\: $!";
    $hub->attachments->create(
        creator  => $hub->current_user,
        page_id  => $page->id,
        filename => $newname,
        fh       => $fh,
    );

    my @attachments = $page->attachments();
    is scalar(@attachments), 1, '... attached image';

    my $html = $hub->pdf_export->_get_html($page->name);
    ok $html, '... converted to HTML';

    my $escaped = uri_escape($newname);
    like $html, qr{<img [^>]*src="[^"]+/$escaped"},
        '... image filename is properly escaped';
}

###############################################################################
# TEST: multi-page export, from "admin" Workspace.
multi_page_export: {
    my @pages = ('Conversations', 'Start Here', 'Meeting agendas');
    my $hub   = new_hub('admin');
    my $pdf;
    $hub->pdf_export->multi_page_export(\@pages, \$pdf);
    looks_like_pdf_ok $pdf, 'Multi-page export looks like PDF';
}

###############################################################################
# TEST: create some wikipages, and convert them to PDF
export_to_pdf: {
    my $hub   = create_test_hub();
    my @cases = Load(join '', <DATA>);

    foreach my $case (@cases) {
        my ($content, $title) = @{$case};
        my $page = Socialtext::Page->new(hub => $hub)->create(
            creator => $hub->current_user,
            title   => $title,
            content => $content,
        );
        ok $page, "Created test page: $title";

        my $pdf;
        $hub->pdf_export->multi_page_export([ $page->name ], \$pdf);
        looks_like_pdf_ok $pdf, '... results look like a PDF';
    }
}

###############################################################################
# TEST: empty content
empty_page_content: {
    my $hub = create_test_hub();
    my $page = Socialtext::Page->new(hub => $hub)->create(
        creator => $hub->current_user,
        title   => 'Empty Page',
        content => '',
    );
    ok $page, 'Created empty test page';

    my $pdf;
    my $rc = $hub->pdf_export->multi_page_export([ $page->name ], \$pdf);
    ok $rc, '... which we are able to convert to PDF';
    looks_like_pdf_ok $pdf, '... resulting in some PDF content';
}


__DATA__
---
- |
    | 1a | 1b |
    | 2a | *2b* |

    hello
- Table and paragraph
---
- '* one'
- Unordered list
---
- |
    .html
    <ul>
    <li>one</li>
    </ul>
    .html
- UL in html block
