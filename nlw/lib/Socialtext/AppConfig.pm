package Socialtext::AppConfig;
# @COPYRIGHT@
use strict;
use warnings;

use Cwd ();
use File::Basename ();
use File::Spec ();
use File::Path qw/mkpath/;
use Socialtext::Hostname;
use Socialtext::Validate qw(
    validate validate_with
    SCALAR_TYPE BOOLEAN_TYPE
    NONNEGATIVE_INT_TYPE POSITIVE_INT_TYPE
    FILE_TYPE DIR_TYPE
    URI_TYPE SECURE_URI_TYPE EMAIL_TYPE
);
use User::pwent;
use YAML ();
use YAML::Dumper;
use Socialtext::Build qw( get_build_setting get_prefixed_dir );
use Unicode::Collate;

our $Auto_reload = 1;

# We capture this at load time and then will later check
# $Current_user->uid to see if the user _when the module was loaded_
# was root. We do not want to check $> later because under mod_perl
# this will change once Apache forks its children.
my $StartupUser = getpwuid($>);

my @obviously_not_human_users = qw( www-data wwwrun nobody daemon );
my %obviously_not_human_users = map {($_,1)} @obviously_not_human_users;

sub is_testrunner {
    return $StartupUser->name eq 'hudson';
}

sub startup_user_is_human_user {
    return 0 if $obviously_not_human_users{ $StartupUser->name };

    # XXX - This is Debian and OSX specific. I doubt there's a 100%
    # correct way of doing this, since people can do any crazy thing
    # on their systems they want, but it'd be nice to have this work
    # on any system that was compliant with its distro/OSs usre
    # numbering scheme.
    return 1 if $StartupUser->uid >= 500;
    return 1 if is_testrunner();

    return;
}

# Used _only_ for testing
sub _set_startup_user { shift; $StartupUser = getpwuid(shift) }

my %Options = _parse_pod_for_options();

sub _parse_pod_for_options {
    my $pm_file = $INC{'Socialtext/AppConfig.pm'};
    open my $fh, '<', $pm_file
        or die "Cannot read $pm_file: $!";

    my $file = do { local $/; <$fh> };

    my ($pod) = $file =~ m{
        =head1\ CONFIGURATION\ VARIABLES  # the start of the relevant section
         .+?                               # ignore the bit up to the first =head2
         (?=
           =head2)                         # don't eat this =head2, we
                                           # want it in the capture

         (.+)                              # the config variables
         (?:=head1|=cut)                   # this marks the end of the config variables
       }xs;

    my %opts;
    while ( $pod =~ m{\G
                     =head2\ (\w+)               # the variable name
                     (.+?)                       # the description
                     \s+
                     (?:                         # it can have a default, or be optional, but not both
                       (?:^Default:\s+(.+?)$)    # a default
                       |
                       (^Optional\.)             # or it's optional, but not both
                     )?                          # maybe it has neither
                     \s*
                     (?:^=for\ code\ default\s*=>\s* (.+?)$)? # the default is some subroutine
                     \s* # it is bullshit this ^^^ needs to be before this vvv
                     (?:^=for\ code\ type\s*=>\s*(.+?)$)      # the type, required
                     \s+
                    }gxsm ) {

        my ( $name, $desc, $default_string, $optional, $default_code, $type )
            = ( $1, $2, $3, $4, $5, $6 );

        # This means the regex ate through the beginning of one or
        # more config variables following the current one until it
        # found a type.
        #
        # REVIEW - if the last item is missing a type, this won't
        # catch it, the regex will just stop matching.
        if ( $default_string && ( $default_string =~ /=head2/ ) ) {
            die "The POD for $name is missing a type\n";
        }

        $opts{$name} = { description => $desc };
        if ( defined $default_string ) {
            # print " $default_string -";
            $opts{$name}{default} = $default_string;
        }
        elsif ( defined $default_code ) {
            $opts{$name}{default} = eval $default_code;
            die $@ if $@;
            # print " $default_code == $opts{$name}{default} -";
        }
        elsif ( defined $optional ) {
            # print " optional -";
            $opts{$name}{optional} = 1;
        }
        # print "\n";
    }

    return %opts;
}

sub is_default {
    my $self = shift;
    my $name = shift;
    return $self->$name eq $Options{$name}{default};
}

sub _default_data_root {
    return ( startup_user_is_human_user()
             ? File::Spec->catdir( _user_root(), 'root' )
             : get_prefixed_dir("webroot"));
}

sub _default_code_base {
    return (
        startup_user_is_human_user()
        ? File::Spec->catdir( _user_checkout_dir(), 'share' )
        : get_prefixed_dir("sharedir")
    );
}

