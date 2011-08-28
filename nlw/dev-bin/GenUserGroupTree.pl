#!/usr/bin/env perl
# @COPYRIGHT@
use warnings;
use strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Socialtext::SQL qw/sql_execute/;
use Socialtext::UserSet;
use Socialtext::Role;
use Time::HiRes;


# Generate 10000 users - NOP
# generate 1000 groups level 4 - 4000-4999
# generate 100 groups level 3 - 3000-3999 
# generate 30 groups level 2 - 2000-2999
# generate 10 groups level 1 - 1000-1999
# generate 5 groups level 0 - 0 to 1000

# Add level 2 groups to 1, 2 to 3, 3 to 4, 4 to 5
# Add users to level 4

# Perform random has_role queries with users in random groups
#
#

my $now=time;
srand($now);
warn ("Using $now as seed\n");

my @groups = ();
my @levelgroups = ();
my @users = ();
my $dbh = Socialtext::SQL::get_dbh();
my $us = Socialtext::UserSet->new;
my $OFFSET = 0x10000001;
my @levels = (5,10,30,100,300);
my $usercount = 10_000;
my $numtrials = 100;

my $nothing = sql_execute(q{ DELETE FROM user_set_include });
$nothing = sql_execute(q{ DELETE FROM user_set_path});

$dbh->begin_work;
$us->_create_insert_temp($dbh,'bulk');
my $memberroleid = Socialtext::Role->Member->role_id;
warn "Level 0 has $levels[0] groups\n";
my %seen = ();
for my $level (1 .. (scalar(@levels)-1)) {
    warn "Adding for level $level\n";
    my $levelcount = $levels[$level];
    my $prevcount = $levels[$level-1];
    for my $count (1 .. $levelcount){
        my ($from, $to);
        do 
        {
            $from = $OFFSET+int(rand($levelcount))+($level*1000);
            $to = $OFFSET+int(rand($prevcount))+(($level-1)*1000);
        } while (exists $seen{"$from/$to"});
        $seen{"$from/$to"}=$to;
        #warn "Inserting $from, $to\n";
        $us->_insert($dbh, $from,$to, $memberroleid,"bulk");
   }
   warn "Added $levelcount for level $level\n";
}


my $toplevel = scalar(@levels)-1;
my $toplevelcount = $levels[$toplevel];

warn "Adding users to $toplevelcount level $toplevel groups\n";

for my $user (1..$usercount) {
    my $targetgroup;
    do {
        $targetgroup = $OFFSET+int(rand($toplevelcount))+($toplevel*1000);
    } while (exists $seen{"$user/$targetgroup"});
    $seen{"$user/$targetgroup"}=$targetgroup;
    #warn "adding $user to $targetgroup";
    warn "Added $user users\n" if not ($user % 100);
    $us->_insert($dbh, $user, $targetgroup, $memberroleid, "bulk");
};
$dbh->commit;

# pick random pairs and time has_role

my @froms = map {s/\/.+$//; $_} keys %seen;
my @tos = values %seen;
for my $trial (1..scalar($numtrials)) {
    my $from = $froms[int(rand(@froms))];
    my $to = $tos[int(rand(@tos))];
    my $start = Time::HiRes::time;
    $us->has_role($from, $to, $memberroleid);
    warn "Took ".(Time::HiRes::time - $start)." for $from/$to\n";
}
