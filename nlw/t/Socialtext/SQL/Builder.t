#!perl
# @COPYRIGHT@
use strict;
use warnings FATAL => 'all';

use Test::More tests => 36;
use Test::Socialtext::Fatal;
use mocked 'Socialtext::SQL', ':test';

use_ok 'Socialtext::SQL::Builder', ':all';

nextval: {
    sql_mock_result([42]);

    my $next = sql_nextval('somesequence');
    is $next, 42, "got expected nextval";
    sql_ok(
        sql => "SELECT nextval(?)",
        args => ['somesequence'],
        name => 'sql_nextval',
    );
}

update_invalid_calls: {
    ok exception { sql_update('') };
    ok exception { sql_update(undef) };
    ok exception { sql_update('mytable') }, 'missing args';
    ok exception { sql_update('mytable', undef, 'id') }, 'missing params';
    ok exception { sql_update('mytable', {}, 'id') }, 'empty params';
    ok exception { sql_update('mytable', {foo=>12}, 'id') }, 'missing key';
    ok exception { sql_update('mytable', {foo=>undef}, 'foo') }, 'undef value';

    ok !@Socialtext::SQL::SQL, 'no sql got run';
}

update_works: {
    sql_update(
        'mytable_1',
        {
            foo  => 'bar',
            this => 'that',
            baz  => 'quxx',
        },
        'foo'
    );
    sql_ok(
        sql => q{UPDATE mytable_1 SET baz = ?, this = ? WHERE foo = ?},
        args => ['quxx', 'that', 'bar'],
        name => 'sql_update works',
    );
    ok !@Socialtext::SQL::SQL, 'no more sql';
}

update_works_with_composite_key: {
    sql_update(
        'mytable',
        {
            one   => '1',
            two   => '2',
            three => '3',
        },
        [ 'one', 'two' ],
    );
    sql_ok(
        sql  => q{UPDATE mytable SET three = ? WHERE one = ? AND two = ?},
        args => [ '3', '1', '2' ],
        name => 'update works with composite key'
    );
    ok !@Socialtext::SQL::SQL, 'no more sql';
}

insert_invalid_calls: {
    ok exception { sql_insert('') };
    ok exception { sql_insert(undef) };
    ok exception { sql_insert('mytable') }, 'missing args';
    ok exception { sql_insert('mytable', undef) }, 'missing params';
    ok exception { sql_insert('mytable', {}) }, 'empty params';

    ok !@Socialtext::SQL::SQL, 'no sql got run';
}

insert_works: {
    sql_insert(
        'mytable_2',
        {
            foo2  => 'bar',
            this2 => 'that',
            baz2  => 'quxx',
        },
    );
    sql_ok(
        sql => q{INSERT INTO mytable_2 (baz2,foo2,this2) VALUES (?,?,?)},
        args => ['quxx', 'bar', 'that'],
        name => 'sql_insert works',
    );
    ok !@Socialtext::SQL::SQL, 'no more sql';
}

insert_many: {
    my $args = [ [qw/a b c/], [qw/d e f/], [qw/g h i/] ];
    sql_insert_many(
        'mytable_3',
        [ qw/foo bar baz/ ],
        $args,
    );
    sql_ok(
        sql => q{INSERT INTO mytable_3 (foo,bar,baz) VALUES (?,?,?)},
        args => $args,
        name => 'sql_insert_many works',
    );
    ok !@Socialtext::SQL::SQL, 'no more sql';
}

insert_many_fail: {
    ok exception { sql_insert_many('') };
    ok exception { sql_insert_many('table') };
    ok exception { sql_insert_many('table', []) };
    ok exception { sql_insert_many('table', [], []) };
    ok exception { sql_insert_many('table', [1], []) };
    ok exception { sql_insert_many('table', [], [1]) };
}