{
    # hold the initial CWD of when we we started, so we can fix up relative
    # paths here if needed.
    my $initial_cwd = Cwd::cwd();

    sub _user_checkout_dir {
        my $base = File::Basename::dirname(__FILE__);

        my $dir = Cwd::abs_path( 
            File::Spec->catdir( $ENV{ST_SRC_BASE}, 'socialtext', 'nlw' )
        );

        return $dir if defined $dir && -d $dir;

        return Cwd::abs_path(
            File::Spec->catdir(
                (
                    File::Spec->file_name_is_absolute($base)
                    ? ()
                    : $initial_cwd
                ),
                $base,
                File::Spec->updir,
                File::Spec->updir
            )
        );
    }
}

sub _default_template_compile_dir {
    return File::Spec->catdir( _cache_root_dir(), 'tt2' );
}

sub _default_formatter_cache_dir {
    return File::Spec->catdir( _cache_root_dir(), 'formatter' );
}

sub _default_change_event_queue_dir {
    my $root =
        $ENV{HARNESS_ACTIVE}
            ? _user_root()
            : get_prefixed_dir('spooldir');
    return File::Spec->catdir( $root, 'ceq' )
}

sub _cache_root_dir {
    return ( startup_user_is_human_user()
             ? File::Spec->catdir( _user_root(), 'cache' )
             : get_prefixed_dir('cachedir'));
}

sub _default_pid_file_dir {
    return ( startup_user_is_human_user()
             ? File::Spec->catfile( _user_root(), 'run' )
             : get_prefixed_dir('piddir'));
}

sub _default_admin_script {
    my $script = File::Spec->catfile( bin_path(), 'st-admin' );
    return ( ( -x $script ) ? $script : "/usr/local/bin/st-admin" );
}

=head2 bin_path()

Returns the location that executable scripts should be stored at.

=cut

sub bin_path {
    if ( startup_user_is_human_user() ) {
        return File::Spec->catfile( _user_checkout_dir(), 'bin' );
    }
    return '/usr/bin';
}

sub _default_db_name {
    return 'NLW' unless startup_user_is_human_user();

    my $name = 'NLW_' . $StartupUser->name;
    $name .= '_testing' if $ENV{HARNESS_ACTIVE};

    my $slot = test_slot();
    $name .= "_$slot" if $slot;

    return $name;
}

sub _default_solr_base {
    my $base = 'http://localhost:8983/solr';
    return "$base/core0" unless startup_user_is_human_user();

    my $name = $StartupUser->name;
    $name .= '_testing' if $ENV{HARNESS_ACTIVE};

    my $slot = test_slot();
    $name .= "_$slot" if $slot;

    return "$base/$name";
}

sub _default_auth_token_soft_limit { return 86400 * 13; }
sub _default_auth_token_hard_limit { return 86400 * 14; }
sub minimum_auth_token_limit       { return 86400; }
sub maximum_auth_token_limit       { return 86400 * 365; }

sub auth_token_soft_limit {
    my $self = shift;
    $self = $self->instance() unless ref($self);

    my $limit = $self->{config}{auth_token_soft_limit};

    # Force a minimum if they've tried to set to <=0
    # - allow for low values, though, to facilitate testing
    $limit = minimum_auth_token_limit() if ($limit <= 0);

    # Enforce maximum value
    my $max = maximum_auth_token_limit();
    $limit = $max if ($limit > $max);

    return $limit;
}

sub auth_token_hard_limit {
    my $self = shift;
    $self = $self->instance() unless ref($self);

    my $limit = $self->{config}{auth_token_hard_limit};

    # Force a minimum if they've tried to set to <=0
    # - allow for low values, though, to facilitate testing
    $limit = minimum_auth_token_limit() if ($limit <= 0);

    # Enforce maximum value
    my $max = maximum_auth_token_limit();
    $limit = $max if ($limit > $max);

    return $limit;
}

sub _default_schema_name { 'socialtext' }

sub _default_db_user {
    return ( startup_user_is_human_user()
             ? $StartupUser->name
             : 'nlw' )
}

sub _default_locale {
    return get_build_setting('default-locale') || 'en';
}

sub _user_root {
    if ( $ENV{HARNESS_ACTIVE} ) {
        my $dir;
        my $test_dir = test_dir();

        # Under mod_perl, Apache will already have chdir'd to /
        if ( $ENV{MOD_PERL} ) {
            $dir = Apache->server_root_relative();
            $dir =~ s{(.+$test_dir).*}{$1};
        }
        else {
            $dir = File::Spec->catdir( _user_checkout_dir(), $test_dir );
        }

        die "Cannot find the user root with the HARNESS_ACTIVE env var set\n"
            unless $dir;

        # Untaint this so tests pass with tainting on.
        # REVIEW: This untainting should be more stringent.
        ($dir) = $dir =~ /(.+)/;

        return $dir;
    }
    else {
        return File::Spec->catdir( $StartupUser->dir, '.nlw' );
    }
}

sub Options { keys %Options }

# XXX be smarter about reloading here. We don't want to check
# every single time.
for my $f ( keys %Options ) {
    next if __PACKAGE__->can($f);

    my $sub = sub {
        return $1
            if exists $ENV{NLW_APPCONFIG}
            and $ENV{NLW_APPCONFIG} =~ /(?:^|,)$f=(.*?)(?:$|,)/;

        my $self = shift;
        $self = $self->instance()
            unless ref $self;

        $self->_reload_if_modified;
        return $self->{config}{$f};
    };
    no strict 'refs';
    *{$f} = $sub;
}

