#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 14;
fixtures( 'admin_with_ordered_pages', 'foobar_with_ordered_pages' );

BEGIN {
    use_ok( "Socialtext::CategoryPlugin" );
}

my $workspace_hub = new_hub('admin');

run {
    my $case = shift;
    my $got = $workspace_hub->viewer->text_to_html($case->kwiki);
    smarter_like($got, $case->htmlre, $case->name);
};

__DATA__

=== {category-list category 0}
--- kwiki
{category-list category 0}
--- htmlre
action=blog_display;category=category%200
admin page six
admin page four
admin page two

=== {tag-list category 0}
--- kwiki
{tag-list category 0}
--- htmlre
action=blog_display;category=category%200
admin page six
admin page four
admin page two

=== {category-list category 1}
--- kwiki
{category-list category 1}
--- htmlre
action=blog_display;category=category%201
admin page five
admin page three
admin page one

=== {category-list <foobar> category 0}
--- kwiki
{category-list <foobar> category 0}
--- htmlre
action=blog_display;category=category%200
foobar page six
foobar page four
foobar page two

=== {category-list-full category 0}
--- kwiki
{category-list-full category 0}
--- htmlre
<!-- wiki: {category_list_full: category 0}
--></div><br /></div>

=== {tag-list-full category 0}
--- kwiki
{tag-list-full category 0}
--- htmlre
<!-- wiki: {tag_list_full: category 0}
--></div><br /></div>

=== {category-list-full <foobar> category 0}
--- kwiki
{category-list-full <foobar> category 0}
--- htmlre
<!-- wiki: {category_list_full: <foobar> category 0}
--></div><br /></div>

=== {weblog-list category 1}
--- kwiki
{weblog-list category 1}
--- htmlre
action=blog_display;category=category%201
admin page five
admin page three
admin page one

=== {weblog-list <foobar> category 1}
--- kwiki
{weblog-list <foobar> category 1}
--- htmlre
action=blog_display;category=category%201
foobar page five
foobar page three
foobar page one

=== {blog-list category 1}
--- kwiki
{blog-list category 1}
--- htmlre
action=blog_display;category=category%201
admin page five
admin page three
admin page one

=== {blog-list <foobar> category 1}
--- kwiki
{blog-list <foobar> category 1}
--- htmlre
action=blog_display;category=category%201
foobar page five
foobar page three
foobar page one

=== {category-list yadda} - link text
--- kwiki
{category-list yadda}
--- htmlre
Recent Changes in Tag yadda

=== {category-list fooblog} - link text
--- kwiki
{category-list fooblog}
--- htmlre
Recent Posts from fooblog
