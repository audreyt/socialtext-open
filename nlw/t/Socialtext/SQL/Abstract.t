#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::More tests => 5;

use Socialtext::SQL::Builder qw(sql_abstract);
use_ok 'Socialtext::SQL::Abstract';

my $abstract = sql_abstract();

# Test that SQL::Abstract is monkey-patched to support GROUP BY clauses
{
    my $sql = $abstract->select(
        'table', 'field',
        { where_col => 'where_field' },
        { group_by => 'group_col' },
    );

    is $sql, q{SELECT field FROM table } .
             q{WHERE ( where_col = ? ) GROUP BY group_col};
}

# Test that SQL::Abstract::Limit still works with a monkey-patched
# SQL::Abstract so it supports GROUP BY clauses
{
    my $sql = $abstract->select(
        'table', 'field',
        { where_col => 'where_field' },
        { group_by => 'group_col' },
        10, 5,
    );

    is $sql, q{SELECT field FROM table } .
             q{WHERE ( where_col = ? ) GROUP BY group_col } .
             q{LIMIT 10 OFFSET 5};
}

# Make sure GROUP BY and ORDER BY work together
{
    my $sql = $abstract->select(
        'table', 'field',
        { where_col => 'where_field' },
        { group_by => 'group_col', order_by => 'order_col' },
        10, 5,
    );

    is $sql, q{SELECT field FROM table } .
             q{WHERE ( where_col = ? ) GROUP BY group_col } .
             q{ORDER BY order_col } .
             q{LIMIT 10 OFFSET 5};
}

pass 'done';
