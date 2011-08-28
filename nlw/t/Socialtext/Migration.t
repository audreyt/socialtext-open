#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::More tests => 29;
use Socialtext::AppConfig;
use File::Path qw/mkpath rmtree/;
use Socialtext::File qw/set_contents get_contents/;

BEGIN {
    use_ok 'Socialtext::Migration';
}

my $test_dir = Socialtext::AppConfig->test_dir();
my $migration_output_file = "/tmp/mig.$$";
END { unlink $migration_output_file if $migration_output_file }

Normal_migrations: {
    my $m = Socialtext::Migration->new;

    # clear the migration file
    my $state_file = $m->migration_state_file;
    like $state_file, qr($test_dir/etc/socialtext/migration\.state$);
    unlink $state_file;
    is $m->migration_number, 0;

    # create migration scripts
    my $state_dir = $m->migration_script_dir;
    like $state_dir, qr($test_dir/share/migrations$);

    First_migration: {
        setup_test_migration_scripts($state_dir, 1);
        $m->migrate;
        is $m->migration_number, 1;
        is get_contents($migration_output_file), "3\n";

        $m->migrate;
        is $m->migration_number, 1;
        is get_contents($migration_output_file), "3\n";
    }

    Fractional_migration: {
        setup_test_migration_scripts($state_dir, 1.1);
        $m->migrate;
        is $m->migration_number, 1.1;
        is get_contents($migration_output_file), "3\n";

        $m->migrate;
        is $m->migration_number, 1.1;
        is get_contents($migration_output_file), "3\n";
    }

    Second_migration: {
        setup_test_migration_scripts($state_dir, 2);
        $m->migrate;
        is $m->migration_number, 2;
        is get_contents($migration_output_file), "3\n";
    }

    Pre_check_fails_then_passes: {
        setup_test_migration_scripts($state_dir, 3, 'pre-check fails');
        eval { $m->migrate };
        like $@, qr/Pre-check failed/;
        is $m->migration_number, 2;
        ok !-e $migration_output_file;

        setup_test_migration_scripts($state_dir, 3);
        $m->migrate;
        is $m->migration_number, 3;
        is get_contents($migration_output_file), "3\n";
    }
}

Pre_check_passes_if_migration_already_run: {
    my $m          = Socialtext::Migration->new();
    my $state_file = $m->migration_state_file;
    setup_test_migration_scripts(
        $m->migration_script_dir, 3,
        'migration already run'
    );
    unlink $state_file;
    unlink $migration_output_file;
    $m->migrate;
    ok -e $state_file;
    is $m->migration_number, 3;
    ok !-e $migration_output_file;  # nothing should've actually run.
}

Dry_run: {
    my $m = Socialtext::Migration->new( dryrun => 1 );
    setup_test_migration_scripts($m->migration_script_dir, 1);
    unlink $m->migration_state_file;
    is $m->migration_number, 0;
    $m->migrate;
    is $m->migration_number, 0;
    ok !-e $migration_output_file;
}

Migrations_run_in_order: {
    my $m = Socialtext::Migration->new( dryrun => 1 );
    setup_test_migration_scripts($m->migration_script_dir, 1, 'out of order');
    my $cmd = "$^X -Ilib -MSocialtext::Migration -le "
              . "'print Socialtext::Migration->new(dryrun => 1)->migrate'";
    my $output = qx($cmd 2>&1);
    like $output, qr/migration 1.+migration 2.+migration 3/s;
}

Initialize_Migrations: {
    my $m = Socialtext::Migration->new( initialize => 1 );
    my $state_file = $m->migration_state_file;
    setup_test_migration_scripts( $m->migration_script_dir, 1, 'out of order' );
    unlink $state_file;
    unlink $migration_output_file;
    $m->migrate;
    ok -e $state_file;
    is $m->migration_number, 3;
    ok !-e $migration_output_file;
}

sub setup_test_migration_scripts {
    my $dir  = shift;
    my $num  = shift;
    my $type = shift || '';

    rmtree $dir;
    mkpath $dir or die "Can't mkpath $dir: $!";

    my @migrations = ($num);
    if ($type eq 'out of order') {
        @migrations = ($num + 2, $num, $num + 1);
    }

    for my $mignum (@migrations) {
        my $migration_dir = "$dir/$mignum-foo";
        mkpath $migration_dir or die "Can't mkdir $migration_dir: $!";
        _create_migration_scripts( $migration_dir, $type );
        unlink $migration_output_file;
    }
}

sub _create_migration_scripts {
    my $migration_dir = shift;
    my $type = shift || '';

    my $incrementor = <<EOT;
#!/bin/bash
COUNT=1
if [ -e "$migration_output_file" ]; then
    COUNT=\$(expr \$COUNT + `cat $migration_output_file`)
fi
echo \$COUNT > $migration_output_file
EOT
    my %file = (
        "pre-check" => $incrementor,
        "post-check" => $incrementor,
        "migration" => $incrementor,
    );

    if ($type eq 'migration already run') {
        $file{'pre-check'} = "#!/bin/bash\nexit 1\n";
    } elsif ($type eq 'pre-check fails') {
        $file{'pre-check'} = "#!/bin/bash\nexit 2\n";
    }

    for my $f (keys %file) {
        my $file = "$migration_dir/$f";
        set_contents($file, $file{$f});
        chmod 0755, $file or die "Can't chmod 0755 $file: $!";
    }
}
