#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Config;
use Data::Dumper;
use Sys::Hostname;
use File::Basename qw(basename);

print Dumper(
    {
        entry ('default-locale' => 'en', << 'DOC' ),
The country code for the localization you wish to use.  If your localization
isn't present, or isn't finished, then English is used for the unlocalized
parts.
DOC

        entry ('js-modules' => (-e '../js-modules' ? 1 : 0), << 'DOC' ),
We only make wikiwyg if we have the js-modules, check for that here.
DOC

        entry( destdir => "", <<'DOC' ),
Destdir is a directory to prepended onto all install paths.  Its purpose is to
relocate an install, which is useful for packaging.  Changing this variable
will not cause any hard coded values to be updated in any executable code.
For example if some file refers to /etc/socialtext then setting destdir will
have no affect on that value; this is on purpose since destdir only relocates
an install and does not update internal references to be consistent.
C.f. prefix
DOC

        entry( prefix => "", <<'DOC' ),
Prefix is a directory to prepend onto all install paths.  Changing prefix will
also updated any hard coded settings.  For example if some file refers to
/etc/socialtext then setting prefix will make it refer to
$prefix/etc/socialtext.  C.f. destdir
DOC

        entry( perl => $^X, <<'DOC' ),
The path to the version of perl you wish to use for installing.
DOC

        entry( 'st-user' => 'www-data', <<'DOC' ),
The user used by the Apache web server while runing Socialtext.
DOC

        entry( 'st-group' => 'www-data', <<'DOC' ),
The group used by the Apache web server while runing Socialtext.
DOC

        entry( bindir => '/usr/local/bin', <<'DOC' ),
The location to install executable files.   This is the same as passing
INSTALLSCRIPT to MakeMaker.
DOC

        entry( libdir => $Config{installsitelib}, <<'DOC' ),
The location to install Perl library files.  This is equivalent to passing in
INSTALLSCRIPTLIB= to MakeMaker.  The default value is the value of
$Config{installsitelib} from Config.pm
DOC

        entry( man1dir => $Config{installsiteman1dir}, <<'DOC' ),
The location to install Perl man1 man files.  This is equivalent to passing in
INSTALLSITEMAN1DIR= to MakeMaker.  The default value is the value of
$Config{installsiteman1dir} from Config.pm
DOC

        entry( man3dir => $Config{installsiteman3dir}, <<'DOC' ),
The location to install Perl man3 man files.  This is equivalent to passing in
INSTALLSITEMAN3DIR= to MakeMaker.  The default value is the value of
$Config{installsiteman3dir} from Config.pm
DOC

        entry( sharedir => '/usr/share/nlw', <<'DOC' ),
The location of the shared files used by Socialtext.  This includes things
like images, templates, and other shared but static files.
DOC

        entry( 'root-user' => 'root', <<'DOC' ),
The name of the root user.
DOC

        entry( 'root-group' => 'root', <<'DOC' ),
The name of the root group.
DOC

        entry( 'socialtext-open' => 0, <<'DOC' ),
Configures for the settings most appropriate for the Socialtext Open release.
DOC

        entry( 'dev' => 0, <<'DOC' ),
Configures for a development environment.  This may add additional
depencies to your build.
DOC

        entry( 'apache-status' => '', <<'DOC' ),
Configures Apache to include the /status and /perl-status URIs
for tracking and measuring Apache internals.  The value passed to
apache-status is the hosts to which these URLs will be restricted.
For example, --apache-status=.mydomain.com
DOC

        entry( hostname => get_hostname(), <<'DOC' ),
The fully-qualified hostname of the server on which we'll be running.
This is required for Socialtext Open, or single-Apache setups.
DOC

        entry( url => 'https://' . get_hostname() . get_port() . '/', <<'DOC' ),
The URL of where Socialtext will be reachable from.  This is currently only
used when generating the WSDL, which currently is not dynamically generated.
DOC

        entry( 'force-ssl-login' => 0, <<'DOC' ),
Force logins to use SSL. An attempt to login without SSL will be redirected to the https URL.
DOC

        entry( 'db-port' => '', <<'DOC' ),
The port that the database runs on.  If blank, assumes the default for the database.
DOC

        entry( 'db-host' => '', <<'DOC' ),
The host that the database runs on.  If blank, assumes the default for the database.
DOC

        entry( 'db-user' => 'postgres', <<'DOC' ),
The username of the DB superuser.  This is used only during the build process
when we connect to the DB and create our DB schemas.
DOC

        entry( 'install-prog' => which('/usr/bin/install'), <<'DOC' ),
The location of GNU install (or compatiable program).  Used during the install
to install files onto the system.
DOC

        entry( 'init-d' => '/etc/init.d', <<'DOC' ),
Location where system init.d files go.
DOC

        entry( webroot => '/var/www/socialtext', <<'DOC' ),
The web root used by Socialtext for storing all wiki data.  The root of the
webserver will be $webroot/docroot.
DOC

        entry( piddir => '/var/run/socialtext', <<'DOC' ),
The directory to which PID files are written.
DOC

        entry( spooldir => '/var/spool/socialtext', <<'DOC' ),
The directory where Socialtext change events can be spooled.
DOC

        entry( cachedir => '/var/cache/socialtext', <<'DOC' ),
The directory where Socialtext cache data is written.
DOC

        entry( confdir => '/etc/socialtext', <<'DOC' ),
The directory where Socialtext keeps all of its configuration files.
DOC

        entry( httpd => '/usr/sbin/apache-perl', <<'DOC' ),
The path to an Apache 1.3 web server which is capable of using both mod_perl
and mod_ssl.
DOC

        entry( httpd_confdir => '/etc/apache-perl', <<'DOC' ),
The location of the Apache configuration directory.
DOC
        entry( httpd_logdir => '/var/log/apache-perl', <<'DOC' ),
The location of the Apache log directory.
DOC

        entry( httpd_piddir => '/var/run', <<'DOC' ),
The location of the Apache pid directory.
DOC

        entry( httpd_lockdir => '/var/lock', <<'DOC' ),
The location of the Apache lock directory.
DOC

        entry( ssldir => '/etc/ssl', <<'DOC' ),
Directory that holds SSL certificates.
DOC

        entry( 'ceqlotron-logfile' => '/var/log/ceqlotron.log', << 'DOC' ),
Location of the file where ceqlotron should log any exceptional errors.
DOC

        entry( 'jsonproxy-logfile' => '/var/log/json-proxy.log', << 'DOC' ),
Location of the file where json-proxy should log any exceptional errors.
DOC

        entry( 'apache-perl-moduledir' => apache_perl_moduledir(), <<'DOC' ),
Directory that holds the modules for Apache 1 / mod_perl.
DOC

        entry( 'apache2-moduledir' => apache2_moduledir(), <<'DOC' ),
Directory that holds the modules for Apache 2.
DOC

        entry( 'support-address' => root_at_hostname(), <<'DOC' ),
Email address for users to get support for your wiki.  If not specified,
defaults to root@hostname.
DOC

        entry( 'server-admin' => root_at_hostname(), <<'DOC' ),
Email address for the administrator of your server.  If not specified,
defaults to root@hostname.
DOC

    }
);

