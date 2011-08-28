# @COPYRIGHT@
package Socialtext::Schema;
use strict;
use warnings;
use File::Spec;
use Socialtext::Paths;
use Socialtext::AppConfig;
use Socialtext::System qw/shell_run/;
use Socialtext::SQL qw/sql_execute disconnect_dbh/;
use Socialtext::SystemSettings qw/get_system_setting set_system_setting/;

# Ignore PG environment variables that may be hanging around.
delete $ENV{PGUSER};
delete $ENV{PGDATABASE};

=head1 NAME

Socialtext::Schema - management of the database Schema

=head1 SYNOPSIS

  use Socialtext::Schema;

  Socialtext::Schema->new->sync();

=head1 DESCRIPTION

This class provides the behaviour to create, dump and upgrade the database
schema.  The schema is upgraded through a series of SQL patch files.

=head1 Package Methods

=head2 schema_dir()

Returns the directory schemas should be found in.

=cut

sub schema_dir {
    return $ENV{ST_SCHEMA_DIR} || File::Spec->catfile(
        Socialtext::AppConfig->config_dir(), 'db',
    );
}

=head1 Methods

=head2 new()

Create a new schema object.  Doesn't need any parameters.

=cut

sub new {
    my $class = shift;
    my $self = {
        @_,
    };
    bless $self, $class;
    return $self;
}

=head2 schema_name()

Returns the name of the schema to modify.

=cut

sub schema_name {
    my $self = shift;
    my %params = $self->connect_params();
    return $self->{schema_name} || $params{schema_name};
}

=head2 connect_params()

Returns a hash of the parameters to connect to the specified schema.

=cut

sub connect_params {
    my %params = Socialtext::AppConfig->db_connect_params();
    $params{psql} = "psql -U $params{user} $params{db_name}";
    return %params;
}

=head2 recreate()

Dumps, drops, and then re-creates the schema.

Optionally, you may pass in a list of key-value pairs as options.

=head3 recreate() options:

=over 4

=item no_dump

Don't do a database dump before dropping.  Useful for testing.

=back

=cut

sub recreate {
    my $self = shift;
    my %opts = @_;

    eval { $self->dump } unless $opts{no_dump};
    $self->dropdb(%opts);
    $self->createdb;
    my $file = $opts{'schema-file'} || $self->_schema_filename;
    $self->run_sql_file($file);
    $self->_add_required_data;
}

=head2 sync()

Create or update the schema to the latest version.

=cut

sub sync {
    my $self      = shift;
    my %sync_opts = @_;

    eval { $self->createdb } unless $sync_opts{no_create};
    my $current_version = $self->current_version;
    $self->_display("Current schema version is $current_version\n");
    if ($current_version == 0) {
        $self->run_sql_file($self->_schema_filename);
        $self->_display("Set up fresh schema\n");
        $self->_add_required_data;
    }
    else {
        my @scripts = $self->_update_scripts(
            from => $current_version,
            to   => $sync_opts{to_version},
        );
        if (@scripts) {
            eval { $self->dump } unless $sync_opts{no_dump};
    
            for my $s (@scripts) {
                $self->run_sql_file($s->{name});
            }
        }
        else {
            $self->_add_required_data;
            $self->_display("No updates necessary.\n");
            return;
        }

        print "\n";
        # Double check that we're up-to-date
        my $old_version = $current_version;
        $current_version = $self->current_version;
        if ($old_version == $current_version) {
            $self->_display("No updates were successfully applied.\n");
            return;
        }

        my $up_msg = "Updated from $old_version to $current_version.";
        if ( $self->_update_scripts(
                from => $current_version,
                to   => $sync_opts{to_version},
            )
            ) {
            $self->_display("Not all updates applied.  $up_msg\n");
            return;
        }

        # Only add the required data if we're at the very latest schema version
        if ($self->current_version == $self->ultimate_version) {
            $self->_add_required_data;
        }

        $self->_display("$up_msg  Schema is up-to-date.\n");
    }
}

sub _add_required_data {
    my $self = shift;
    return if $self->{no_add_required_data};
    return unless $self->schema_name eq 'socialtext';
    require Socialtext::Data;

    for my $c ( Socialtext::Data::Classes() ) {
        eval "require $c";
        die $@ if $@;

        if ($c->can('EnsureRequiredDataIsPresent')) {
            $self->_display("Adding required data for $c\n") 
                if $self->{verbose};
            $c->EnsureRequiredDataIsPresent;
        }
    }
}

