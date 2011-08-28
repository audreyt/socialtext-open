#!/usr/bin/env perl
# @COPYRIGHT@
use warnings;
use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";

#
# produce an anonymized dump of the user graph in the database.
# Correct as of schema version 94.
#
# Usage: sudo -u www-data ./anon-user-graph-dump.pl | bzip2 -c - > anon-user-graph.yaml.bz2
#

use Socialtext::SQL qw/get_dbh/;
use YAML qw/Dump/;

my $dbh = get_dbh();

my %queries = (
    Role => q{SELECT * FROM "Role"},
    Permission => q{SELECT * FROM "Permission"},
    Account => q{SELECT account_id FROM "Account"},
    Workspace => q{SELECT workspace_id,account_id FROM "Workspace"},
    WorkspaceRolePermission => q{SELECT workspace_id,role_id,array_accum(permission_id) AS permission_ids FROM "WorkspaceRolePermission" GROUP BY workspace_id, role_id ORDER BY workspace_id, role_id},
    System => q{SELECT * FROM "System"},
    groups => q{SELECT group_id,primary_account_id FROM groups},
    users => q{SELECT user_id,primary_account_id FROM users NATURAL JOIN "UserMetadata"},
    user_set_include => q{SELECT * FROM user_set_include},
    user_set_plugin => q{SELECT user_set_id, array_accum(plugin) AS plugins FROM user_set_plugin GROUP BY user_set_id},
    user_set_plugin_pref => q{SELECT * FROM user_set_plugin_pref},
);

while (my ($label, $query) = each %queries) {
	my $sth = $dbh->prepare($query);
	$sth->execute();
	# make keys lexical for readability
	print Dump({
		aa_label => $label,
		bb_names => $sth->{NAME},
		zz_data => $sth->fetchall_arrayref(),
	});
}
