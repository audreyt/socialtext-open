# @COPYRIGHT@
package Socialtext::Paths;
use strict;
use warnings;

use Socialtext::AppConfig;
use Socialtext::File;
use Socialtext::Exceptions qw( param_error );

=head1 NAME

Socialtext::Paths - Returns directory and filenames for NLW

=head1 SYNOPSIS

  my $workspace_db = Socialtext::Paths::workspaces_db();

=head1 DESCRIPTION

This module knows how to calculate paths to various important
directories and files for the NLW application.  Most functions take
either a single optional argument, a workspace name, or no argument at
all.

=head1 FUNCTIONS

This module provides the following functions:

=head2 htgroup_db_directory($ws_name)

=head2 plugin_directory($ws_name)

These functions each return the appropriate directory for the given
workspace name.  If not given a name, they return the root for the
specific type of directory.

=cut
sub plugin_directory         { _per_workspace_dir( 'plugin', @_ ) }
sub change_event_queue_dir   { Socialtext::AppConfig->change_event_queue_dir }
sub change_event_queue_lock  { change_event_queue_dir() . '/lock' }

=head2 system_plugin_directory()

Returns the path to the system plugin directory wherein plugins
may store supra-workspace data.

=cut
# This one is formed just like the per-workspace ones, but no workspace name.
sub system_plugin_directory { _per_workspace_dir('plugin.system', @_) }

=head2 pid_file( $program_name )

Returns the path to the PID file for the given program.

=cut

sub pid_file {
    return Socialtext::AppConfig->pid_file_dir . "/$_[0].pid"
}

=head2 user_directory($ws_name, $email)

This function can take two optional parameters.  The first is a
workspace name and the second is an email address.

=cut

sub user_directory {
    my $dir = _per_workspace_dir( 'user', @_ );
    return @_ == 2
        ? Socialtext::File::catdir( $dir, $_[1] )
        : $dir;
}

=head2 storage_directory([String $subdir])

Location of the generic storage directory.  You can use it for whatever you
want which doesn't fit into the per-workspace page/plugin data model. 

Optionally you can pass in a string which will be added to the storage path as
a subdir.  No guarantee is made that the directory exists.

=cut

sub storage_directory {
    my $subdir = shift;
    $subdir = "" unless defined $subdir;
    return Socialtext::File::catdir(
        _data_relative_path("storage"),
        $subdir
    );
}

sub _per_workspace_dir {
    my $subdir = shift;
    my @id = shift || ();

    return Socialtext::File::catdir( Socialtext::AppConfig->data_root_dir(), $subdir, @id  );
}

sub _data_relative_path {
    my $basename = shift;

    return Socialtext::File::catfile( Socialtext::AppConfig->data_root_dir, "$basename" );
}

=head2 aliases_file()

Looks for a writeable aliases.deliver file, first in F</etc> and then
C<< Socialtext::AppConfig->data_root_dir() >>. If the file does not exist in
the given directory, but the directory is writeable, then it returns a
path using that directory.

=cut

sub aliases_file {
    for my $file ( '/etc/aliases.deliver',
                   Socialtext::File::catfile( Socialtext::AppConfig->data_root_dir(), 'aliases.deliver' )
                 ) {
        if ( -w $file
             or ( ! -f _ and -w File::Basename::dirname($file) )
           ) {
            return $file;
        }
    }
}

=head2 log_directory()

Returns the location that log files should be stored at.

=cut

sub log_directory {
    if (Socialtext::AppConfig->startup_user_is_human_user()) {
        return Socialtext::AppConfig::_user_root() . '/log'
    }
    return '/var/log';
}

=head2 cache_directory ($dir)

Returns the location of a specific directory for caching files.

=cut

sub cache_directory {
    my $subdir = shift;
    $subdir = "" unless defined $subdir;
    return Socialtext::File::catdir(
        Socialtext::AppConfig::_cache_root_dir(),
        $subdir
    );
}

1;