sub entry {
    my ($name, $value, $doc) = @_;
    $doc = defined($doc) ? $doc : 'Undocumented';
    my $env_name = uc($name);
    $env_name =~ s/-/_/g;
    $value = defined($ENV{$env_name}) ? $ENV{$env_name} : $value;
    $value = defined($value) ? $value : "";
    return ($name => {value => $value, doc => $doc});
}

sub which {
    my $program = shift;
    my $basename = basename($program);
    chomp(my $name = `which $basename`);
    return $name || $program;
}

sub root_at_hostname {
    return 'root@' . get_hostname();
}

sub get_hostname {
    return Sys::Hostname::hostname() || 'localhost';
}

sub get_port {
    return $ENV{PORT} ? ":$ENV{PORT}" : '';
}

sub apache2_moduledir {
    my @tries = qw(
        /usr/lib/apache2/modules
        /opt/local/apache2/modules
    );

    return _find_dir( @tries ) || '';
}

sub apache_perl_moduledir {
    my @tries = qw(
        /opt/local/libexec/apache
        /usr/libexec/httpd
        /usr/lib/apache/1.3
        /usr/lib/apache-perl
    );

    return _find_dir( @tries ) || '';
}

sub _find_dir {
    for ( @_ ) {
        return $_ if -d && -r;
    }
    return;
}

__END__

=pod

=head1 NAME

defaults.pl - Data::Dumpers the build variables and their default values.

=head1 DESCRIPTION

This program is used to collect build variables and their default values.
It's printed in Data::Dumper format.  We don't use YAML, a more logical
choice, because it may not be installed at the point in the build when
this file is invoked.

All varible entries try to pull their default value from the environment.
Failing that they use their hard coded default.  The returned data structure
is a hash of hashes.  The keys of the outer hash are the names of the
variables.  The keys of the inner hash are "value" and "doc" and contain the
value and the documentation for that particular variable.

=cut