my $Self;
sub instance {
    my $class = shift;

    return $Self || $class->new();
}

sub clear_instance {
    $Self = undef;
}

sub new {
    my $class = shift;
    my %p = @_;

    # REVIEW:
    #
    # The goal here is to allow gen-config to call Socialtext::AppConfig->new
    # to load the old file Socialtext::AppConfig->new() without making that
    # the new singleton instance, since it's full of bogus
    # junk. That's why we don't save it as a singleton if file is
    # provide.
    #
    # However, this module's own _reload_if_modified calls new() with
    # a file parameter, but in that case we _do_ want to save the new
    # object as the singleton instance, thus the singleton
    # parameter. This is all pretty gross, and could use some review.
    # The unit tests also use _singleton for testing.
    my $save_singleton = $p{file} ? 0 : 1;
    $save_singleton ||= $p{_singleton};

    my $default_config_file = _find_config_file() || '';
    %p = validate(
        @_, {
            file       => FILE_TYPE( default => $default_config_file ),
            strict     => BOOLEAN_TYPE( default => 1 ),
            _singleton => BOOLEAN_TYPE( default => 0 ),
        },
    );

    my $config_from_file =
        $p{file} && -f $p{file} ? YAML::LoadFile( $p{file} ) : {};
    # remove deprecated option for {bz: 4347}
    delete $config_from_file->{benchmark_mode} if $config_from_file;

    my $real_config = validate_with(
        params      => ( $config_from_file || {} ),
        spec        => \%Options,
        allow_extra => $p{strict},
    );

    my $self = bless {}, $class;

    $self->{original_data} = $config_from_file;
    $self->{config} = $real_config;

    $self->{file} = $p{file};
    $self->{last_mod_time} = time;
    $self->{last_size}     = (-s $p{file}) || 0;

    $Self = $self
        if $save_singleton;

    return $self;
}

sub file {
    my $self = shift;
    $self = $self->instance()
        unless ref $self;

    return $self->{file}
}

# really just provided to help with testing
sub _last_mod_time { $_[0]->instance->{last_mod_time} }

sub _reload_if_modified {
    my $self = shift;

    return unless $Auto_reload;

    return unless -f $self->{file};

    # We check size as well as last mod time because at least in the
    # tests, the file can be created, read, and modified in less than
    # one second.  The size check doesn't require an extra system call
    # so it's cheap to do.  This still isn't 100% accurate, but unless
    # we can get sub-second resolutions out of stat(), it's as good as
    # it gets.
    my $mod_time = ( stat $self->{file} )[9];
    my $size     = -s _;

    return
        if $mod_time <= $self->{last_mod_time}
        && $size == $self->{last_size};

    my $reload = (ref $self)->new(
        file       => $self->{file},
        # REVIEW - bleah, this is gross
        _singleton => ( $Self and $Self == $self ),
    );

    %$self = %$reload;
}

sub _find_config_dirs {
    my @dirs;

    if ( !$ENV{HARNESS_ACTIVE} ) {
        push @dirs, '/etc/socialtext';
        if ( startup_user_is_human_user() ) {
            unshift @dirs, $StartupUser->dir . '/.nlw/etc/socialtext';
        }
    }
    else {
        my $test_dir = _user_root() . '/etc/socialtext';
        push @dirs, $test_dir;
        unless (-d $test_dir) {
            mkpath $test_dir or die "Can't mkpath $test_dir: $!";
        }
    }

    return @dirs;
}

sub config_dir {
    my $self = shift;

    my @dirs = _find_config_dirs();
    unshift @dirs, File::Basename::dirname($self->file)
        if $self && ref($self);

    foreach my $dir (@dirs) {
        return $dir if -d $dir;
    }
}

sub test_slot {
    return $ENV{HARNESS_JOB_NUMBER};
}

sub test_dir {
    my $slot = test_slot();
    my $base = 't/tmp';
    return $slot ? "$base/$slot" : $base;
}

sub _find_config_file {
    my @dirs = _find_config_dirs();
    my @files = map { $_ . "/socialtext.conf" } @dirs;

    unshift @files, $ENV{NLW_CONFIG}
        if ( defined $ENV{NLW_CONFIG} and length $ENV{NLW_CONFIG} );

    foreach my $f (@files) {
        return $f if -r $f;
    }
}

sub db_connect_params {
    my $self = shift;
    $self = $self->instance()
        unless ref $self;

    my %connect_params = ( 
        db_name => $self->db_name(),
        schema_name => $self->schema_name(),
    );

    for my $field (qw( db_user db_password db_host db_port )) {
        next unless defined $self->$field();

        ( my $k = $field ) =~ s/^db_//;

        $connect_params{$k} = $self->$field();
    }

    if (($connect_params{host} eq 'localhost')
            or (!$connect_params{host} and $^O eq 'darwin')) {
        $connect_params{host} = '127.0.0.1';
    }

    return %connect_params;
}

