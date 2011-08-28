#!perl
# @COPYRIGHT@

use warnings;
use strict;
use Socialtext::AppConfig;
use Test::Socialtext tests => 15;
use IO::File;

fixtures('db');

use File::Path ();
use ok 'Socialtext::HTMLArchive';

my $hub = create_test_hub('admin');

{
    my $page = $hub->pages->new_from_name('Welcome');
    $hub->pages->current($page);
    my $rev = $page->edit_rev;
    $page->content('Welcome!');
    $page->store();
}

{
    my $page = $hub->pages->new_from_name('Quick-start');
    my $g = $hub->pages->ensure_current($page);
    $page->content('JFDI');
    $page->store();
}

{
    my $page = $hub->pages->new_from_name('Admin Wiki');
    my $g = $hub->pages->ensure_current($page);
    $page->tags(['Top Page']);
    $page->content("I'm in ur pages, admining ur wikis\n");
    $page->store();
}

# add attachments to a page so we can test that attachment/image links
# are processed properly
{
    my $page = $hub->pages->current;
    is $page->page_id, 'welcome';
    for my $att (qw( revolts.doc socialtext-logo-30.gif )) {
        my $path = "t/attachments/$att";
        my $fh = IO::File->new($path,'<');
        my $attachment = $hub->attachments->create(
            page     => $page,
            filename => $path,
            fh       => $fh,
            embed    => 1,
        );
        ok $attachment, "created attachment for $att";
    }
}

my $archive  = Socialtext::HTMLArchive->new( hub => $hub );
my $test_dir = Socialtext::AppConfig->test_dir();
my $dir = "$test_dir/junk";
File::Path::mkpath( $dir, 0, 0755 );
END { File::Path::rmtree($dir) if (defined $dir && -d $dir) }

my $file_name = "$dir/admin-archive.zip";
unlink $file_name;

$archive->create_zip($file_name);
ok -e $file_name, 'archive exists';

system( 'unzip', '-q', $file_name, '-d', $dir );

for my $f (
    map { "$dir/$_" }
    qw( admin_wiki.htm
    quick_start.htm
    welcome.htm
    screen.css
    revolts.doc
    socialtext-logo-30.gif )
  ) {
    ok -e $f, "$f exists";
}

my $html_file = "$test_dir/junk/welcome.htm";
open my $fh, '<', $html_file
  or die "Cannot read $html_file: $!";
my $html = do { local $/; <$fh> };

like $html, qr/link.+ href="screen.css"/,
  'admin_wiki.htm has valid css link to screen.css';
like $html, qr/href="revolts.doc"/, 'welcome.htm has valid link to revolts.doc';
like $html, qr/src="socialtext-logo-30.gif"/,
  'welcome.htm has img link to socialtext-logo-30.gif';

pass 'done';
