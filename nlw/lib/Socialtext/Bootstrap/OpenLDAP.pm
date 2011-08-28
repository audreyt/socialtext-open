package Socialtext::Bootstrap::OpenLDAP;
# @COPYRIGHT@

use strict;
use warnings;
use Class::Field qw(field);
use IO::Socket;
use Net::LDAP;
use Net::LDAP::LDIF;
use POSIX qw(:sys_wait_h);
use File::Path qw(mkpath rmtree);
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use Time::HiRes qw(sleep);
use User::pwent;
use Socialtext::HTTP::Ports;
use Socialtext::AppConfig;
use Socialtext::LDAP;
use Socialtext::LDAP::Config;

# XXX: these should be treated as "read-only" fields after instantiation
field 'nodb';
field 'name';
field 'host';
field 'port';
field 'base_dn';
field 'root_dn';
field 'root_pw';
field 'requires_auth';
field 'raw_conf';
field 'statedir';
field 'datadir';
field 'logfile';
field 'slapd';
field 'schemadir';
field 'moduledir';
field 'conffile';
field 'debug_level';
field 'ldap_config', -init => '$self->_ldap_config';

my %ports = (
    ldap    => 389,
    ldaps   => 636,     # XXX: unused, but put in for completeness
    );

sub verbose {
    print STDERR "$_[0]\n" if ($ENV{TEST_VERBOSE});
}

sub new {
    my ($class, %config) = @_;

    # extract parameters
    my $port = $config{port} || $class->_autodetect_port();
    my $self = {
        # generic parameters; could be factored to common base class
        name            => "Bootstrapped, port $port",
        host            => $config{host}            || 'localhost',
        port            => $port,
        base_dn         => $config{base_dn}         || 'dc=example,dc=com',
        root_dn         => $config{root_dn}         || 'cn=Manager,dc=common-dc,dc=com',
        root_pw         => $config{root_pw}         || 'its-a-secret',
        requires_auth   => $config{requires_auth}   || 0,
        # openldap specific parameters
        debug_level     => $config{debug_level}     || 256,
        raw_conf        => $config{raw_conf}        || '',
        statedir        => $config{statedir}        || File::Spec->catdir(_ldap_root_dir(),'run'),
        datadir         => $config{datadir}         || File::Spec->catdir(_ldap_root_dir(),'ldap',$port),
        logfile         => $config{logfile}         || File::Spec->catfile(_ldap_root_dir(),'log',"ldap-$port.log"),
        slapd           => $config{slapd}           || _autodetect_slapd(),
        schemadir       => $config{schemadir}       || _autodetect_schema_dir(),
        moduledir       => $config{moduledir}       || _autodetect_module_dir(),
        # our custom parameters, to control how we set up the configuration
        nodb            => $config{nodb},
        };
    bless $self, $class;
    $self->conffile( File::Spec->catfile($self->datadir(), 'slapd.conf') );

    # start OpenLDAP
    $self->setup() or return;
    $self->start() or return;
    $self->add_to_ldap_config() or return;
    $self->add_to_user_factories() or return;
    $self->add_to_group_factories() or return;

    # return newly created object
    return $self;
}

my $ldap_root_dir;
sub _ldap_root_dir {
    unless ($ldap_root_dir) {
        # figure out what the right place is for us to be putting our files
        # that we need to bootstrap OpenLDAP.
        # - if running as a user it'll be either "nlw/t/tmp/" or "~/.nlw/"
        # - otherwise, its "/tmp/st-bootstrap-openldap-USERNAME-XXXXXX"
        #
        # NOTE: although Test::Socialtext::Environment provides a "root_dir()"
        # method, we *DON'T* want to use that; we're not necessariy running
        # unit tests.
        if (Socialtext::AppConfig->startup_user_is_human_user()) {
            $ldap_root_dir = Socialtext::AppConfig->_user_root();
        }
        else {
            my $username = getpwuid($>)->name();
            my $template = "st-bootstrap-openldap-$username-XXXXXX";
            $ldap_root_dir = tempdir( $template, TMPDIR=>1, CLEANUP=>1 );
        }
    }
    return $ldap_root_dir;
}

