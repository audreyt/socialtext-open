#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests=>3;
use Test::LectroTest::Compat;
use Test::Differences;
use Socialtext::SQL qw/sql_execute/;
use Test::LectroTest::Generator qw(:common Gen);
use Graph;
use Graph::Directed;
use Socialtext::Role;
use Socialtext::UserSet;
use Data::Dumper;
use List::MoreUtils qw(any all);
use Time::HiRes;
no strict 'subs';

fixtures(qw( db ));

my $now=time;
srand($now);
diag ("Using $now as seed");
my $nothing = sql_execute(q{ DELETE FROM user_set_include });
$nothing = sql_execute(q{ DELETE FROM user_set_path});

my $OFFSET = 0x10000001;
my @vertices = $OFFSET..($OFFSET+255);
my %edges; 
my ($first, $second);
for (1..100) {
    $first = $second = $OFFSET;
    while (($first == $second) || 
        $edges{"$first/$second"}) {
        $first = $OFFSET+int(rand(256));
        $second = $OFFSET+int(rand(256));
    }
    $edges{"$first/$second"} = [$first, $second];
}

#warn "done generating graph in db";
my $graph = Graph::Directed->new( 
            vertices => \@vertices, 
            edges => [values %edges]);
my $graphb = $graph->deep_copy;

#warn "done generating Graph object";

my $dbh = Socialtext::SQL::get_dbh();
my $us = Socialtext::UserSet->new;
Socialtext::SQL::sql_begin_work();
$us->_create_insert_temp($dbh,'bulk');
my $memberroleid = Socialtext::Role->Member->role_id;
my $counter=0;
my $start = Time::HiRes::time;
for my $set (values %edges) {
    $counter++;
    #warn "$counter\n" unless ($counter % 10);
    #$us->add_role($set->[0],$set->[1],$memberroleid); 
    $us->_insert($dbh,$set->[0],$set->[1],$memberroleid,'bulk');
}
Socialtext::SQL::sql_commit();
diag("Took ". (Time::HiRes::time - $start) . " to generate user_sets in db");
#warn "Done creating user_sets";

my $connected = Property { 
    ##[x <- graph_gen ]##

    my $us = Socialtext::UserSet->new;
    my $from = $x->[0];
    my $to = $x->[1];
    my $usresult = $us->has_role($from, $to, $memberroleid) || 0;
    my $grresult = $graph->is_reachable($from, $to) || 0; #|| $graph->has_vertex($from, $to);
    my $success=($usresult == $grresult);
    
    diag ("FAILED:", 
        "From: $from\n",
        "To: $to\n",
        "UserSet connected: $usresult\n",
        "Graph connected: $grresult\n",
        Dumper($x), "\n",
        Dumper(keys %edges)) unless $success;
    $success;
}, name => "has_role works the same as Graph->is_reachable";

holds($connected);

{ use strict;
my $tcg_nr= Graph::TransitiveClosure->new($graph, reflexive => 0);
my $tcg_r = Graph::TransitiveClosure->new($graphb, reflexive => 1); 

#warn "finished creating transitive closure graph objects";
# get the edges from user_set_include_tc and this should be a supergraph of
# $tcg_nr and the SAME graph as $tcg_r
my $sth = sql_execute(
    q{SELECT DISTINCT from_set_id, into_set_id FROM user_set_path});
my @usedges =  @{$sth->fetchall_arrayref} ;

diag "Size of edges is ".scalar(@usedges);

ok all(sub{ $tcg_r->has_edge($_->[0],$_->[1]) },@usedges),
    "tcg_r has all uset edges (uset is a subset of tcg_r)";

eq_or_diff([
    sort map {"$_->[0],$_->[1]"}
    grep {$_->[0] != $_->[1]} @usedges
], [
    sort map {"$_->[0],$_->[1]"} $tcg_nr->edges
],
"all non-reflexive edges are in the tcg_nr graph (tgc_nr is a subset of uset)");
}

exit;

package graph_gen;

my %testpairs;

sub generate {
    my $OFFSET = 0x10000001;
    my ($first, $second) = (0, 0);
        while (($first == $second) || $testpairs{"$first/$second"}) {
            $first = $OFFSET+int(rand(256));
            $second = $OFFSET+int(rand(256));
        }
    return [$first, $second];
};