sub shortcuts_file {
    my $self = shift;
    $self = $self->instance()
        unless ref $self;

    return $self->{config}{shortcuts_file}
        if defined $self->{config}{shortcuts_file};

    if ( $self->{file} ) {
        my $file = File::Spec->catfile(
            File::Basename::dirname( $self->{file} ),
            'shortcuts.yaml',
        );

        if ( -f $file ) {
            $self->{config}{shortcuts_file} = $file;
            return $file;
        }
    }
}

sub MAC_secret {
    my $self = shift;
    $self = $self->instance()
        unless ref $self;

    return $self->{config}{MAC_secret}
        if $self->{config}{MAC_secret};

    # REVIEW - is there a better way to distinguish between a real
    # installation and a developer installation?
    die "Cannot generate a MAC secret once app has started except in dev environments"
        unless $StartupUser->dir =~ m{^(?:/home|/Users)} || is_testrunner();

    return $StartupUser->name . ' needs a better secret';
}

sub has_value {
    my $self = shift;
    $self = $self->instance()
        unless ref $self;

    my $key = shift;

    return exists $self->{config}{$key};
}

sub is_appliance {
    return 1 if $ENV{NLW_IS_APPLIANCE};

    my $self = shift;
    $self = $self->instance()
        unless ref $self;

    $self->{is_appliance} ||=
        -e '/etc/socialtext/appliance.conf'
        ? 1
        : 0;

    return $self->{is_appliance};
}

sub is_dev_env { return !shift->is_appliance }

sub set {
    my $self = shift;
    $self = $self->instance()
        unless ref $self;

    my %p = @_;

    # Clear the json cache so activities widgets get the new limit
    require Socialtext::JSON::Proxy::Helper;
    Socialtext::JSON::Proxy::Helper->PurgeCache;

    my %spec = map { $Options{$_} ? ( $_ => $Options{$_} ) : () } keys %p;
    %p = validate( @_, \%spec );

    while ( my ( $k, $v ) = each %p ) {
        $self->{config}{$k} = $v;
        $self->{original_data}{$k} = $v;
    }

    # Warn about potentially poor config values
    foreach my $limit (qw( auth_token_soft_limit auth_token_hard_limit )) {
        if (exists $p{$limit}) {
            my $minimum = minimum_auth_token_limit();
            my $value   = $p{$limit};
            if ($value < $minimum) {
                warn qq{
WARNING: You are over-riding the minimum value for '$limit';
         this value is recorded here in *seconds*, not hours/days.

         Minimum...: $minimum
         Over-ride.: $value
};
            }
        }
    }
}

sub write {
    my $self = shift;
    $self = $self->instance()
        unless ref $self;

    my %p = validate( @_, { file => SCALAR_TYPE( optional => 1 ) } );

    my $file = $p{file} || $self->{file};

    die "Cannot call write() on an object without a file unless an output file is specified.\n"
        unless $file;

    open my $fh, '>', "$file.tmp.$$"
        or die "Cannot write to $file.tmp.$$: $!";

    my $time = scalar localtime();
    print $fh <<"EOF";
# This file was generated by Socialtext::AppConfig. Changes to the settings
# in this file will be preserved, but changes to comments will not be.

# Generated: $time

EOF

    for my $k ( Unicode::Collate->new->sort( keys %Options ) ) {
        my $desc = $Options{$k}{description};
        $desc =~ s/^/\# /mg;

        if ( $Options{$k}{optional} ) {
            $desc .= "\n# Optional\n";
        }
        elsif ( $Options{$k}{default} ) {
            $desc .= "\n# Defaults to $Options{$k}{default}\n";
        }

        print $fh $desc;
        print $fh "#\n";

        my $dumper = YAML::Dumper->new;
        $dumper->use_header(0);
        $dumper->use_block(1);

        if ( exists $self->{original_data}{$k} ) {
            print $fh $dumper->dump( { $k => $self->{original_data}{$k} } );
        }
        else {
            if ( $Options{$k}{optional} ) {
                # YAML will want to use either ~ for undef or '', but
                # either reads kind of funny as a default.
                print $fh "# $k:\n";
            }
            else {
                my $default = $Options{$k}{default};

                my $dumped = $dumper->dump( { $k => $default } );
                $dumped =~ s/^/# /gm;

                print $fh "$dumped\n";
            }
        }

        print $fh "\n";
    }

    close $fh;

    rename "$file.tmp.$$" => $file
        or die "Cannot rename $file.tmp.$$ to $file: $!";
}

# NOTE: AppConfig.pm is a dependency of ST/l10n.pm, so we cannot rely on
# l10n's loc() at compile time.  But we still must call loc() so that 
# the strings can be captured by gettext.pl
#
# So, l10n.pm will over-ride this method on load to be the correct method.
sub loc { shift }

1;

__END__

=head1 NAME

Socialtext::AppConfig - Application-wide configuration for NLW