sub _autodetect_port {
    my $class = shift;
    my %args  = @_;

    # attempts to auto-detect an empty port that we can listen on.
    verbose( "# finding empty port to run OpenLDAP on" );
    my $attempts = 0;
    while ($attempts < 10) {
        my $port = $class->_base_port_number()
                 + ($attempts * 1000);

        # see if anyone is listening on this port
        my $socket = IO::Socket::INET->new(
            Proto       => 'tcp',
            LocalPort   => $port,
            Listen      => SOMAXCONN,
            Reuse       => 1,
            );
        if ($socket) {
            verbose( "# ... using port $port" );
            return $port;
        }

        # busy, try next port
        $attempts ++;
    }
    die "unable to find empty/available port for OpenLDAP";
}

sub _base_port_number {
    # use a distinct port number for each User, so that they can all have
    # their own copies of OpenLDAP bootstrapped.
    my $port = Socialtext::HTTP::Ports->PORTS_START_AT()
             + $ports{'ldap'}
             + $<;
    return $port;
}

my $slapd;
sub _autodetect_slapd {
    unless ($slapd) {
        # attempts to auto-detect the path to the "slapd" binary on the system
        #
        # throws a FATAL exception if we're unable to find it
        foreach my $path (qw(/usr/sbin /usr/local/sbin)) {
            my $bin = File::Spec->catfile( $path, 'slapd' );
            if (-e $bin and -x $bin) {
                verbose( "# auto-detected slapd: $bin" );
                $slapd = $bin;
                return $slapd;
            }
        }
        die "unable to find executable 'slapd' binary\n";
    }
    return $slapd;
}

my $schema_dir;
sub _autodetect_schema_dir {
    unless ($schema_dir) {
        # attempts to auto-detect the path to the "schema" directory for the
        # installed OpenLDAP
        #
        # throws a FATAL exception if we're unable to find it
        foreach my $path (qw(/etc/ldap/schema /usr/local/etc/ldap/schema)) {
            my $file = File::Spec->catfile( $path, 'openldap.schema' );
            if (-e $file) {
                verbose( "# auto-detected OpenLDAP schema dir: $path" );
                $schema_dir = $path;
                return $schema_dir;
            }
        }
        die "unable to find OpenLDAP schema directory\n";
    }
    return $schema_dir;
}

my $module_dir;
sub _autodetect_module_dir {
    unless ($module_dir) {
        # attempts to auto-detect the path to the directory that OpenLDAP
        # dynamic modules are located in
        #
        # throws a FATAL exception if we're unable to find it
        foreach my $path (qw(/usr/lib/ldap /usr/local/lib/ldap)) {
            my $file = File::Spec->catfile( $path, 'back_bdb.so' );
            if (-e $file) {
                verbose( "# auto-detected OpenLDAP module dir: $path" );
                $module_dir = $path;
                return $module_dir;
            }
        }
        die "unable to find OpenLDAP dynamic module directory\n";
    }
    return $module_dir;
}

sub DESTROY {
    my $self = shift;

    # remove ourselves from any LDAP connection cache, the quick/dirty way
    Socialtext::LDAP->ConnectionCache()->clear();

    # remove ourselves from the LDAP config
    #
    # wrapped in an eval in case it fails/dies (which could happen if the test
    # environment was purged since we were started)
    eval { $self->remove_from_user_factories() };
    eval { $self->remove_from_group_factories() };
    eval { $self->remove_from_ldap_config() };

    # shut down and cleanup after ourselves
    $self->stop();
    $self->teardown();
}

