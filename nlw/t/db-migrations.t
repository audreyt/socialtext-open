#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use YAML;
use Test::Differences;
use File::Path 'mkpath';
use File::Copy qw/copy/;
use Socialtext::Paths;
use Socialtext::System qw/shell_run/;
use Socialtext::Schema;
use Socialtext::AppConfig;
use Test::Socialtext;

###############################################################################
# Fixtures: clean base_layout destructive
# - need to start from a clean slate; we're going to build DB from scratch
# - we're destructive; you'll want to recreate the DB when we're done
fixtures(qw( clean base_layout destructive ));

my $CURR_RELEASE  = 'lolcat';
my $test_dir      = Socialtext::AppConfig->test_dir();
my $real_dir      = 'etc/socialtext/db';
my $fake_dir      = "$test_dir/etc/socialtext/db";
my $log_dir       = Socialtext::Paths::log_directory();
my $backup_dir    = Socialtext::Paths::storage_directory('db-backups');
my $START_SCHEMA  = 131; # the version in the pg-9 schema file
my $latest_schema = $START_SCHEMA; # default, will change to actual latest below

# Set up directories and copy schema migrations into our test directory
{
    mkpath $fake_dir unless -d $fake_dir;
    ($latest_schema) = reverse sort { $a <=> $b }
                        map { m/-\d+-to-(\d+)\.sql/ }
                       glob("$real_dir/socialtext-*-to-*.sql");

    for my $cur ($START_SCHEMA .. $latest_schema) {
        my $prev = $cur - 1;
        my $file = "socialtext-$prev-to-$cur.sql";
        open my $in, "$real_dir/$file"
            or die "Can't open $real_dir/$file: $!";
        open my $out, ">$fake_dir/$file"
            or die "Can't open $fake_dir/$file: $!";
        while (<$in>) {
            # change backup directories that don't exist here
            s{/var/www/socialtext/storage/db-backups}{$backup_dir}g;
            print $out $_;
        }
        close $out or die "Can't write to $fake_dir/$file: $!";
    }

    copy "$real_dir/socialtext-pg-9.sql" => "$fake_dir/socialtext-pg-9.sql";
}

plan tests => ($latest_schema - $START_SCHEMA) + 3;

# Set up the initial database
diag "loading config...\n";
my $schema_config = YAML::LoadFile("$real_dir/socialtext.yaml");

diag "Creating schema object...\n";
my $schema = Socialtext::Schema->new(%$schema_config, verbose => 1);
$schema->{no_add_required_data} = $schema->{quiet} = 1;

diag "Recreating schema...\n";

ok -r "$fake_dir/socialtext-pg-9.sql", "base postgres 9 schema exists";
eval {
    $schema->recreate(
        'schema-file'    => "$fake_dir/socialtext-pg-9.sql",
        'no_die_on_drop' => 1,
    );
};
if ($@) {
    system("tail -n 20 $test_dir/log/st-db.log");
    exit;
}

# Check each schema
for ( $START_SCHEMA+1 .. $latest_schema ) {
    eval {
        $schema->sync( to_version => $_, no_dump => 1, no_create => 1)
    };
    if ($@) {
        system("tail -n 20 $log_dir/st-db.log");
        die "Can't continue";
    }
    pass "Schema migration $_";
}

# Run schema changes for current release
eval {
    $schema->run_sql_file("$real_dir/socialtext-$CURR_RELEASE.sql")
        if -f "$real_dir/socialtext-$CURR_RELEASE.sql";
};
if ($@) {
    system("tail -n 20 $log_dir/st-db.log");
    die "Can't continue";
}
pass "Schema changes for current release";

# Now check that the final result is the same as socialtext-schema.sql
my $generated_schema = "$test_dir/generated-schema.sql";
shell_run "dump-schema $generated_schema";

# Note: whitespace amount changes are ignored with -b
my $diff = qx{diff -dub $real_dir/socialtext-schema.sql $generated_schema};
is $diff, '', "Zero length diff";

if ($ENV{INSTALL_SCHEMA}) {
    shell_run("cp $generated_schema $real_dir/socialtext-schema.sql");
}