=head1 SYNOPSIS

  use Socialtext::AppConfig;

  if ( Socialtext::AppConfig->is_default('user_factories') ) { ... }

  Socialtext::AppConfig->set( web_services_proxy => 'https://proxy.example.com/' );
  Socialtext::AppConfig->write();

=head1 DESCRIPTION

This module provides access to the application config file for NLW. If
this file does not exist, this module will try to provide reasonable
defaults for all config variables, at least when running in a
developer environment.

=head1 USAGE

For general usage, you can simply call all of the config variable
methods as class methods on the C<Socialtext::AppConfig> class. However, it
is also possible to explicitly create an C<Socialtext::AppConfig> object if
you want. The main reason this would be useful would be to explicitly
override the file to be used for configuration information.

=head2 Configuration File Locations

C<Socialtext::AppConfig> tries to find a config file in several
locations. If the current user is not root, and we are not running
under the Perl test harness, the module looks in
F<~/.nlw/etc/socialtext/socialtext.conf> first. After that, it tries
F</etc/socialtext/socialtext.conf>.

However, you can override this by setting the C<NLW_CONFIG>
environment variable. If this is set, then the module looks for the
file specified in that variable first.

Finally, you can call C<< Socialtext::AppConfig->new() >> and pass a "file"
parameter to the constructor to force it to use that file, whether or
not it exists. This is done primarily to make it possible to write a
config file to a new a file.

=head2 config_dir

We provide the directory where our configuration file can be found as
a means to allow other configuration files to be retrieved at the same
location.

=head2 $Auto_reload

By default, C<Socialtext::AppConfig> will automatically reload the
configuration file if it detects that the file has been modified.

By setting C<$Socialtext::AppConfig::Auto_reload=0> you can disable this, so
that the configuration file is only loaded once (the first time C<instance()>
or C<new()> is called).

=head1 CONFIGURATION VARIABLES

The following configuration variables can be set in the config
file. All variables either have a reasonable default or are optional.

Some of the defaults depend on whether the application was started as
root, or whether it is running under the Perl test harness. The
assumption is that if the app started as root (when C<Socialtext::AppConfig>
was I<loaded>), then it must be a production environment. This means
that to trigger this behavior under mod_perl, the module must be
loaded during server startup, before Apache forks and changes its user ID.

All of these variables are available by calling them as class methods
on C<Socialtext::AppConfig>, for example
C<< Socialtext::AppConfig->status_message_file >>.

=head2 status_message_file

The path to a file containing a status message to be shown on all the
pages.

Optional.

=for code type => FILE_TYPE

=head2 login_message_file

The path to a file containing a message to shown on the login screen.

Optional.

=for code type => FILE_TYPE

=head2 shortcuts_file

The file containing WAFL shortcut definitions. By default, this module
tries to find a file named F<shortcuts.yaml> in the same directory as
the config file.

Optional.

=for code type => FILE_TYPE

=head2 data_root_dir

The root directory for NLW data files.

If the startup user was root, defaults to F</var/www/socialtext>. If
the user was not root, it defaults to F<~/.nlw/root> or F<t/tmp/root>
under the Perl test harness.

=for code default => _default_data_root()

=for code type => DIR_TYPE

=head2 code_base

The directory under which various files needed by NLW are installed,
such as templates, javascript, images, etc.

If the startup user was root, this defaults to F</usr/share/nlw>,
otherwise it defaults the current directory at startup.

=for code default => _default_code_base()

=for code type => DIR_TYPE

=head2 template_compile_dir

The directory to use for caching compiled TT2 templates.

If the startup user was root, this defaults to
F</var/cache/socialtext/tt2>. Under the test harness it defaults to
F<t/tmp/cache/tt2>, otherwise F<~/.nlw/cache/tt2>.

Optional.

=for code default => _default_template_compile_dir()

=for code type => SCALAR_TYPE

=head2 formatter_cache_dir

The directory to use for caching the parse tree for a page.

If the startup user was root, this defaults to
F</var/cache/socialtext/formatter>. Under the test harness it defaults
to F<t/tmp/cache/formatter>, otherwise F<~/.nlw/cache/formatter>.

=for code default => _default_formatter_cache_dir()

=for code type => SCALAR_TYPE

=head2 change_event_queue_dir

The directory where change events are stored.

=for code default => _default_change_event_queue_dir()

=for code type => SCALAR_TYPE

=head2 pid_file_dir

The directory where daemons for NLW should put pid files.

If the startup user was root, this defaults to F</var/run/socialtext>.
Under the test harness it defaults to F<t/tmp/rnu>, otherwise
F<~/.nlw/run>.

=for code default => _default_pid_file_dir()

=for code type => DIR_TYPE

=head2 admin_script

The location of the Socialtext command line admin script.

If the startup user was root, the default is
F</usr/local/bin/st-admin>, and for non-root users it is
F<./bin/st-admin>.

=for code default => _default_admin_script()

=for code type => FILE_TYPE

=head2 script_name