sub start {
    my $self = shift;
    return if $self->running();
    verbose( "# starting OpenLDAP" );

    # start OpenLDAP
    my @args = (
        '-f'    => $self->conffile(),
        '-d'    => $self->debug_level(),
        '-h'    => "ldap://$self->{host}:$self->{port}",
        );
    my $pid;
    unless ($pid = fork()) {
        die "fork: $!" unless defined $pid;

        # make sure that the log directory exists
        my $logdir = dirname($self->{logfile});
        unless (-e $logdir) {
            mkpath($logdir, 0, 0755) or die "cannot create log directory '$logdir'; $!";
        }

        # set up logging; we run slapd in debug mode and it doesn't detach
        open STDERR, ">$self->{logfile}";
        open STDOUT, '>&STDERR';
        close STDIN;

        # fire up slapd
        exec( $self->{slapd}, @args ) or die "cannot exec slapd @args\n\t$!";
    }

    # give OpenLDAP some time to start up or die off
    #
    # When running w/Devel::Cover, this takes a LOT longer than normal, so
    # rather than just sleeping an arbitrary amount of time we'll keep an eye
    # on it and wait for it to either (a) die off, or (b) respond to an
    # inbound connection.
    my $counter = 120;   # 40 x 0.25s = 20s
    while ($counter-- > 0) {
        # stop checking if we see the process die
        my $child = waitpid( -1, WNOHANG );
        last if ($child > 0);
        # stop checking if we can connect
        my $socket = IO::Socket::INET->new(
            Proto       => 'tcp',
            PeerHost    => $self->host(),
            PeerPort    => $self->port(),
            Timeout     => 0,
            );
        last if ($socket);
        sleep( 0.25 );
    }

    # make sure that OpenLDAP is running
    unless ($self->running($pid)) {
        warn "# unable to start OpenLDAP!";
        return;
    }
    $self->{pid} = $pid;
}

sub stop {
    my $self = shift;
    if ($self->running()) {
        # kill running OpenLDAP server, and give it some time to die off
        kill( 15, $self->{pid} );
        my $counter = 40;   # 40 x 0.25s = 10s
        while ($counter-- > 0) {
            my $child = waitpid( $self->{pid}, WNOHANG );
            last if ($child > 0);
            sleep( 0.25 );
        }
        # make sure that it died off
        if ($self->running()) {
            # didn't; KILL IT NOW!
            warn "# forcefully killing OpenLDAP server (pid=$self->{pid})";
            kill( 9, $self->{pid} );
        }
    }
    delete $self->{pid};
}

sub running {
    my ($self, $pid) = @_;
    $pid ||= $self->{pid};
    return ($pid and kill(0,$pid));
}

sub _ldap_config {
    my $self = shift;
    # create ST::LDAP::Config object based on our config
    my $config = Socialtext::LDAP::Config->new(
        id          => Socialtext::LDAP::Config->generate_driver_id(),
        name        => $self->name(),
        backend     => 'OpenLDAP',
        host        => $self->host(),
        port        => $self->port(),
        base        => $self->base_dn(),
        filter      => '(objectClass=inetOrgPerson)',
        attr_map    => {
            user_id         => 'dn',
            username        => 'cn',
            email_address   => 'mail',
            first_name      => 'givenName',
            middle_name     => 'initials',
            last_name       => 'sn',
            supervisor      => 'manager',
            work_phone      => 'telephoneNumber',
            preferred_name  => 'displayName',
            },
        group_filter => '(objectClass=groupOfNames)',
        group_attr_map => {
            group_id        => 'dn',
            group_name      => 'cn',
            member_dn       => 'member',
            },
        );
    $self->root_dn() && $config->bind_user( $self->root_dn() );
    $self->root_pw() && $config->bind_password( $self->root_pw() );
    # return ST::LDAP::Config
    return $config;
}

sub add_to_ldap_config {
    my $self = shift;
    verbose( "# adding LDAP instance to ldap.yaml" );

    # load the existing LDAP config, and strip our config out of it
    # (so we don't add ourselves again as a duplicate)
    my @ldap_config =
        grep { $_->id() ne $self->ldap_config->id }
        Socialtext::LDAP::Config->load();

    # save the LDAP configs
    my $rc = Socialtext::LDAP::Config->save(@ldap_config, $self->ldap_config());
    unless ($rc) {
        warn "# unable to save ldap.yaml; $!\n";
    }
    return $rc;
}

sub remove_from_ldap_config {
    my $self = shift;
    verbose( "# removing LDAP instance from ldap.yaml" );

    # load the existing LDAP config, and strip our config out of it
    my @ldap_config =
        grep { $_->id() ne $self->ldap_config->id }
        Socialtext::LDAP::Config->load();

    # save the remaining LDAP configs back out
    my $rc = Socialtext::LDAP::Config->save(@ldap_config);
    unless ($rc) {
        warn "# unable to save ldap.yaml; $!\n";
    }
    return $rc;
}

