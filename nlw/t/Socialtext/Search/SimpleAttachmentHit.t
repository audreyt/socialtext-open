#!perl
# @COPYRIGHT@
use warnings;
use strict;

use Test::More tests => 8;
use Socialtext::Search::SimpleAttachmentHit;
use Readonly;

Readonly my $PAGE_URI          => 'mml_work_log_2006_04_27';
Readonly my $NEW_PAGE_URI      => 'mml_work_log_2006_04_28';
Readonly my $ATTACHMENT_HIT    => {
    excerpt => '... blah blah blah .. ',
    key     => 'somethin'
};

Readonly my $WS_NAME           => 'socialtext';
Readonly my $ATTACHMENT_ID     => '20060427183122-0';
Readonly my $NEW_ATTACHMENT_ID => '20060427183122-1';

BEGIN {
    use_ok( 'Socialtext::Search::SimpleAttachmentHit' );
}

# Test constructor/getters
{
    my $hit = Socialtext::Search::SimpleAttachmentHit->new( $ATTACHMENT_HIT,
        $WS_NAME, $PAGE_URI, $ATTACHMENT_ID );

    ok( $hit->isa('Socialtext::Search::AttachmentHit'),
        'isa Socialtext::Search::AttachmentHit' );

    is( $hit->page_uri, $PAGE_URI, 'constructor picks up page URI' );

    is( $hit->attachment_id, $ATTACHMENT_ID,
        'constructor picks up attachment ID' );
}

# Test set_page_uri
{
    my $hit = Socialtext::Search::SimpleAttachmentHit->new( $ATTACHMENT_HIT,
        $WS_NAME, $PAGE_URI, $ATTACHMENT_ID );

    $hit->set_page_uri($NEW_PAGE_URI);

    is( $hit->page_uri, $NEW_PAGE_URI, 'page URI setter works' );

    is( $hit->attachment_id, $ATTACHMENT_ID,
        'page URI setter leaves attachment ID alone' );
}

# Test set_attachment_id
{
    my $hit = Socialtext::Search::SimpleAttachmentHit->new( $ATTACHMENT_HIT,
        $WS_NAME, $PAGE_URI, $ATTACHMENT_ID );

    $hit->set_attachment_id($NEW_ATTACHMENT_ID);

    is( $hit->page_uri, $PAGE_URI,
        'attachment ID setter leaves page URI alone' );

    is( $hit->attachment_id, $NEW_ATTACHMENT_ID, 'attachment ID setter works' );
}