The name of the script used in NLW application URIs.

Default: index.cgi

=for code type => SCALAR_TYPE

=head2 ssl_port

Specifies NLW uses a non-standard HTTPS port for SSL connections.  0 means no
custom SSL port.

Default: 0

=for code type => POSITIVE_INT_TYPE

=head2 ssl_only

NLW will only allow SSL access.

Default: 0

=for code type => BOOLEAN_TYPE

=head2 prefer_https

NLW will only generate HTTPS scheme URLs.

Default: 0

=for code type => BOOLEAN_TYPE

=head2 custom_http_port

Specifies NLW uses a non-standard HTTP port.  No redirection is provided for
requests sent to port 80.  0 means no custom port.

Default: 0

=for code type => POSITIVE_INT_TYPE

=head2 cookie_domain

The domain to be used for cookies set by NLW. If left, unset, this
defaults to the hostname for the virtual host serving NLW.

Optional.

=for code type => SCALAR_TYPE

=head2 web_services_proxy

The URI to a proxy to be used for web services (like Dashboard widgets, 
Google search, RSS feeds).

Optional.

=for code type => URI_TYPE

=head2 email_errors_to

An email address to which error messages will be sent. If not set, no
emails will be sent.

Optional.

=for code type => EMAIL_TYPE

=head2 support_address

The address to displayed in the app as the application support address.
The default is the value of --support-address supplied when configure
was run.

=for code default => get_build_setting('support-address')

=for code type => EMAIL_TYPE

=head2 web_hostname

The hostname used when generating fully-qualified URIs inside NLW.

Defaults to the system's hostname, as returned by
C<Socialtext::Hostname::fqdn()>.

Optional.

=for code default => Socialtext::Hostname::fqdn()

=for code type => SCALAR_TYPE

=head2 email_hostname

The hostname used when generating email addresses inside NLW.

Defaults to the system's hostname, as returned by
C<Socialtext::Hostname::fqdn()>.

Optional.

=for code default => Socialtext::Hostname::fqdn()

=for code type => SCALAR_TYPE

=head2 ceqlotron_synchronous

If this is true, this forces the Ceqlotron to dispatch tasks
synchronously one-at-a-time (without forking).

Default: 0

=for code type => BOOLEAN_TYPE

=head2 ceqlotron_max_concurrency

The maximum number of child processes the Ceqlotron will run in
parallel (pre-forked).

Default: 2

=for code type => NONNEGATIVE_INT_TYPE

=head2 ceqlotron_period

The time, in seconds, that a ceqlotron child process will wait after
processing a job.  Setting this lower will cause ceqlotron to process jobs
more frequently and may increase system load.  Setting this higher will cause
ceqlotron to process jobs less frequently and may decrease system load.

Default: 0

=for code type => POSITIVE_FLOAT_TYPE

=head2 ceqlotron_polling_period

The time, in seconds, that ceqlotron child processes will wait to check for
new jobs after they find that there's no more work to do (no work polling
interval).  Set this lower to have ceqlotron be more responsive to new jobs.

Default: 5

=for code type => POSITIVE_FLOAT_TYPE

=head2 ceqlotron_worker_loops

The number of jobs that a ceqlotron child process will work on before exiting.
This is used to combat memory leaks.

Default: 25

=for code type => NONNEGATIVE_INT_TYPE

=head2 did_you_know_title

The did you know title

=for code default => loc('config.did-you-know-title')

=for code type => SCALAR_TYPE

=head2 did_you_know_text

The did you know text

=for code default => loc('config.did-you-know-text')

=for code type => SCALAR_TYPE

=head2 MAC_secret

A secret used for seeding any digests generated by the app. This is
used for things like verifying user login cookies.

If the startup user was not root, then this variable is not required,
as it will be generated as needed. For production environments, this
must be set in the config file.

Optional.

=for code type => SCALAR_TYPE

=head2 challenger

The challenge system for this installation, defaults to the NLW login system

Default: STLogin

=for code type => SCALAR_TYPE

=head2 credentials_extractors

The colon-separated list of drivers to use for extracting credentials from a
request.

Default: BasicAuth:Cookie:Guest

=for code type => SCALAR_TYPE

=head2 logout_redirect_uri

The URI that users are redirected to after they log out.

Defaults to the login URI, but make no assumption about this pointing to a
page that you can login from.

Default: /challenge

=for code type => SCALAR_TYPE

=head2 default_user_ttl

The time, in seconds, between DB refreshes for users using the 'Default' driver.

Default: 86400

=for code type => SCALAR_TYPE

=head2 user_factories

The semicolon-separated list of drivers to use for user creation.

Default: Default

=for code type => SCALAR_TYPE

=head2 group_factories

The semicolon-separated list of drivers to use for Group creation

Default: Default

=for code type => SCALAR_TYPE

=head2 unauthorized_returns_forbidden

If this is true, then when a user is not authorized to perform an
action (like view a workspace), the server returns a forbidden (403)
error instead of sending them to the login screen.  Defaults to false.

Default: 0

