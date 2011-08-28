#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::More;

BEGIN {
    eval 'use Test::MockObject';
    plan skip_all => 'This test requires Test::MockObject' if $@;
    plan tests => 6;
}

my $context = Test::MockObject->new();
$context->mock('install_filter', sub { return $context; } );
$context->mock('define_filter', sub { return $context; } );

use_ok( 'Socialtext::Template::Plugin::html_encode' );
my $filter = Socialtext::Template::Plugin::html_encode->new($context);

is($filter->filter('a'), 'a', 'No translation of standard text');
is($filter->filter('"'), '&quot;', 'Double Quote translated');
is($filter->filter('\''), '&#39;', 'Quote translated');
is($filter->filter('<>&'), '&lt;&gt;&amp;', 'HTML translated');

my $singapore = join '', map { chr($_) } 26032, 21152, 22369;
is($filter->filter($singapore), '&#x65B0;&#x52A0;&#x5761;', 'UTF8 translated');
