#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext tests => 6;
fixtures(qw( empty ));

use Socialtext::Page;

my $content =<<'EOF';
^ the first header

This is the stuff

^^ the second header

here's the other stuff

^ the third header

** and a list
** for fun

^^^^^^ the fourth header

wow

EOF

my $hub = new_hub('empty');
my $page = Socialtext::Page->new(hub => $hub)->create(
    title => 'our test page',
    content => $content,
    creator => $hub->current_user,
);

{
    my $headers = $page->get_headers();
    is scalar @$headers, 4, 'there are four headers';

    my $second_header = $headers->[1];
    is $second_header->{text}, 'the second header', 'the second header has the right text';
    is $second_header->{level}, 2, 'the second header has level 2';

    my $fourth_header = $headers->[3];
    is $fourth_header->{text}, 'the fourth header', 'the fourth header has the right text';
    is $fourth_header->{level}, 6, 'the fourth header has level 6';

    $page->edit_rev();
    $page->content('');
    $headers = $page->get_headers();
    is scalar @$headers, 0, 'no headers in an empty page';


}
