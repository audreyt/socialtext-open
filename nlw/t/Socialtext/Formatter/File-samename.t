#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 5;
use Time::HiRes qw/sleep/;
fixtures(qw( db ));

my $hub = create_test_hub();
my $ws = $hub->current_workspace;
my $ws_name = $ws->name;


my $p1 = Socialtext::Page->new( hub => $hub )->create(
    title   => 'page 1',
    content => <<'EOF',
{file: foo.txt}
EOF
    creator => $hub->current_user,
);

my $p2 = Socialtext::Page->new( hub => $hub )->create(
    title   => 'page 2',
    content => <<'EOF',
{file: foo.txt}
EOF
    creator => $hub->current_user,
);

my $p3 = Socialtext::Page->new( hub => $hub )->create(
    title   => 'page 3',
    content => <<'EOF',
{file: foo.txt}
EOF
    creator => $hub->current_user,
);

my $id1 = attach_file($p1, 'foo.txt');
sleep 0.1; # force a different timestamp
my $id2 = attach_file($p2, 'foo.txt');
# deliberately no attachment for page 3

# /data/workspaces/1303944220263950/attachments/page_3:$ID/original/foo.txt
$hub->pages->current($p1);
my $h1 = $p1->to_html_or_default();
like $h1, qr{/data/workspaces/\Q$ws_name\E/attachments/page_1:\Q$id1\E/original/foo\.txt}, "page one has attachment one";

$hub->pages->current($p2);
my $h2 = $p2->to_html_or_default();
like $h2, qr{/data/workspaces/\Q$ws_name\E/attachments/page_2:\Q$id2\E/original/foo\.txt}, "page two has attachment two";

$hub->pages->current($p3);
my $h3 = $p3->to_html_or_default();
unlike $h3, qr{/data/workspaces/\Q$ws_name\E/attachments/page_1:\Q$id1\E/original/foo\.txt}, "page three doesn't have attachment one";
unlike $h3, qr{/data/workspaces/\Q$ws_name\E/attachments/page_2:\Q$id2\E/original/foo\.txt}, "page three doesn't have attachment two";
unlike $h3, qr{/data/workspaces/[^/]+/attachments}, "no attachments links at all in page three";

sub attach_file {
    my ($page, $filename) = @_;
    $hub->pages->current($page);
    my $path = 't/attachments/' . $filename;
    open my $fh, '<', $path or die "unable to open $path $!";
    my $att = $hub->attachments->create(
        filename => $filename,
        fh => $fh,
        creator => $hub->current_user,
    );
    return $att->id;
}

