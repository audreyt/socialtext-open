#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 4;

fixtures(qw( db ));

###############################################################################
# TEST: grayscale PNG image
grayscale_png: {
    my $imgfile = 'grayscale.png';
    my $imgpath = "t/attachments/$imgfile";
    my $wiki    = "{image: $imgfile}";

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
        filename => $imgfile,
        fh       => $fh,
    );

    my @attachments = $page->attachments();
    is scalar(@attachments), 1, '... attached image';

    my $pdf;
    $hub->pdf_export->multi_page_export( [$page->name], \$pdf );
    ok $pdf, '... exported page to PDF';
    looks_like_pdf_ok $pdf, '... results look like a PDF';
}
