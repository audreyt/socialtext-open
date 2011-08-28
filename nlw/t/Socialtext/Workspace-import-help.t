#!perl
use warnings;
use strict;
use Test::Socialtext tests => 19;
use Test::Socialtext::Fatal;
require bytes;

fixtures(qw(db));

my $user = create_test_user();
my $ws_name = Test::Socialtext::create_unique_id().'_wiki';

do_help_en: {
    my $tarball = "$ENV{ST_CURRENT}/nlw/t/share/tarballs/help-en.tar.gz";

    # Load up the workspace from a previous export.
    my $ws;
    is exception {
        $ws = Socialtext::Workspace->ImportFromTarball(
            name        => $ws_name,
            tarball     => $tarball,
            overwrite   => 1,
            index_async => 1,
        );
    }, undef, "imported";
    isa_ok $ws, 'Socialtext::Workspace';

    is exception {
        $ws->add_user(
            user => $user,
            role => Socialtext::Role->Admin(),
        );
    }, undef, "added role";
}

check_it: {
    my $ws = Socialtext::Workspace->new(name => $ws_name);
    isa_ok $ws, 'Socialtext::Workspace';
    my ($main,$hub) = $ws->_main_and_hub($user);

    my $page = $hub->pages->new_from_name("Temporarily Down");
    isa_ok $page, 'Socialtext::Page';
    ok $page->exists, "page exists!";

    my @atts = $page->attachments;
    is scalar(@atts), 1, "one attachment";
    my $att = $atts[0];
    ok !$att->is_temporary, "non-temp";
    is $att->filename, 'SiteDownForUpgradePage.png', "filename";
    ok $att->is_image, "is_image";
    is $att->mime_type, "image/png", "mime_type";

    # check that the file doesn't exist on disk (just in the database)
    # immediately following import.
    ok !-f $att->disk_filename, "file not on disk";
    is exception {$att->ensure_stored()}, undef, "ensure_stored";
    ok -f $att->disk_filename, "ensure_stored() worked";
    is -s $att->disk_filename, $att->content_length,
        "stored file matches content_length metadata";

    body_from_disk: {
        my $ref;
        $att->binary_contents(\$ref);
        is bytes::length($ref), $att->content_length,
            "loaded blob from disk matches content_length";
    }

    $att->cleanup_stored;
    ok !-f $att->disk_filename, "file removed from disk";
    body_from_db: {
        my $ref;
        $att->binary_contents(\$ref);
        is bytes::length($ref), $att->content_length,
            "loaded blob from db matches content_length";
    }
}

pass "done";
