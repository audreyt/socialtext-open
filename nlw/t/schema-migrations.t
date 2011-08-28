#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::More;
use Socialtext::File qw/get_contents/;
use FindBin;

my $schema_dir  = "$FindBin::Bin/../etc/socialtext/db/";
my $schema_file = "$schema_dir/socialtext-schema.sql";
my @sql_patches = sort {
    (my $aver = $a) =~ s/.+-to-(\d+)\.sql/$1/;
    (my $bver = $b) =~ s/.+-to-(\d+)\.sql/$1/;
    return $aver <=> $bver
} glob("$schema_dir/*-to-*.sql");

plan tests => @sql_patches * 4 + 8;

Schema_is_okay: {
    ok -d $schema_dir;
    ok -e $schema_file;

    my $highest = $sql_patches[-1];
    (my $to_version = $highest) =~ s/.+-to-(\d+)\.sql/$1/;
    my $schema = get_contents($schema_file);
    like $schema,
        qr/\QINSERT INTO "System" VALUES ('socialtext-schema-version', '$to_version')\E/,
        'schema includes setting the version';

    like $schema,
        qr/\QCREATE FUNCTION is_page_contribution/,
        'schema has the is_page_contribution function';

    like $schema,
        qr/CREATE INDEX ix_page_events_contribs_actor_time\b/,
        "index on the is_page_contribution function didn't get accidentally dropped";

    like $schema,
        qr/ADD CONSTRAINT workspace_created_by_user_id_fk[^;]+ON DELETE RESTRICT;/,
        "foreign key on Workspace.created_by_user_id doesn't cascade deletes";

    like $schema,
        qr/ADD CONSTRAINT page_creator_id_fk[^;]+ON DELETE RESTRICT;/,
        "foreign key on page.creator_id doesn't cascade deletes";

    like $schema,
        qr/ADD CONSTRAINT page_last_editor_id_fk[^;]+ON DELETE RESTRICT;/,
        "foreign key on page.last_editor_id doesn't cascade deletes";
}

Migrations_are_okay: {
    for my $s (@sql_patches) {
        (my $name = $s) =~ s#.+/##;
        (my $to_version = $name ) =~ s#socialtext-\d+-to-(\d+)\.sql#$1#;
        my $contents = get_contents($s);
        like $contents, qr/^BEGIN;/is,  "$s starts with BEGIN";
        like $contents, qr/COMMIT;$/is, "$s ends with COMMIT";
        like $contents, qr/socialtext-schema-version/,
            'patch file mentions the version number';

        # Single quotes are optional for the value field.
        like $contents, 
             qr/(?:SET\s+value\s+=\s+'?$to_version'?
                 |\('socialtext-schema-version',\s+'?$to_version'?\))/x,
            'patch updates socialtext-schema-version to correct number.';
    }
}

