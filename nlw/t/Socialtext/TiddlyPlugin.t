#!perl
# @COPYRIGHT@
use strict;
use warnings;

use mocked 'Apache';
use Test::Socialtext tests => 17;
fixtures(qw( empty ));

BEGIN {
    use_ok('Socialtext::TiddlyPlugin');
    use_ok('Socialtext::Page');
}

my $Title = "Hey, it is a page";
my $hub = new_hub('empty');

#### Test the units

# class_id
is (Socialtext::TiddlyPlugin->class_id(), 'tiddly', 'class_id is tiddly');

# produce_tiddly
# make one page
my $page = Socialtext::Page->new(hub=>$hub)->create(
    title => $Title,
    content => "Righteous\nBro!\n",
    creator => $hub->current_user,
    categories => ['love', 'hope charity'],
);

ok $page->isa('Socialtext::Page'), "we did create a page";

# look at the resulting tiddler
my $html = $hub->tiddly->produce_tiddly(pages => [$page], count => 1);

# turn it into tiddlers
my @chunks = split('<!--POST-STOREAREA-->', $html);
my @tiddlers = split('</div>', $chunks[0]);

# get the one we care about
my $tiddler = $tiddlers[-3];

my ($attributes, $body) = split('>', $tiddler, 2);

is $body, "\n<pre>Righteous\nBro!\n</pre>\n", "tiddler content is correct";

my %attribute;
while ($attributes =~ /([\w\.]+)="([^"]+)"/g) {
    $attribute{$1} = $2;
}

# make sure we get the right name and such
$page = $hub->pages->new_from_name($Title);

is $attribute{'title'}, $page->name,
    'tiddler and subject are the same';
is $attribute{'title'}, $Title, 'tiddler and given title are the same';
is $attribute{'modifier'}, 'devnull1@socialtext.com',
    'tiddler has the devnull1 modifier';
like $attribute{'modified'}, qr{\d{12}},
    'tiddler has a date stamp for modified';
like $attribute{'created'}, qr{\d{12}},
    'tiddler has a date stamp for created';
is $attribute{'tags'},        'love [[hope charity]]',  'tiddler lists correct tags';
is $attribute{'wikiformat'},  'socialtext', 'Wiki format socialtext';
like $attribute{'server.host'}, qr{^https?://},   'server.host looks like a uri';
is $attribute{'server.workspace'}, 'empty', 'tiddler has the right workspace';
is $attribute{'server.page.id'},   $page->uri,  'page.id is set to uri';
is $attribute{'server.page.name'}, $Title, 'page.name is set to title';
is $attribute{'server.page.revision'}, $page->revision_id,
    'version and revision id are the same';

