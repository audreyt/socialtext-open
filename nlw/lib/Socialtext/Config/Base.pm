package Socialtext::Config::Base;
# @COPYRIGHT@

use strict;
use warnings;
use Carp qw(croak);
use File::Spec;
use YAML;
use Socialtext::AppConfig;
use Socialtext::Log qw(st_log);

sub new {
    my ($class, %opts) = @_;
    my $self = \%opts;
    bless $self, $class;

    # initialize, giving derived classes a chance to sanity check the config
    # and/or do any special initialization that's necessary
    eval { $self->init() };
    if ($@) {
        st_log->error( ref($self) . ": $@" );
        return;
    }

    # return the newly created object back to the caller
    return $self;
}

sub init { }    # STUB; just has to "not die a horrible death"

sub check_required_fields {
    my ($self, @fields) = @_;
    foreach my $field (@fields) {
        unless ($self->{$field}) {
            die "config missing '$field'\n";
        }
    }
}

sub config_filename {
    my $class = shift;
    my $yaml_file = File::Spec->catfile(
        Socialtext::AppConfig->config_dir(),
        $class->config_basename,
    );
    return $yaml_file;
}

sub config_basename {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    croak "config_basename() unimplemented in $class";
}

sub load {
    my $class = shift;
    my $filename = $class->config_filename();
    return $class->load_from($filename);
}

{
    # cache the parsed YAML for each file, so we don't have to keep RE-parsing
    # it every single time we want to read the config
    #
    # structure:
    #   $ConfigCache{$filename} = {
    #       last_modified   => $time_t,
    #       last_size       => $size_in_bytes,
    #       config          => \@config,
    #       };
    our %ConfigCache;

    sub load_from {
        my ($class, $file) = @_;

        # Load/Parse the YAML config file, caching the parsed YAML where
        # possible.
        #
        # Checks for "last modified time is the same as it was last time we
        # looked *and* the file size is also identical" (the *SAME* check we
        # do in ST::AppConfig for socialtext.conf).
        my @config;
        my $mod_time = (stat $file)[9];
        my $size     = -s _;
        if (   $ConfigCache{$file}
            && ((defined $mod_time) && ($mod_time == $ConfigCache{$file}{last_modified}))
            && ((defined $size)     && (    $size == $ConfigCache{$file}{last_size}))
        ) {
            @config = @{ $ConfigCache{$file}{config} };
        }
        else {
            @config = eval { YAML::LoadFile($file) };
            if ($@) {
                st_log->error( "$class\: error reading config in '$file'; $@" );
                return;
            }

            $ConfigCache{$file} = {
                last_modified   => $mod_time,
                last_size       => $size,
                config          => \@config,
            };
        }

        # Turn the parsed YAML into config objects
        my @objects;
        foreach my $cfg (@config) {
            my $obj = $class->new( %{$cfg} );
            unless ($obj) {
                st_log->error( "\$class: error with config in '$file'" );
                return;
            }
            push @objects, $obj;
        }
        return wantarray ? @objects : $objects[0];
    }
}

sub save {
    my ($class, @objects) = @_;
    my $filename = $class->config_filename();
    return $class->save_to( $filename, @objects );
}

sub save_to {
    my ($class, $file, @objects) = @_;
    # save un-blessed versions of the config objects (without the YAML header
    # that says that they came from ST::*::Config).
    if ($file) {
        local $YAML::UseHeader = 0;
        my @unblessed = map { {%{$_}} } @objects;
        return YAML::DumpFile( $file, @unblessed );
    }
    return;
}

1;

=head1 NAME

Socialtext::Config::Base - Base class for YAML based config parsers

=head1 SYNOPSIS

### To create your own custom Configuration object

  package MY::Config;

  use Class::Field qw(field const);
  use base qw(Socialtext::Config::Base);

  # specify name of config file
  const 'config_basename' => 'my.yaml';

  # list the fields in my config file
  field ...
  field ...
  ...

  # custom initialization routine
  sub init {
      my $self = shift;

      # make sure we've got all required fields
      my @required = (qw( ... ));
      $self->check_required_fields(@required);

      # other custom init/sanity checking
      ...
  }

### Using a configuration object

  use MY::Config;

  # load config, from default config filename
  @all_config = MY::Config->load();
  $first_cfg  = MY::Config->load();

  # load config, from explicit YAML file
  @all_config = MY::Config->load_from($filename);
  $first_cfg  = MY::Config->load_from($filename);

  # save config, to default filename
  MY::Config->save(@cfg_objects);

  # save config to explicit YAML file
  MY::Config->save_to($filename, @cfg_objects);

  # get path to configuration file
  $filename = MY::Config->config_filename();

  # instantiate config object, based on data hash
  $config = MY::Config->new(%opts);

=head1 DESCRIPTION

C<Socialtext::Config::Base> implements a base class for dealing with YAML
based configuration files.

=head1 METHODS

=over

=item B<$class-E<gt>new(%opts)>

Instantiates a new configuration object based on the provided hash of
configuration options.

=item B<$class-E<gt>config_basename()>

Returns the base name for the configuration file (e.g. F<foo.yaml>).

=item B<$class-E<gt>config_filename()>

Returns the full path to the configuration file (e.g.
F</etc/socialtext/foo.yaml>).

=item B<$class-E<gt>load()>

Loads the configuration from the default configuration file.

Contents of the configuration file are returned in an appropriate context.  In
a list context you get back a list of configuration objects for all of the
configurations stored in the YAML file.  In a scalar context, you get back a
configuration object for the I<first> configuration stored in the file.

=item B<$class-E<gt>load_from($filename)>

Loads the configuration from the named configuration file.

Contents returned in an appropriate context, as outlined in L<load()> above.

=item B<$class-E<gt>save(@objects)>

Saves the provided configuration objects out to the default configuration
file.  Any existing configuration present in the file is over-written.

=item B<$class-E<gt>save_to($filename, @objects)>

Saves the provided configuration objects out to the named configuration file.
Any existing configuration present in the file is over-written.

=back

The following additional methods are also available, but are for use by
derived classes:

=over

=item B<$self-E<gt>init()>

Custom initialization routine, to be implemented by derived classes (if they
actually need any custom initialization).  When called, the configuration
object will have I<already> been blessed.

If you need to do any custom initialization or sanity checking on the
configuration, B<this> is the place to do it.  In the event of error or some
sanity check failing, throw an exception with C<die()>; it'll get caughtt
automatically and an error will be recorded in F<nlw.log>

=item B<$self-E<gt>check_required_fields(@fields)>

Checks for the presence of each of the named C<@fields>, throwing an exception
if any of them are missing from the configuration in C<$self>.

This method has been provided to help derived classes implement some basic
sanity checking in their L<init()> methods.

=back

=head1 DERIVING YOUR OWN CONFIG CLASS

Deriving your own custom configuration class is pretty simple...

=over

=item * make C<Socialtext::Config::Base> your base class

=item * specify your L<config_basename()>

=item * list the fields your config file contains

=item * implement a custom L<init()> routine, if needed

=item * profit!

=back

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
