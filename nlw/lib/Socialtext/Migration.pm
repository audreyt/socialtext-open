package Socialtext::Migration;
# @COPYRIGHT@
use strict;
use warnings;
use File::Spec;
use Socialtext::AppConfig;
use Socialtext::File qw/get_contents set_contents/;
use Socialtext::System qw/shell_run/;

=head1 NAME

Socialtext::Migration - Provides a data migration framework

=head1 SYNOPSIS

  my $m = Socialtext::Migration->new;
  $m->migrate;

=head1 Methods

=head2 new

Create a new migration object.  Arguments:

=over 4

=item dryrun

If true, the migration steps will only be printed, not executed.

=back

=cut

sub new {
    my $class = shift;
    my $self = { @_ };
    bless $self, $class;
    return $self;
}

=head2 migrate

Perform the migration.

=cut

sub migrate {
    my $self = shift;
    my $current = $self->migration_number;
    my @migrations = find_migrations(migration_script_dir());

    return $self->initialize(@migrations) if $self->{initialize};

    my $ran = 0;
    for my $m (@migrations) {
        next if $m->{num} <= $current;

        print "Running migration $m->{num} - $m->{name}\n";
        eval { $self->run_migration($m->{dir}) };
        die "Migration $m->{num} - $m->{name} failed:\n$@\n" if $@;

        $self->record_migration($m);
        $ran++;
    }
    print "No migrations to run.\n" unless $ran;
}

=head2 initialize

Creates a migration.state file and seeds it with the highest numbered migration it can find.  None of the migrations are run.  This is useful if we're installing new software, and we don't need/want to run the older migrations.

=cut

sub initialize {
    my ( $self, @migrations ) = @_;
    my ($last_migration) = sort { $b->{num} <=> $a->{num} } @migrations;
    $self->record_migration($last_migration);
}

=head2 record_migration

Save the current migration number.

=cut

sub record_migration {
    my ( $self, $m ) = @_;
    set_contents( migration_state_file(), $m->{num} ) unless $self->{dryrun};
}

=head2 find_migrations

Returns a list of migrations found in the migration directory.

=cut

sub find_migrations {
    my $dir = shift;
    my (@migrations) = grep { -d $_ } glob("$dir/*");
    my @dirs;
    for my $migdir (@migrations) {
        unless( $migdir =~ m#.+/(\d+(?:\.\d+)?)-([-\w_]+)$# ) {
            next;
        }
        push @dirs, {
            dir => $migdir,
            num => $1,
            name => $2,
        };
    }
    return sort { $a->{num} <=> $b->{num} } @dirs;
}

=head2 run_migration

Run the scripts for a particular migration.

=cut

sub run_migration {
    my $self = shift;
    my $migdir = shift || '';
    die "'$migdir' is not a directory!" unless $migdir and -d $migdir;

    my @scripts = map { "$migdir/$_" } qw/pre-check migration post-check/;
    for (@scripts) {
        die "Script missing ($_)" unless -e $_;
        die "Script not -x ($_)"  unless -x $_;
    }

    if ($self->{dryrun}) {
        print map { "Would run: $_\n" } @scripts;
        return;
    }

    eval { shell_run($scripts[0]) };
    if ( $@ and $@ =~ /child exited with value 1$/m ) {
        return;  # Status of 1 indicates migraton already ran.
    }
    elsif ($@) {
        die "Pre-check failed: $@";
    }

    eval { shell_run($scripts[1]) };
    die "Migration failed: $@" if $@;

    eval { shell_run($scripts[2]) };
    die "Post-check failed: $@" if $@;
}

=head2 migration_number

Returns the current migration level from the state file.

=cut

sub migration_number {
    my $self = shift;
    my $num = 0;
    my $statefile = migration_state_file();
    if (-e $statefile) {
        chomp($num = get_contents($statefile) );
    }
    return $num;
}

=head2 migration_state_file

Returns the name of the migration state file.

=cut

sub migration_state_file {
    my $config_dir = Socialtext::AppConfig::config_dir();
    return "$config_dir/migration.state";
}

=head2 migration_script_dir

Returns the name of the directory containing migrations.

=cut

sub migration_script_dir {
    my $share = $ENV{HARNESS_ACTIVE}
        ? File::Spec->catdir(Socialtext::AppConfig->test_dir(), 'share')
        : Socialtext::AppConfig->new->code_base();
    return "$share/migrations";
}

1;

__END__

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