=for code type => BOOLEAN_TYPE

=head2 custom_invite_screen

Use a different set of templates and actions for the invitation screen.

Optional.

=for code type => SCALAR_TYPE

=head2 db_name

The name of the database in the DBMS to which we connect.

If the startup user was root, this defaults to "NLW". Otherwise, this
defaults to "NLW_<username>_testing" under the test harness, and
"NLW_<username>" otherwise.

=for code default => _default_db_name()

=for code type => SCALAR_TYPE

=head2 schema_name

The name of the schema in the DBMS to which we connect.

=for code default => _default_schema_name()

=for code type => SCALAR_TYPE

=head2 db_user

The name of the to use when connecting to the DBMS.

If the startup user was root, this defaults to "nlw", otherwise it is
the current user's username.

=for code default => _default_db_user()

=for code type => SCALAR_TYPE

=head2 db_password

The password to use when connecting to the DBMS.

Optional.

=for code type => SCALAR_TYPE

=head2 db_host

The host to use when connecting to the DBMS. If not set, we do not
provide this when connecting, which for Postgres means we will connect
via a local Unix socket.

Optional.

=for code default => get_build_setting('db-host')

=for code type => SCALAR_TYPE

=head2 db_port

The post to use when connecting to the DBMS.

Optional.

=for code type => POSITIVE_INT_TYPE

=head2 enable_weblog_archive_sidebox

If this is true, the blog archive sidebox is shown when viewing a
blog. This will be removed as a configuration option once the box is
not so darn slow.

Default: 0

=for code type => BOOLEAN_TYPE

=head2 default_workspace

When a user logs into the system and the app does not know what
workspace they want, this is default workspace they are sent to.

Set this to a workspace name to have users redirected to it when 
their primary account does not have dashboard.

If the default_workspace does not exist, the app will behave as though
this is not set.

Optional.

=for code type => SCALAR_TYPE

=head2 locale

The two letter country code for the locale of your Socialtext install.  This
usually defaults to English, but that can be changed at install time.

=for code default => _default_locale()

=for code type => SCALAR_TYPE

=head2 stats

A comma- or dot-delimited list of runtime statistics to keep track
of. Setting this to "ALL" turns on all statistics. Collecting these
statistics slows the application down.

Optional.

=for code type => BOOLEAN_TYPE

=head2 syslog_level

The minimum log level used for passing messages to syslog.

Default: warning

=for code type => SCALAR_TYPE

=head2 benchmark_mode

Deprecated option - do not use.

Default: 0

=for code type => BOOLEAN_TYPE

=head2 minify_javascript

Set this to false disables the javascript minifier.

Default: 1

=for code type => SCALAR_TYPE

=head2 analytics_id

Server-wide Google Analytics

Optional.

=for code type => SCALAR_TYPE

=head2 analytics_domains

Server-wide Google Analytics - domains

Optional.

=for code type => BOOLEAN_TYPE

=head2 analytics_masked

Server-wide Google Analytics - mask urls

Default: 1

=for code type => SCALAR_TYPE

=head2 socialtext_analytics_id

Socialtext Google Analytics Code

Optional.

=for code type => BOOLEAN_TYPE

=head2 disable_mobile_redirect

Set this to true in order to disable the mobile UI

Default: 0

=for code type => BOOLEAN_TYPE

=head2 debug

Setting this to true turns on debugging output for NLW.

Default: 0

=for code type => BOOLEAN_TYPE

=head2 search_factory_class

Deprecated.

Default: Socialtext::Search::Solr::Factory

=for code type => SCALAR_TYPE

=head2 interwiki_search_set

Deprecated.

=for code default => '' 

=for code type => SCALAR_TYPE

=head2 search_warning_threshold

The maximum number of search results that will be returned for any query.

Default: 500

=for code type => SCALAR_TYPE

=head2 search_time_threshold

The maximum number of milliseconds to wait for a search to finish.  This is 
passed to Solr.

Default: 10000

=for code type => SCALAR_TYPE

=head2 reports_summary_email

Setting this causes the reports summary to be sent to the specified address.

Optional.

=for code type => SCALAR_TYPE

=head2 reports_skip_file

Set this to a file containing workspaces names that should not be included
in view/edit stats reporting.

Optional.

=for code type => SCALAR_TYPE

=head2 self_registration

Set this to true to enable users to self-register with accounts.

Default: 0

=for code type => BOOLEAN_TYPE

=head2 allow_network_invitation

Set this to true to enable users to send invite emails for other people to join their accounts.

Default: 0

=for code type => BOOLEAN_TYPE

=head2 users_can_create_groups

Set this to false to prevent users from creating groups.

Default: 1

=for code type => BOOLEAN_TYPE

=head2 solr_base

Set this to the base URL for your solr instance.

=for code default => _default_solr_base()

=for code type => SCALAR_TYPE

=head2 auth_token_soft_limit

