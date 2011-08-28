#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 21;
# destructive because it adds pages to these workspaces.
fixtures('admin','foobar','public','destructive');

# Confirm that we can create tables of contents of 
# the current page, of another page in the same workspace,
# of a page not in this workspace, but not of a page
# in which we aren't a member.

use Socialtext::Pages;

my $admin  = new_hub('admin'); $admin->action('test');
my $foobar = new_hub('foobar'); $foobar->action('test');
my $public = new_hub('public'); $public->action('test');

my $page_one = Socialtext::Page->new( hub => $admin )->create(
    title   => 'target one',
    content => <<'EOF',
^ Structured Wikitext

Folding [is fun].

^^ Has Benefits

> Now is the time for all good wikitext to come to the aid of its user.

^^^ And Consequences

The bees are in the what?

* this is a list
* and so is this

^ In Summary

We conclude ipsum lorem is nonsense.

^^ Header with {link in summary}

stuff

^^ Header with [Free Link]

EOF
    creator => $admin->current_user,
);

for my $hub ( $admin, $foobar ) {
    Socialtext::Page->new( hub => $hub )->create(
        title   => 'NoHeaders',
        content => <<'EOF',
This page has no headers.

None, not a one.
EOF
        creator => $hub->current_user,
    );
}

# confirm content of first page
$admin->pages->current($page_one);
my $html_one = $page_one->to_html_or_default();
like $html_one, qr{<h1 id="structured_wikitext">Structured Wikitext</h1>},
    'page one should start with an h1';

my $page_plusplus = Socialtext::Page->new( hub => $admin )->create(
    title  => 'C++',
    content => <<'EOF',

{toc}

EOF
    creator => $admin->current_user,
);

$admin->pages->current($page_plusplus);
my $html_plusplus = $page_plusplus->to_html_or_default();
like $html_plusplus,
    qr{does not have any headers.},
    'Plusplus page has a valid (empty) toc';

my $page_two = Socialtext::Page->new( hub => $admin )->create(
    title   => 'source two',
    content => <<'EOF',

^ Witness the Fitness

{toc}

^ Recant the cant

{toc [target one]}

{toc [target infinity]}

{toc [noheaders]}

{toc foobar [noheaders]}
EOF
    creator => $admin->current_user,
);

$admin->pages->current($page_two);
$admin->viewer->page_id($page_two->id);
$page_two->delete_cached_html;

my $html_two = $page_two->to_html_or_default();
like $html_two,
    qr{<div class="wafl_title">\s*Contents\s*}sm,
    'page two has a title for the first table of contents';

like $html_two,
    qr{<div class="wafl_title">\s*Contents: <a.*>target one<\/a>.*</div>}sm,
    'page two has a title for the remote table of contents';
like $html_two,
    qr{<li><span.*<a.* href="#witness_the_fitness">Witness the Fitness</a>.*</li>},
    'page two has a section link to witness the fitness';
like $html_two,
    qr{<li><span.*<a.* href="/admin/target_one#structured_wikitext">Structured Wikitext</a>.*</li>},
    'page two has a section link to structured wikitext on target one';
like $html_two,
    qr{<li><span.*<a.* href="/admin/target_one#header_with_in_summary">Header with in summary</a>.*</li>},
    'page two has a section link to complex header on target one';
like $html_two,
    qr{<li><span.*<a.* href="/admin/target_one#header_with_free_link">Header with Free Link</a>.*</li>},
    'page two has a section link to complex header on target one';
# like $html_two,
#     qr{class="wafl_syntax_error">\[target infinity\]},
#     'page two does not link to non-existent target infinity';
like $html_two,
    qr{href='/admin/noheaders'>NoHeaders</a>.*does not have any headers.},
    'a page with no headers reports that information and links to page';
like $html_two,
    qr{href='/foobar/noheaders'>NoHeaders</a>.*does not have any headers.},
    'a page with no headers in a different workspace links to page only';
like $html_two, qr{title="[^"]+this is a list},
    'html two contains lookahead list content from one';
like $html_two, qr{title="[^"]+The bees are in the what},
    'html two has a lookahead link containing content from one';

# Test under conditions similar to RSS and Atom
$admin->pages->current(undef);
$html_two = $page_two->to_absolute_html();
like $html_two,
    qr{<li><span.*<a.* href="#witness_the_fitness">Witness the Fitness</a>.*</li>},
    'page two has a section link to witness the fitness';
like $html_two,
    qr{<li><span.*<a.* href="http://.*/admin/target_one#structured_wikitext">Structured Wikitext</a>.*</li>},
    'page two has a section link to structured wikitext on target one';
# like $html_two,
#     qr{class="wafl_syntax_error">\[target infinity\]},
#     'page two does not link to non-existent target infinity';


my $page_foobar = Socialtext::Page->new( hub => $foobar )->create(
    title   => 'foobar',
    content => <<'EOF',

^ Crazy Man

{toc admin [target one]}

^ Extra wacky

{toc admin [source two]}

{toc admin [target infinity]}

EOF
    creator => $foobar->current_user,
);

$foobar->pages->current($page_foobar);
my $html_foobar = $page_foobar->to_html_or_default();
like $html_foobar,
    qr{<li><span.*<a.*href="/admin/target_one#structured_wikitext">Structured Wikitext</a>.*</span></li>},
    'page foobar links to structured wikitext on target one';
like $html_foobar,
    qr{<li><span.*<a.*href="/admin/source_two#witness_the_fitness">Witness the Fitness</a>.*</span></li>},
    'page foobar links to witness the fitness on source two';
# like $html_foobar,
#     qr{syntax_error.*admin \[target infinity\]},
#     'page foobar does not link to non-existent target infinity';

my $page_public = Socialtext::Page->new( hub => $public )->create(
    title   => 'public',
    content => <<'EOF',

^ Denied!

{toc admin [target one]}

EOF
    creator => $public->current_user,
);

$public->pages->current($page_public);
$public->current_user( Socialtext::User->Guest() );
my $html_public = $page_public->to_html_or_default();
like $html_public,
    qr{permission_error.*admin \[target one\]},
    'guest user viewing page public does not have access to admin target one';

Bad_recursion_bugs: { # 598 and 622
    local $SIG{__WARN__} = sub {
        my $warning = shift;
        die "Too much recursion!" if $warning =~ m/Deep recursion/;
        warn $warning;
    };

    my @bad_wikitexts = (
        q/^^^ {recent_changes} {toc: }/,
        q/^^^ {recent_changes} {toc}/,
        q/^ {toc} I'm OK{tm}/,
        q/^ {toc} {toc} {toc} {toc} Hometown/,
    );
    for my $text (@bad_wikitexts) {
        my $recurse_page = Socialtext::Page->new( hub => $public )->create(
            title => 'recurse',
            content => "$text\n",
            creator => $public->current_user,
        );
        my $html;
        eval { 
            $html = $recurse_page->to_html_or_default();
        };
        ok !$@, 'did not recurse forevar';
    }
}