sub _update_scripts {
    my $self = shift;
    my %opts = @_;
    my $from_version = $opts{from};
    my $to_version = $opts{to};

    my $schema_dir = $self->schema_dir;
    my $schema_name = $self->schema_name;
    my @all_scripts = 
        sort { $a->{from} <=> $b->{from} }
        map { m/-(\d+)-to-(\d+)\.sql/; { name => $_, from => $1, to => $2 } }
        glob("$schema_dir/$schema_name-*-to-*.sql");

    my $last_script = $all_scripts[-1];
    if ($last_script) {
        $self->{ultimate_version} = $last_script->{to};
    }

    my @to_run;
    for my $s (@all_scripts) {
        next if $from_version and $s->{from} < $from_version;
        last if $to_version   and $s->{to} > $to_version;
        push @to_run, {
            name => $s->{name},
            from => $s->{from},
            to => $s->{to},
        };
    }
    return @to_run;
}

=head2 escalate_privs()

Escalates our DB privileges to "superuser" status.

=cut

sub escalate_privs {
    my $self = shift;
    my %c = $self->connect_params();
    my $sudo = _sudo('postgres');
    $self->_db_shell_run("$sudo psql -U postgres $c{db_name} -c 'ALTER ROLE $c{user} SUPERUSER'");
}

=head2 revoke_privs()

Revokes any "superuser" privileges that we may have granted ourselves earlier
via a call to C<escalate_privs()>.

=cut

sub revoke_privs {
    my $self = shift;
    my %c = $self->connect_params();
    my $sudo = _sudo('postgres');
    $self->_db_shell_run("$sudo psql -U postgres $c{db_name} -c 'ALTER ROLE $c{user} NOSUPERUSER'");
}

=head2 version()

Prints out the current schema version.

=cut

sub version {
    my $self = shift;
    my $version = $self->current_version;
    my $schema = $self->schema_name;
    $self->_display("Schema $schema version: $version\n");
}

=head2 current_version()

Returns the version of the schema currently used by the database.

=cut

# If the "System" table exists, read the version out of that for our schema.
# Otherwise: if a certain table exists, assume it is version 1
# Otherwise: assume it is a fresh database, and return version 0
sub current_version {
    my $self = shift;
    my %c = $self->connect_params();

    my $version = 0;
    eval {
        local $SIG{__WARN__} = sub {}; # ignore warnings
        $version = get_system_setting($self->_schema_field);
    };
    return $version if $version;

    # If we couldn't find a version, check for a given SQL returning something
    # to determine if this is a fresh database, or just one without a version
    # yet.  The SQL we run is dependent on the schema being used.
    # Subclasses of this class can provide their own check method
    return 0 if $self->_is_fresh_database;
    return 1;
}

=head2 ultimate_version()

Returns the highest schema version number available.  This is not necessarily
the version we're upgrading to.

=cut

sub ultimate_version { shift->{ultimate_version} }

# This method allows us to do special things when migrating from systems
# before this module was refactored.
sub _is_fresh_database {
    my $self = shift;
    my $name = $self->schema_name;

    if ($name eq 'socialtext') {
        eval {
            local $SIG{__WARN__} = sub {}; # ignore warnings
            sql_execute(q{SELECT account_id FROM "Account" LIMIT 1});
        };
        return 0 if !$@;
    }
    return 1;
}

=head2 dump()

Dumps out the database to a sql dump file.

=cut

sub dump {
    my $self = shift;
    my %c    = $self->connect_params();

    # NOTE st-appliance-backup does not use this method (opting to dump the db
    # directly).  st-appliance-upgrade will set this environment variable,
    # opting to use `st-appliance-backup checkpoint` instead:
    if ($ENV{ST_DB_NODUMP}) {
        my $msg = $ENV{ST_UPGRADE_IN_PROGRESS}
            ? "skipping dump of $c{db_name}: an upgrade is in progress"
            : "skipping dump of $c{db_name}: ST_DB_NODUMP env-var is set";
        require Socialtext::Log;
        Socialtext::Log::st_log(info => $msg);

        open my $db_log, '>>', $self->_log_file;
        print $db_log "$msg\n";
        close $db_log;

        $self->_display("$msg\n");
        return;
    }

    my $time = time;
    my $dir  = Socialtext::Paths::storage_directory("db-backups");
    my $file = $self->{output};

    $file ||= $ENV{ST_DB_DUMPFILE}
        if $c{db_name} eq 'NLW';

    $file ||= Socialtext::File::catfile($dir, "$c{db_name}.$time.dump");

    # This is only likely to happen if we pass an output param to new().
    return if -f $file and not $self->{force};

    my @parms = (
        'pg_dump',
        '-Fc',
        '--disable-triggers',
        '-U' => $c{user},
        '-f' => $file,
    );
    push( @parms, '--password' => $c{password} )  if $c{password};
    push( @parms, '--host'     => $c{host} )      if $c{host};
    push( @parms, $c{db_name} );

    my $sudo = _sudo('www-data');
    $self->_db_shell_run( "$sudo @parms" );
    $self->_display("Dumped data to $file\n");
}

# If we're root, sudo to a different user, otherwise
# don't sudo, assume we're already the right user.
sub _sudo { $> ? '' : 'sudo -u ' . shift }

sub _display {
    my $self = shift;
    my $msg = shift;

    print $self->schema_name . ": $msg" unless $self->{quiet};
}

