#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 43;
use Socialtext::URI;
use Socialtext::Cache;
fixtures(qw( clean auth-to-edit no-ceq-jobs ));

use DateTime;

# REVIEW: See t/syndicate-page.t for a less regular expression intensive
# way to do feed tests

BEGIN {
    use_ok( "Socialtext::SyndicatePlugin" );
    use_ok( "Socialtext::Page" );
    use_ok( "Socialtext::Jobs" );
}

my $hub = new_hub('auth-to-edit');
Socialtext::Cache->clear();
no warnings 'redefine';
*Socialtext::URI::_scheme_host_port = sub { 
    host => 'local.example.com',
    scheme => 'http',
};

my $date = DateTime->now->add( seconds => 600 );

# We have to call syndicate off the hub to initialize Socialtext::CGI :(
my $syndicator = $hub->syndicate;

Socialtext::Page->new(hub => $hub)->create(
    title => 'this is the title',
     content => ("\n^^^ This is the content\n\n* [Wiki 101]\\n\nHello.\n" x 100),
    creator => $hub->current_user,
    date => $date,
    categories => [qw(cows blink)],
);

Socialtext::Page->new(hub => $hub)->create(
    title => 'this is the ugly one in base 64',
    content => "\n^^^ This is the\bugly\n\n* [Wiki 101]\\n\nHello.\n",
    creator => $hub->current_user,
    date => $date,
);

Socialtext::Page->new(hub => $hub)->create(
    title => 'this is bad xhtml',
    content => "\n* hello\n** goodbye\n* hello\n\n",
    creator => $hub->current_user,
    date => $date,
);

ceqlotron_run_synchronously();

run {
    my $block = shift;
    my @positive_regexps = ();
    my @negative_regexps = ();
    my $output = generate_feed($block->method, $block->type, $block->argument);
    @positive_regexps = split(/\n/, $block->match) if $block->match;
    @negative_regexps = split(/\n/, $block->nomatch) if $block->nomatch;

    foreach my $re (@positive_regexps) {
        like $output, qr/\Q$re/, "matches $re";
    }

    foreach my $re (@negative_regexps) {
        unlike $output, qr/\Q$re/, "does not match $re";
    }
};

sub generate_feed {
    my $method = shift;
    my $type = shift;
    my $argument = shift;

    return $syndicator->$method($type, $argument)->as_xml;
}

__DATA__

===
--- method: _syndicate_changes
--- type: Atom
--- match
type="xhtml"
Auth-to-edit Wiki: Recent Changes</title>
this is the title</title>
<h3 id="this_is_the_content">This is the content</h3>
auth-to-edit/this_is_the_title</id>
auth-to-edit/this_is_the_title"/>
this is the ugly one in base 64</title>
this is bad xhtml</title>

===
--- method: _syndicate_changes
--- type: RSS20
--- match
rss version="2.0"
<title><![CDATA[Auth-to-edit Wiki: Recent Changes]]></title>
-0000</pubDate>
<generator>Socialtext Workspace v
<title><![CDATA[this is the title]]></title>
<h3 id="this_is_the_content">This is the content</h3>
<author>devnull1@hidden</author>
<guid isPermaLink="true">http://local.example.com/auth-to-edit/this_is_the_title</guid>
<link>http://local.example.com/auth-to-edit/this_is_the_title</link>
--- nomatch
http://www.w3.org/2005/Atom

===
--- method: _syndicate_page_named
--- type: Atom
--- argument: this is the title
--- match
http://www.w3.org/2005/Atom
>Auth-to-edit Wiki: this is the title</title>
>this is the title</title>
<h3 id="this_is_the_content">This is the content</h3>
Tags: blink, cows
--- nomatch
>this is bad xhtml</title>

===
--- method: _syndicate_page_named
--- type: RSS20
--- argument: this is the title
--- match
Tags: blink, cows
<category>blink, cows</category>

===
--- method: _syndicate_search
--- type: RSS20
--- argument: title:title
--- match
<title><![CDATA[Auth-to-edit Wiki: search for title:title]]></title>
<title><![CDATA[this is the title]]></title>
<h3 id="this_is_the_content">This is the content</h3>

===
--- method: syndicate
--- match
rss version="2.0"
<title><![CDATA[Auth-to-edit Wiki: Recent Changes]]></title>
-0000</pubDate>
<generator>Socialtext Workspace v
<title><![CDATA[this is the title]]></title>
<h3 id="this_is_the_content">This is the content</h3>
<author>devnull1@hidden</author>
<guid isPermaLink="true">http://local.example.com/auth-to-edit/this_is_the_title</guid>
<link>http://local.example.com/auth-to-edit/this_is_the_title</link>
--- nomatch
http://www.w3.org/2005/Atom
