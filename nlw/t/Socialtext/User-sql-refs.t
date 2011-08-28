#!perl
use warnings;
use strict;
use Test::Socialtext tests => 1;
use Socialtext::SQL qw/sql_execute/;

fixtures(qw(db));

check_fk_constraints: {
    my $sth = sql_execute(q{
        SELECT DISTINCT constraint_name
        FROM information_schema.referential_constraints
        NATURAL JOIN information_schema.constraint_table_usage
        NATURAL JOIN information_schema.constraint_column_usage
        WHERE table_name = 'user'
          AND column_name = 'user_id'
          AND delete_rule <> 'RESTRICT'
    });
    my $rows = $sth->fetchall_arrayref({}) || [];
    is(@$rows, 0, "all FKs on user.user_id are ON DELETE RESTRICT");
    if (@$rows) {
        diag "\n";
        diag "The following constraints don't specify ON DELETE RESTRICT.\n";
        diag "Please change them so that they do and check Perl codes\n\n";
        diag "* $_->{constraint_name}" for @$rows;
        diag "\n";
    }
}
