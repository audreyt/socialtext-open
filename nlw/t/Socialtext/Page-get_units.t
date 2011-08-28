#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext tests => 12;
fixtures(qw( empty ));

use Socialtext::Page;

my $content =<<'EOF';
^ the first header

{section a} This is the stuff a

^^ the second header

{section b} here's the [other stuff] b

^ the third header

** and a list
** for fun

^^^^^^ the fourth header

[wow]

EOF

my $hub = new_hub('empty');
my $page = Socialtext::Page->new(hub => $hub)->create(
    title => 'our test page',
    content => $content,
    creator => $hub->current_user,
);

HEADERS: {
    my $headers = $page->get_headers();
    is scalar @$headers, 4, 'there are four headers';

    my $second_header = $headers->[1];
    is $second_header->{text}, 'the second header', 'the second header has the right text';
    is $second_header->{level}, 2, 'the second header has level 2';

    my $fourth_header = $headers->[3];
    is $fourth_header->{text}, 'the fourth header', 'the fourth header has the right text';
    is $fourth_header->{level}, 6, 'the fourth header has level 6';

}

SECTIONS: {
    my $sections = $page->get_sections();
    is scalar @$sections, 6, 'there are four sections';

    my $second_header = $sections->[2];
    is $second_header->{text}, 'the second header', 'the second header has the right text';

    my $third_section = $sections->[1];
    is $third_section->{text}, 'a', 'section a has text a';
}

ARBITRARY: {
    my $units = $page->get_units(
        'wiki' => sub { return +{name => $_[0]->get_text}},
    );

    is scalar @$units, 2, 'there are two freelinks in the page';
    is $units->[1]->{name}, 'wow', 'the second link is named wow';

    $units = $page->get_units(
        'frank' => sub { 1 },
    );
    is scalar @$units, 0, 'there are 0 frank units in the page';

}

DELETED: {
    $page->edit_rev;
    $page->content('');

    my $sections = $page->get_sections();
    is scalar @$sections, 0, 'no sections in an empty page';
}
