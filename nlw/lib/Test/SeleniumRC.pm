# @COPYRIGHT@
package Test::SeleniumRC;
use strict;
use warnings;

=head1 Description

This module executes tests defined in wiki tables.

The REST API is used to fetch pages (or pages tagged as something) which are
parsed using Socialtext::WikiObject::TestPlan.  Socialtext::WikiFixture 
objects are created to perform the actual testing.

We create a single Test::WWW::Selenium instance that we pass to each of the
WikiFixtures to save time.

Tests are defined in the wiki specified below.

=cut

use base 'Test::Live';
use Class::Field qw(field);
use Test::Socialtext;
use Test::Socialtext::User;
use Test::More;

BEGIN {
    my @modules = qw(
        Test::WWW::Selenium
        Socialtext::Resting
        Socialtext::WikiObject::TestPlan
    );
    for my $mod (@modules) {
        eval "require $mod";
        if ($@) {
            plan skip_all => "Can't load $mod"; 
            exit;
        }
    }
}

# Config for selenium server running somewhere
field 'selenium';
field 'selenium_server'         => $ENV{selenium_host} || 'localhost';
field 'selenium_server_port'    => $ENV{selenium_port} || 4444;
field 'selenium_server_browser' => $ENV{selenium_browser} || '*firefox';
field 'selenium_timeout'        => $ENV{selenium_timeout} || 10000;

# The test plans and testcases are stored somewhere - fetch using REST API
field 'plan_server'    => $ENV{plan_server} || 'http://www2.socialtext.net';
field 'plan_workspace' => $ENV{plan_workspace} || 'regression-test';
field 'plan_username'  => $ENV{plan_username} || 'tester@ken.socialtext.net';
field 'plan_password'  => $ENV{plan_password} || 'wikitest';

# This is the workspace we're testing
field 'test_workspace' => $ENV{test_workspace} || 'test-data';
field 'test_username'  => $ENV{test_username}  || Test::Socialtext::User->test_username();
field 'test_password'  => $ENV{test_password}  || Test::Socialtext::User->test_password();

sub new {
    my $class = shift;
    my $self = bless {}, $class;

    # these may bail if we can't connect
    $self->load_selenium;
    $self->plan_rester; 

    $self->prepare_apache_and_possibly_stop;
    $self->setup_env;
    $self->maybe_start_apache;

    # Socialtext::WikiFixture::Socialtext expects 
    # st-admin to be in the PATH
    $ENV{PATH} = "bin:$ENV{PATH}";

    return $self;
}

sub test {
    my $self = shift;
    my %opts = @_;
    my $rester = $self->plan_rester;

    Test::Socialtext::plan('no_plan');

    warn "# Testing on " . $self->base_url . "\n";
    $self->setup_canonical_test_workspace;

    my @pages;
    if ($opts{page}) {
        push @pages, $opts{page};
    }
    elsif ($opts{tag}) {
        push @pages, $rester->get_taggedpages($opts{tag});
    }
    else {
        die "No page or tag defined";
    }

    for my $page (@pages) {
        diag "Executing page '$page'";
        my $test_plan = Socialtext::WikiObject::TestPlan->new(
            rester => $rester,
            page => $page,
            default_fixture => 'Socialtext',
            fixture_args => {
                selenium => $self->selenium,
                workspace => $self->test_workspace,
                username => $self->test_username,
                password => $self->test_password,
            },
        );
        $test_plan->run_tests;
    }
}

sub setup_canonical_test_workspace {
    my $self = shift;

    $self->test_workspace;

    my $attachment_id = 'test_data:20061228170418-0-4100';
    warn "fetching $attachment_id\n";
    my $tarball = $self->plan_rester->get_attachment($attachment_id);
    my $filename = "/tmp/test-data.$$.tar.gz";
    warn "Saving to $filename";
    open(my $fh, ">$filename") or die "Can't open $filename: $!";
    binmode $fh;
    print $fh $tarball;
    close $fh or die "Can't write $filename: $!";

    my $workspace = 'test-data';
    warn "# Deleting old $workspace workspace\n";
    system("st-admin delete-workspace --workspace $workspace --no-export");
    warn "# Importing $workspace workspace\n";
    system("st-admin import-workspace --tarball $filename --overwrite");
    warn "# Indexing $workspace workspace\n";
    system("st-admin index-workspace --workspace $workspace --sync");
    unlink $filename;
}

sub plan_rester {
    my $self = shift;
    eval {
        $self->{_plan_rester} ||= Socialtext::Resting->new(
            server => $self->plan_server,
            username => $self->plan_username,
            password => $self->plan_password,
            workspace => $self->plan_workspace,
        );
        $self->{_plan_rester}->get_pages; # make sure we can connect
    };
    if ($@) {
        my $server = $self->plan_server;
        plan skip_all => "Can't connect to wiki at $server";
        exit;
    }
    return $self->{_plan_rester};
}

# Make sure the Selenium server is running, get test instance
sub load_selenium {
    my $self = shift;

    eval {
        $self->selenium( Test::WWW::Selenium->new(
            host => $self->selenium_server,
            port => $self->selenium_server_port,
            browser => $self->selenium_server_browser,
            browser_url => $self->base_url,
        ));
    };
    if ($@) {
        my $server = $self->selenium_server . ':' . $self->selenium_server_port;
        plan skip_all => "Can't connect to selenium server ($server)";
        exit;
    }
}

1;

__END__