=head2 run_sql_file 

Executes the SQL file with psql.

=cut

sub run_sql_file {
    my $self = shift;
    my $file = shift;

    my %c = $self->connect_params();
    eval {
        $self->_db_shell_run("$c{psql} --set ON_ERROR_STOP=1 -e -f $file");
    };
    if ($@) {
        die "Schema update failed on file '$file'\n";
    }
}

=head2 set_schema_version 

Forcibly set the schema version to the given value in the "System" table.

Instead of relying on this method getting called, schema upgrade SQL scripts
*MUST* do a version bump within the same transaction as it's DDL updates.

=cut

sub set_schema_version {
    my $self = shift;
    my $new_version = shift;

    set_system_setting($self->_schema_field, $new_version);
}

sub _schema_field { shift->schema_name . '-schema-version' }

sub _schema_filename {
    my $self = shift;
    my $schema_file = File::Spec->catfile(
        schema_dir(), $self->schema_name . '-schema.sql',
    );
    return $schema_file;
}

=head2 createdb 

Creates the database for the schema to live in.

=cut

sub createdb {
    my $self = shift;
    my %c = $self->connect_params();
    disconnect_dbh();
    eval {
        my $sudo = _sudo('postgres');
        $self->_db_shell_run("$sudo createdb -T template0 -E UTF8 -O $c{user} $c{db_name}");
    };
    if (my $e = $@) {
        die $e;
    }
    $self->_createlang;
}

sub reset_db_locale {
    my $self = shift;
    my $locale = shift or die "locale needed";

    $locale =~ s/^[a-zA-Z]\K-/_/; # en-US => en_US
    $locale .= ".UTF-8" unless $locale =~ /\./ or $locale eq 'C'; # en_US => en_US.UTF-8

    my %c = $self->connect_params();
    disconnect_dbh();
    eval {
        my $sudo = _sudo('postgres');
        $self->_db_shell_run("$sudo createdb -l $locale -T template0 -E UTF8 -O $c{user} $c{db_name}_$$");
        $self->_db_shell_run("$sudo pg_dump $c{db_name} | $sudo psql $c{db_name}_$$");
        my $acting_user = $c{user};
        if ($> == 0) {
            $self->_db_shell_run("$sudo /etc/init.d/postgresql restart");
            $acting_user = 'postgres';
        }
        $self->_db_shell_run("$sudo dropdb $c{db_name}");
        $self->_db_shell_run(qq[$sudo psql -c 'ALTER DATABASE "$c{db_name}_$$" RENAME TO "$c{db_name}";' postgres $acting_user]);
    };
    if (my $e = $@) {
        die $e;
    }
    $self->_createlang;
}

# sets up plpgsql for the database schema
sub _createlang {
    my $self = shift;
    my %c = $self->connect_params();

    eval {
        # grep returning 1 (== no match) will cause shell_run to die
        local $Socialtext::System::SILENT_RUN = 1;
        shell_run("createlang -U $c{user} -l $c{db_name} | grep plpgsql"
                  . " > /dev/null");
    };
    if ($@) {
        # If we're running as root, we need to run createlang as postgres
        # If we're not root, then we're likely in a dev-env.
        my $sudo = _sudo('postgres');
        $self->_db_shell_run("$sudo createlang plpgsql $c{db_name}");

        # TODO: now that we're escalating privs before, we should be able to
        # run createlang as the usual db user, removing the need to sudo
        # above.
    }
}

=head2 dropdb 

Removes the current database, without dumping it.

=cut

sub dropdb {
    my $self   = shift;
    my %opts   = @_;
    my $no_die = $opts{no_die_on_drop} ? '-' : '';
    my %c = $self->connect_params();

    disconnect_dbh(); # disconnect so as not to kill self

    my $sudo = _sudo('postgres');

    if (-f '/usr/local/sbin/kill_pg_backends' && $> != 0) {
        eval {
            shell_run("sudo -u postgres /usr/local/sbin/kill_pg_backends");
        };
        warn "Error with kill_pg_backends: $@" if $@;
    }

    $self->_db_shell_run("$no_die$sudo dropdb $c{db_name}");
}

sub _log_file { Socialtext::Paths::log_directory() . '/st-db.log' }

sub _db_shell_run {
    my $self = shift;
    my $command = shift;
    my $log_file = _log_file();
    local $Socialtext::System::SILENT_RUN = !$self->{verbose};
    shell_run($command . " >> $log_file 2>&1");
}

1;

__END__

=head1 NAME

Socialtext::Schema - management of the database Schema

=head1 SYNOPSIS

  use Socialtext::Schema;

  # From command line:
  Socialtext::Schema::Run();

  # Recreate the database
  Socialtext::Schema->new->recreate();

=head1 DESCRIPTION

This class provides the behaviour to create, dump and upgrade the database
schema.  The schema is upgraded through a series of SQL patch files.

=cut