sub add_to_user_factories {
    my $self = shift;
    verbose( "# adding LDAP instance to user_factories" );

    # get the list of existing User Factories, stripping us out of it (so we
    # don't add ourselves again as a duplicate)
    my $me_as_factory = $self->as_factory();
    my @factories =
        grep { $_ ne $me_as_factory }
        split /;\s*/, Socialtext::AppConfig->user_factories();

    # prefix ourselves to the list of User Factories
    my $user_factories = join ';', $me_as_factory, @factories;
    Socialtext::AppConfig->set('user_factories' => $user_factories);
    Socialtext::AppConfig->write();

    my $got_set_ok = Socialtext::AppConfig->user_factories() eq $user_factories;
    unless ($got_set_ok) {
        warn "# unable to add LDAP instance to user_factories\n";
    }
    return $got_set_ok;
}

sub remove_from_user_factories {
    my $self = shift;
    verbose( "# removing LDAP instance from user_factories" );

    # get the list of existing User Factories, stripping us out of it
    my $me_as_factory = $self->as_factory();
    my @factories =
        grep { $_ ne $me_as_factory }
        split /;\s*/, Socialtext::AppConfig->user_factories();

    # save the remaining User Factories back out
    my $user_factories = join ';', @factories;
    Socialtext::AppConfig->set('user_factories' => $user_factories);
    Socialtext::AppConfig->write();

    my $got_set_ok = Socialtext::AppConfig->user_factories() eq $user_factories;
    unless ($got_set_ok) {
        warn "# unable to remove LDAP instance from user_factories\n";
    }
    return $got_set_ok;
}

sub add_to_group_factories {
    my $self = shift;
    verbose( "# adding LDAP instance to group_factories" );

    # get the list of Group Factories, stripping us out of it (so we don't add
    # ourselves again as a duplicate)
    my $me_as_factory = $self->as_factory();
    my @factories =
        grep { $_ ne $me_as_factory }
        split /;\s*/, Socialtext::AppConfig->group_factories();

    # prefix ourselves to the list of Group Factories
    my $group_factories = join ';', $me_as_factory, @factories;
    Socialtext::AppConfig->set('group_factories' => $group_factories);
    Socialtext::AppConfig->write();

    my $got_set_ok = Socialtext::AppConfig->group_factories() eq $group_factories;
    unless ($got_set_ok) {
        warn "# unable to add LDAP instance to group_factories\n";
    }
    return $got_set_ok;
}

sub remove_from_group_factories {
    my $self = shift;
    verbose( "# removing LDAP instance from group_factories" );

    # get the list of existing Group Factories, stripping us out of it
    my $me_as_factory = $self->as_factory();
    my @factories =
        grep { $_ ne $me_as_factory }
        split /;\s*/, Socialtext::AppConfig->group_factories();

    # save the remaining Group Factories back out
    my $group_factories = join ';', @factories;
    Socialtext::AppConfig->set('group_factories' => $group_factories);
    Socialtext::AppConfig->write();

    my $got_set_ok = Socialtext::AppConfig->group_factories() eq $group_factories;
    unless ($got_set_ok) {
        warn "# unable to remove LDAP instance from group_factories\n";
    }
    return $got_set_ok;
}

sub as_factory {
    my $self = shift;
    my $id   = $self->ldap_config->id();
    return "LDAP:$id";
}

