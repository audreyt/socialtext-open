# @COPYRIGHT@
package Test::Socialtext::Environment;
use strict;
use warnings;

use base 'Socialtext::Base';

use Cwd;
use Carp;
use Class::Field qw( field );
use File::chdir;
use File::Path;
use Socialtext::AppConfig;
use Socialtext::Workspace;
use Socialtext::HTTP::Ports;
use Test::More;
use Test::Socialtext::Fixture;
use Test::Socialtext::User;

field 'root_dir';
field 'base_dir';
field 'verbose' => 1;
field 'wiki_url_base';
field 'fixtures' => [];
field 'fixture_objects' => [];
field 'nlw_dir';

my $Self;

# NLW directory for the current branch, under which tests are run.
my $nlw_dir;
foreach my $maybe (
        $ENV{ST_CURRENT} ? "$ENV{ST_CURRENT}/nlw" : (),
        $ENV{ST_SRC_BASE} ? "$ENV{ST_SRC_BASE}/current/nlw" : (),
        $CWD,
        '/tmp',
        ) {
    if (-d $maybe and -w $maybe) {
        $nlw_dir = Cwd::abs_path($maybe);
        last;
    }
}
unless (-d $nlw_dir) {
    die "unable to detect nlw_dir!";
}

# A place to keep mains so they aren't garbage collected.
my @RememberedMains;

sub instance {
    my $class = shift;

    return $Self ||= $class->new(@_);
}

sub CreateEnvironment {
    shift->instance( @_ );
}

sub new {
    my $class = shift;

    my $test_dir = File::Spec->catdir(
        $nlw_dir,
        Socialtext::AppConfig->test_dir(),
    );

    my $self = $class->SUPER::new(
        nlw_dir  => $nlw_dir,
        root_dir => $test_dir,
        base_dir => "$test_dir/root",

        # set by Module::Build for Test::Harness ...
        verbose => $ENV{TEST_VERBOSE},
        @_,
    );

    $self->_create_log_dir;
    $self->_clean_if_last_test_was_destructive;
    $self->_init_fixtures;
    $self->_set_url;
    $self->_make_fixtures_current;

    return $self;
}

sub _create_log_dir {
    my $self = shift;
    my $log_dir = File::Spec->catdir(
        $self->root_dir(), 'log',
    );
    mkpath $log_dir unless -d $log_dir;
}

sub _clean_if_last_test_was_destructive {
    my $self = shift;
    my $fixture = Test::Socialtext::Fixture->new( name => 'destructive', env => $self );
    if ($fixture->is_current) {
        Test::More::diag( "last test was destructive; cleaning everything out and starting fresh" );
        unshift @{$self->{fixtures}}, 'clean';
    }
}

sub _init_fixtures {
    my $self = shift;
    foreach my $name (@{$self->fixtures}) {
        Test::More::diag("Using fixture '$name'.") if $self->verbose;
        my $fixture = Test::Socialtext::Fixture->new( name => $name, env => $self );
        push @{$self->fixture_objects}, $fixture;

        if ($fixture->has_conflicts) {
            Test::More::diag("... fixture conflict detected; cleaning first") if $self->verbose;
            unshift @{$self->fixture_objects},
              Test::Socialtext::Fixture->new( name => 'clean', env => $self );
        }
    }
}

sub _set_url {
    my $self = shift;
    my $hostname = `hostname`;
    chomp($hostname);
    my $main_port = Socialtext::HTTP::Ports->http_port();
    $self->wiki_url_base( "http://$hostname:" . $main_port );
}

sub _make_fixtures_current {
    my $self = shift;
    foreach my $fixture (@{$self->fixture_objects}) {
        $fixture->generate;
    }
}

sub hub_for_workspace {
    my $self = shift;
    my $name = shift || die "no name provided to hub_for_workspace";
    my $username = shift || Test::Socialtext::User->test_username();
    my $ws = ref $name ? $name : Socialtext::Workspace->new( name => $name )
        or croak "No such workspace: $name";
    my $user = Socialtext::User->new(username => $username)
        or croak "No such user: $username";

    my $main = Socialtext->new()->debug();
    my $hub  = $main->load_hub(
        current_workspace => $ws,
        current_user      => $user,
    );

    $hub->registry->load;

    push @RememberedMains, $main;

    return $hub;
}


1;

