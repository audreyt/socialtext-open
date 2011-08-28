#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 2;
fixtures(qw( empty ));

# Confirm that we can create tables of contents of 
# the current page, of another page in the same workspace,
# of a page not in this workspace, but not of a page
# in which we aren't a member.

use Socialtext::Pages;

my $FILE  = 'rock#it.txt';
my $IMAGE = 'sit#start.png';

my $hub = new_hub('empty');
my $page_id = "formater_file_test_$$";

my $page_one = Socialtext::Page->new( hub => $hub )->create(
    title   => $page_id,
    content => <<'EOF',

Shoots brah, I'm going to attach me something here

{file rock#it.txt}
{image sit#start.png}

EOF
    creator => $hub->current_user,
);

# attach those bad boys
$hub->pages->current($page_one);
attach($FILE);
attach($IMAGE);

my $html_one
    = $hub->pages->new_from_name($page_id)->to_html_or_default();

like $html_one,
     qr{/data/workspaces/empty/attachments/$page_id:[\d-]+/original/rock%23it\.txt"},
     'url for rock#it.txt is escaped';
like $html_one,
     qr{/data/workspaces/empty/attachments/$page_id:[\d-]+/scaled/sit%23start\.png"},
     'url for sit#start.png is escaped';

exit;


sub attach {
    my $filename = shift;
    my $path = 't/attachments/' . $filename;
    open my $fh, '<', $path or die "unable to open $path $!";
    $hub->attachments->create(
        filename => $filename,
        fh => $fh,
        creator => $hub->current_user,
    );
}