sub setup {
    my $self = shift;

    # create data directory
    unless (-d $self->datadir()) {
        my $path = $self->datadir();
        verbose( "# creating OpenLDAP data directory: $path" );
        mkpath( $path, 0, 0755 ) or die "can't create '$path'; $!";
    }

    # create state directory
    unless (-d $self->statedir()) {
        my $path = $self->statedir();
        verbose( "# creating OpenLDAP state directory: $path" );
        mkpath( $path, 0, 0755 ) or die "can't create '$path'; $!";
    }

    # create common data directory
    my $common_datadir = "$self->{datadir}/common-dc";
    unless (-d $common_datadir) {
        mkpath($common_datadir, 0, 0755) or die "can't create '$common_datadir'; $!";
    }

    # rebuild config file
    my $conf = $self->conffile();
    unless (-f $conf) {
        verbose( "# writing slapd.conf" );
        my $requires_auth = $self->{requires_auth} ? 'disallow bind_anon' : '';

        open( my $fout, ">$conf" ) || die "can't write '$conf'; $!";
        print $fout <<END_SLAPD_CONF;
# include libraries
modulepath $self->{moduledir}
moduleload back_bdb
# include core OpenLDAP schemas
include $self->{schemadir}/core.schema
include $self->{schemadir}/cosine.schema
include $self->{schemadir}/inetorgperson.schema
include $self->{schemadir}/nis.schema
# logging
pidfile $self->{statedir}/slapd-$self->{port}.pid
argsfile $self->{statedir}/slapd-$self->{port}.args
# auth requirements
$requires_auth
# raw config additions
$self->{raw_conf}

# common database, for all slapd back-ends, w/common rootdn User
database bdb
suffix "dc=common-dc,dc=com"
rootdn "$self->{root_dn}"
rootpw "$self->{root_pw}"
directory "$common_datadir"
cachesize 50000
index default pres,eq
index objectClass,mail,cn
END_SLAPD_CONF

        unless ($self->{nodb}) {
            print $fout <<END_SLAPD_CONF;
# additional (optional) database, where all the Users/data is kept
database bdb
suffix "$self->{base_dn}"
rootdn "$self->{root_dn}"
directory "$self->{datadir}"
cachesize 50000
index default pres,eq
index objectClass,mail,cn
END_SLAPD_CONF
        }

        close $fout;
    }

    return 1;
}

sub teardown {
    my $self = shift;
    if ((-d $self->datadir()) and ($self->datadir() ne '/')) {
        verbose( "# removing OpenLDAP data directory" );
        rmtree( $self->datadir() );
    }
}

sub dump_ldif {
    my $self = shift;
    system("slapcat", "-f",$self->conffile);
}

sub add_ldif {
    my ($self, $ldif_filename) = @_;
    return $self->_ldif_update( \&_cb_add_entry, $ldif_filename );
}

sub remove_ldif {
    my ($self, $ldif_filename) = @_;
    return $self->_ldif_update( \&_cb_remove_entry, $ldif_filename );
}

sub _ldif_update {
    my ($self, $callback, $filename) = @_;

    # Open up the LDIF file
    my $ldif = Net::LDAP::LDIF->new( $filename, 'r', onerror => undef );
    unless ($ldif) {
        warn "# unable to read LDIF file: $filename\n";
        return;
    }

    # Grab all of the entries out of LDIF
    my @entries;
    while (not $ldif->eof()) {
        push @entries, $ldif->read_entry();
    }
    $ldif->done();

    # Feed the data to the LDAP server
    return $self->_update( $callback, \@entries );
}

sub add {
    my ($self, $dn, %attrs) = @_;

    my $entry = Net::LDAP::Entry->new();
    $entry->changetype('add');
    $entry->dn($dn);
    $entry->add(%attrs);

    return $self->_update( \&_cb_add_entry, [$entry] );
}

sub remove {
    my ($self, $dn) = @_;

    my $entry = Net::LDAP::Entry->new();
    $entry->changetype('delete');
    $entry->dn($dn);

    return $self->_update( \&_cb_remove_entry, [$entry] );
}

sub modify {
    my ($self, $dn, $action, $attr_ref) = @_;

    # NOTE: this doesn't follow the general model for passing through a
    #       Net::LDAP::Entry object like 'add()' and 'remove()' do, but there
    #       isn't a nice/quick/simple way to extract the hash of attrs again
    #       from a Net::LDAP::Entry object without iterating over the
    #       attributes individually and grabbing their values.
    #
    #       Was a whole lot simpler/easier to just pass through the attrs *as*
    #       the hash we've already got, rather than "wrap it up, then unwrap
    #       it again (the long way)".
    return $self->_update( \&_cb_modify_entry, [[$dn, $action, $attr_ref]] );
}

sub _update {
    my ($self, $callback, $values_aref) = @_;

    # Connect to the LDAP server
    my $ldap = Net::LDAP->new( $self->host(), port => $self->port() );
    unless ($ldap) {
        warn "# unable to connect to LDAP server\n";
        return;
    }

    # Bind to the LDAP connection
    my $mesg = $ldap->bind( $self->root_dn(), password => $self->root_pw() );
    if ($mesg->code()) {
        warn "# unable to bind to LDAP server\n";
        warn "#\t" . $mesg->code() . ': ' . $mesg->error() . "\n";
        return;
    }

    # Do the update, firing all the values through to the CB
    foreach my $val (@{$values_aref}) {
        return unless $callback->($ldap, $val);
    }
    return 1;
}

