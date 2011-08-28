#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::More;

BEGIN {
    eval 'use Test::MockObject';
    plan skip_all => 'This test requires Test::MockObject' if $@;
    plan tests => 11;
}

my $context = Test::MockObject->new();
$context->mock('install_filter', sub { return $context; } );
$context->mock('define_filter', sub { return $context; } );

use_ok( 'Socialtext::Template::Plugin::label_ellipsis' );
my $filter = Socialtext::Template::Plugin::label_ellipsis->new($context);

is($filter->filter('abcd', [15]), 'abcd', 'No ellipsis on short label');
is($filter->filter('abcd', [2]), 'ab...', 'Ellipsis on length 2 label');
is($filter->filter('abc def', [4]), 'abc...', 'Ellipsis breaks on space');
is($filter->filter('abc def', [6]), 'abc...', 'Ellipsis breaks on space if short one');
is($filter->filter('abc def', [7]), 'abc def', 'No ellipsis on exact length');
is($filter->filter('abc  def efg', [11]), 'abc  def...', 'Whitespace preserved between words');
is($filter->filter('abc def', [0]), '...', 'Ellipsis only if length is 0');
is($filter->filter('abc def', [2]), 'ab...', 'Proper short word ellipsis with space');

#utf8
my $singapore = join '', map { chr($_) } 26032, 21152, 22369;
is($filter->filter($singapore, [3]), $singapore, 'UTF8 not truncated');
is($filter->filter($singapore, [2]), substr($singapore, 0, 2) . '...', 'UTF8 truncated with ellipsis');