The duration, in seconds, that authentication tokens are considered to be
valid and I<not> require the User to re-authenticate themselves.  Once this
"soft" limit has passed (and before the "hard" limit has been reached) the
authentication token will still be considered to be valid but the User I<will>
be prompted to re-authenticate if they perform an interruptable action.

Minimum allowable value is "1d".  Maximum is "365d".  Defaults to "13d".

=for code default => _default_auth_token_soft_limit

=for code type => POSITIVE_INT_TYPE

=head2 auth_token_hard_limit

The duration, in seconds, that authentication tokens are considered to be
valid.  Once this limit has been reached, the authentication token will be
considered invalid and the User will be required to re-authenticate.

Minimum allowable value is "1d".  Maximum is "365d".  Defaults to "14d".

=for code default => _default_auth_token_hard_limit

=for code type => POSITIVE_INT_TYPE

=head2 json_proxy_backend_limit

Set this to limit the number of HTTP connections made to the "back-end" (nlw-psgi).

Default: 16

=for code type => SCALAR_TYPE

=head2 signals_size_limit 

Set this to limit the maximum size of signals posted to this servers. Accounts may limit signals size to a smaller number.

Default: 1000

=for code type => POSITIVE_INT_TYPE

=head2 explore_is_public

Make Signals Explorer links visible to users.

Default: 1

=for code type => BOOLEAN_TYPE

=head2 advertise_push

Make /data/config claim that push support is available (assuming you've got the push plugin installed).

Default: 1

=for code type => BOOLEAN_TYPE

=head2 stringify_max_length

Set this to the maximum size of stringified content to send to the search engine.

Notes on Solr: Setting this too large will cause Solr OOM errors, so be very conservative.
Also, Solr by default only indexes the first 10,000 tokens in a string, so sending too much
content to Solr may simply waste memory/speed without having more content indexed.

Default: 262144

=for code type => POSITIVE_INT_TYPE

=head1 OTHER METHODS

In addition to the methods available for each configuration variable,
the following methods are available.

=head2 Socialtext::AppConfig->instance()

Returns an instance of the C<Socialtext::AppConfig> singleton. This does not
accept any parameters.

=head2 Socialtext::AppConfig->clear_instance()

Clears any existing singleton instance.

=head2 Socialtext::AppConfig->new()

This method explicitly creates a new object, as opposed to re-using a
singleton. Creating an object in this way does not change the
singleton value. The object's methods are the same as those which can
be called on the C<Socialtext::AppConfig> class, excluding constructors.

This method accepts the following parameters:

=over 4

=item * file

The location of the config file. This file does not have to exist, in
which case you can call C<write()> later to create it.

See L<Configuration File Locations> for details on how
C<Socialtext::AppConfig> will look for a file if none is specified.

=item * strict

When this is false, then an existing config file may continue invalid
configuration variables, and the constructor will not throw an
exception. This is useful when upgrading between NLW versions, and you
want to read a config file created with an earlier version of NLW.

By default, this is true, and invalid configuration variables cause an
exception.

=back

=head2 Socialtext::AppConfig->Options()

Returns a list of valid configuration variable names.

=head2 Socialtext::AppConfig->db_connect_params()

Returns a hash of parameters for connecting to the DBMS suitable for
use by your code. The hash returned will always have a "db_name"
key, the name of the schema to which we connect. It may also have any
of "user", "password", "host", and "port" if these are set in the
configuration object. If they are not set, the key is not present.

=head2 Socialtext::AppConfig->has_value($key)

Given a key, this method returns true if that key has a value, either
from the config file or a default. This can be used to check if an
optional variable has been set.

=head2 Socialtext::AppConfig->is_default($key)

Given a key, this method returns true if that key is set to the default
value.

=head2 Socialtext::AppConfig->is_appliance

Returns true if NLW is running on an appliance.

=head2 Socialtext::AppConfig->is_dev_env

Returns true if NLW is running in a dev-env.

Short-hand way of saying C<!Socialtext::AppConfig-E<gt>is_appliance>

=head2 Socialtext::AppConfig->set( key => $value, ... )

Given a list of keys and values, this method sets the relevant
configuration variables based on the values given. The keys must be
valid configuration variables.

=head2 Socialtext::AppConfig->write( [ file => $file ] )

By default, this method writes the configuration to the file from
which the configuration information was loaded. This can be overridden
by passing in a "file" parameter.  If the object was created without
reading from a file and non is specified, then this method will throw
an exception.

If you want to create a new file from scratch, you can create an
object explicitly and pass it a "file" parameter:

  my $config = Socialtext::AppConfig->new( file => $file );
  $config->set( ... );
  $config->write();

Writing a config file does not preserve comments in the file.

=head1 ENVIRONMENT

The C<NLW_APPCONFIG> environment variable can be set to a series of
comma-separated key=value pairs to override the config file. For
example:

  export NLW_APPCONFIG='db_user=one-eye,db_password=fnord'

This sets the value of db_user to "one-eye" and db_password to
"fnord".

There is currently no method to escape commas.  Add it if you need it.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005-2006 Socialtext, Inc., All Rights Reserved.

=cut