sub _cb_add_entry {
    my ($net_ldap, $entry) = @_;
    my $mesg = $net_ldap->add($entry);
    if ($mesg->code()) {
        warn "# error adding to LDAP:\n"
           . "#\t" . $mesg->code() . ': ' . $mesg->error() . "\n";
       $entry->dump(*STDERR);
       return;
    }
    return 1;
}

sub _cb_remove_entry {
    my ($net_ldap, $entry) = @_;
    my $mesg = $net_ldap->delete($entry->dn());
    if ($mesg->code()) {
        warn "# error removing from LDAP:\n"
           . "#\t" . $mesg->code() . ': ' . $mesg->error() . "\n";
        $entry->dump(*STDERR);
        return;
    }
    return 1;
}

sub _cb_modify_entry {
    my ($net_ldap, $entry) = @_;
    # NOTE: see note in 'modify()' above, for why this doesn't follow the same
    #       parameter convention as the 'add/remove' callbacks.
    my ($dn, $action, $attr_ref) = @{$entry};
    my $mesg = $net_ldap->modify( $dn, $action => $attr_ref );
    if ($mesg->code()) {
        warn "# error modifying record in LDAP:\n"
            . "#\t" . $mesg->code() . ': ' . $mesg->error() . "\n";
        $entry->dump(*STDERR);
        return;
    }
    return 1;
}

1;

=head1 NAME

Socialtext::Bootstrap::OpenLDAP - Bootstrap OpenLDAP instances

=head1 SYNOPSIS

  use Socialtext::Bootstrap::OpenLDAP;

  # bootstrap with default config
  $openldap = Socialtext::Bootstrap::OpenLDAP->new();

  # bootstrap with custom config
  $openldap = Socialtext::Bootstrap::OpenLDAP->new(%config);

  # stop/restart the OpenLDAP instance
  $openldap->stop();
  $openldap->start();

  # manipulate contents of LDAP directory, from LDIF file
  $openldap->add_ldif($ldif_filename);
  $openldap->remove_ldif($ldif_filename);

  # manipulate contents of LDAP directory, directly
  $openldap->add($dn, %ldap_attrs);
  $openldap->remove($dn);
  $openldap->modify($dn, add => { attr => 'val' });
  $openldap->modify($dn, replace => { attr => 'newval' });
  $openldap->modify($dn, delete => [qw(attr attr attr)]);
  $openldap->modify($dn, delete => { attr => 'val-to-remove' });

  # get LDAP config object
  $config = $openldap->ldap_config();

  # modify and re-save the LDAP configuration
  $openldap->ldap_config->bind_user( undef );
  $openldap->add_to_ldap_config();

  # query config of the OpenLDAP instance
  #
  # realistically, you should only ever need a minimum of these (if
  # any); if you're finding that you're calling these repeatedly,
  # we've missed something in creating this bootstrap harness.
  $host             = $openldap->host();
  $port             = $openldap->port();
  $base_dn          = $openldap->base_dn();
  $root_dn          = $openldap->root_dn();
  $root_pw          = $openldap->root_pw();
  $requires_auth    = $openldap->requires_auth();
  $raw_conf         = $openldap->raw_conf();
  $datadir          = $openldap->datadir();
  $logfile          = $openldap->logfile();
  $slapd            = $openldap->slapd();
  $schemadir        = $openldap->schemadir();
  $moduledir        = $openldap->moduledir();
  $conffile         = $openldap->conffile();

=head1 DESCRIPTION

C<Socialtext::Bootstrap::OpenLDAP> implements an interface that allows for you
to bootstrap (possibly multiple) OpenLDAP instances.

Designed primarily for use in testing, where although Unit Tests are nice,
nothing really beats testing against a real/live LDAP directory.  Doing that
requires our being able to fire up a copy of OpenLDAP, add some data to it,
and then run our tests against it.  Testing may even require that we
stop/restart the LDAP directory mid-test in order to simulate failed/down
connections.

