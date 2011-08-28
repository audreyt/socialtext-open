#!perl
# @COPYRIGHT@

use warnings;
use strict;
use utf8;

use Test::HTTP::Socialtext '-syntax', tests => 6;

use URI::Escape;
use Readonly;
use Socialtext::Attachments;
use Socialtext::Workspace;
use Test::Live fixtures => ['workspaces_with_extra_pages'];
use Test::More;

my $base = Test::HTTP::Socialtext->url;

my $hub
    = Test::Socialtext::Environment->instance()->hub_for_workspace('public');

my $attachment = (grep { $_->filename =~ /Rule/ }
    @{ $hub->attachments->all( page_id => 'formattingtest' ) })[0];

my $filename = uri_escape( $attachment->filename );
my $id       = uri_escape( $attachment->id );

my %url = (
    UI   => "$base/public/index.cgi/$filename?"
        . "action=attachments_download;page_name=formattingtest;id=$id",
    REST => "$base/data/workspaces/public/attachments/"
        . "formattingtest:$id/original/$filename"
);

# Verify that when downloading attachments we don't send any 'no-cache'
# headers in Pragma or Cache-control.  This is important to allow IE users to
# actually download the file because IE honors the no-cache directives rather
# literally.
while (my ($type, $url) = each %url) {
    test_http "$type attachment headers" {
        >> GET $url

        << 200

        unlike($test->response->header($_), qr/no-cache/, "$_ is clear.")
            for qw( cache-control pragma );
    }
}