Thus, C<Socialtext::Bootstrap::OpenLDAP>, a simple bootstrap harness around
OpenLDAP.

B<NOTE:> if your goal is to use this for unit testing, please refer to
L<Test::Socialtext::Bootstrap::OpenLDAP>, a wrapper for this module that
integrates nicely with C<Test::Builder>.

=head1 METHODS

=over

=item B<new(%config)>

Fires up a new OpenLDAP instance based on the provided C<%config>.

Defaults are available (or auto-detected) for B<all> of the configuration
options.  You should be able to conveniently fire up multiple OpenLDAP
instances just by going:

  $ldap_one   = Socialtext::Bootstrap::OpenLDAP->new();
  $ldap_two   = Socialtext::Bootstrap::OpenLDAP->new();
  $ldap_three = Socialtext::Bootstrap::OpenLDAP->new();
  ...

If you really feel the need to customize an OpenLDAP instance, though, the
following configuration options are supported:

=over

=item host

Specifies the hostname or IP address that we should be using.

=item port

Specifies the port number that we should be using.

=item base_dn

Specifies the Base DN for the LDAP directory.

=item root_dn

Specifies the DN of the root/admin user for the LDAP directory.

=item root_pw

Specifies the password for the root/admin user for the LDAP directory.

=item requires_auth

Specifies whether or not the OpenLDAP server I<requires> that the connection be
authenticated (if required, anonymous binds will fail).

=item raw_conf

Specifies I<raw> OpenLDAP configuration directives that you want to have
included in the OpenLDAP configuration file.

=item datadir

Specifies the data directory that is used for all of the files that OpenLDAP
requires or will place to disk.  This directory will be auto-created and
auto-removed for you.

=item logfile

Specifies the path to a logfile that OpenLDAP will use for writing its debug
output to.

=item slapd

Specifies the full path to the F<slapd> binary to use.

=item schemadir

Specifies the full path to the installed OpenLDAP schema directory.

=item moduledir

Specifies the full path to the OpenLDAP dynamic back-end modules.

=item nodb

Disables the default database used to hold your LDAP data.  This DB may need to
be disabled if you're trying to configure OpenLDAP to issue referral responses.

=back

=item B<start()>

Starts the OpenLDAP instance.  Is called automatically by C<new()>, so you only
need to call this if you've explicitly shut down the server and want to restart
it.

=item B<stop()>

Stops the OpenLDAP instance.

This is called automatically during object cleanup; when the bootstrap object
goes out of scope OpenLDAP will be shut down automatically.

=item B<running($pid)>

Checks to see if the OpenLDAP instance is running.  An optional C<$pid> may be
provided if you wish to check if some other process is running; by default we
use the PID of our OpenLDAP instance.

=item B<ldap_config()>

Returns the current LDAP configuration back to the caller as a
C<Socialtext::LDAP::Config> object.

Useful for bootstrapping OpenLDAP, then saving the configuration out to YAML
so that it can be used by the rest of your testing.

=item B<add_to_ldap_config()>

Adds configuration for B<this> LDAP instance to the LDAP configuration file.

This is called automatically by C<new()>, so you only need to call this if
you've gone in and changed the LDAP configuration or if you have explicitly
removed the LDAP configuration and want to add it back in.

Care is already taken to ensure that you don't get duplicate instances of the
LDAP configuration in the YAML file; don't worry about having to remove the
config before adding it again.

=item B<remove_from_ldap_config()>

Removes the configuration for B<this> LDAP instance from the LDAP
configuration file.

This is called automatically during object cleanup; when the bootstrap object
goes out of scope it'll de-register itself from the LDAP configuration.

=item B<add_to_user_factories()>

Adds B<this> LDAP instance to the list of known C<user_factories> in the
Socialtext configuration file, by prefixing it to the list of existing
C<user_factories>.

This is called automatically by C<new()>, so you only need to call this if you
have explicitly removed it from the C<user_factories> yourself.

=item B<remove_from_user_factories()>

Removes B<this> LDAP instance from the list of known C<user_factories> in the
Socialtext configuration file.

This is called automatically during object cleanup; when the bootstrap object
goes out of scope it'll de-register itself from the list of C<user_factories>.

=item B<add_to_group_factories()>

Adds B<this> LDAP instance to the list of known C<group_factories> in the
Socialtext configuration file, by prefixing it to the list of existing
C<group_factories>.

This is called automatically by C<new()>, so you only need to call this if you
have explicitly removed it from the C<group_factories> yourself.

=item B<remove_from_group_factories()>

Removes B<this> LDAP instance from the list of known C<group_factories> in the
Socialtext configuration file.

This is called automatically during object cleanup; when the bootstrap object
goes out of scope it'll de-register itself from the list of
C<group_factories>.

=item B<setup()>

Sets up the data directory and configuration file required by OpenLDAP.  Called
automatically by C<new()>; its B<not> necessary for you to ever call this
method.

=item B<teardown()>

Cleans up after ourselves, removing the data directory entirely when we're done.
Called automatically by C<DESTROY()>; its B<not> necessary for you to ever call
this method.

=item B<add_ldif($ldif_filename)>

Adds items to the OpenLDAP instance from the LDIF in the specified file.
Returns true if we're able to add all of the LDIF entries successfully, false
on error.

=item B<remove_ldif($ldif_filename)>

Removes items from the OpenLDAP instance based on their entries in the given
LDIF file.  Returns true if we're able to remove all of the LDIF entries
successfully, false on error.

=item B<add($dn, %attrs)>

Adds an entry to the OpenLDAP instance, using the given C<$dn> and LDAP
C<%attrs>.  Returns true if we're able to add the entry to LDAP successfully,
false on error.

=item B<remove($dn)>

Removes the LDAP entry pointed to by the given C<$dn> from the OpenLDAP
instance.  Returns true if we're able to remove the entry from LDAP
successfully, false on error.

=item B<modify($dn, $action, \%attr_ref)>

Modifies an existing entry in the OpenLDAP instance, as pointed to by the
given C<$dn>.

The following C<$action> syntaxes are supported:

=over

=item add => { attr => 'val' }

Adds a new LDAP attribute to the entry, using the provided value.

=item add => { attr => [val, val] }

Adds a new LDAP attribute to the entry, using the provided list of values.

=item replace => { attr => 'newval' }

Replaces an existing LDAP attribute on the entry, changing its value to the
provided value.

=item replace => { attr => [newval, newval] }

Replaces an existing LDAP attribute on the entry, changing its value to the
provided list of values.

=item delete => { attr => 'val' }

Removes the specified value from the LDAP attribute on the entry.

=item delete => { attr => [val, val] }

Removes all of the specified values from the LDAP attribute on the entry.

=item delete => [qw(attr attr)]

Removes one or more LDAP attributes from the entry.

=back

=item B<host()>

Returns the IP address that the OpenLDAP server is running on.

=item B<port()>

Returns the port number that the OpenLDAP server is running on.

=item B<base_dn()>

Returns the "Base DN" for the OpenLDAP instance, specifying the root node in
this LDAP directory.

=item B<root_dn()>

Returns the "Root DN" for the OpenLDAP instance; the username for the
root/admin user.

=item B<root_pw()>

Returns the "Root Password" for the OpenLDAP instance.

=item B<requires_auth()>

Returns a flag stating whether or not the OpenLDAP instance I<requires> that
all connections be authenticated.  If true, then anonymous binds will be
refused.

=item B<raw_conf()>

Returns any I<raw> OpenLDAP configuration that you asked to have included into
the configuration file.

=item B<statedir()>

Returns the path to the directory to which OpenLDAP should be placing its PID
file.

=item B<datadir()>

Returns the path to the data directory that is being used by this OpenLDAP
instance.

=item B<logfile()>

Returns the path to the logfile that is being written to by this OpenLDAP
instance.

=item B<slapd()>

Returns the full path to the F<slapd> executable that is used.

=item B<schemadir()>

Returns the path to the directory that contains the installed OpenLDAP schema
files.

=item B<moduledir()>

Returns the path to the directory that contains the installed OpenLDAP dynamic
modules.

=item B<conffile()>

Returns the full path to the F<slapd.conf> file used by our OpenLDAP instance.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Test::Socialtext::Bootstrap::OpenLDAP>.

=cut
