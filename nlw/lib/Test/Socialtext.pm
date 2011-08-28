# @COPYRIGHT@
package Test::Socialtext;
use strict;
use warnings;

use lib 'lib';

use Cwd ();
use Test::Base 0.52 -Base;
use Socialtext::Base;
use Test::Builder;
use Test::Socialtext::Environment;
use Test::Socialtext::User;
use Test::Socialtext::Account;
use Test::Socialtext::Group;
use Test::Socialtext::Workspace;
use Socialtext::Account;
use Socialtext::Group;
use Socialtext::User;
use Socialtext::Cache;
use Socialtext::AppConfig;
use Socialtext::SQL qw/:exec sql_txn get_dbh/;
use Socialtext::Timer;
use Socialtext::UserSet qw/:const/;
use YAML;
use File::Temp qw/tempdir/;
use File::Spec;
use Socialtext::System qw/shell_run/;
use IO::File;
use IO::Select;

BEGIN {
    require Socialtext::Pluggable::Adapter;
    use Memoize qw/unmemoize/;
    unmemoize( \&Socialtext::Pluggable::Adapter::plugins );

    use Socialtext::HTTP::Ports;
    unmemoize \&Socialtext::HTTP::Ports::http_port;
    unmemoize \&Socialtext::HTTP::Ports::https_port;
    unmemoize \&Socialtext::HTTP::Ports::backend_http_port;
    unmemoize \&Socialtext::HTTP::Ports::backend_https_port;
    unmemoize \&Socialtext::HTTP::Ports::json_proxy_port;
}

# Set this to 1 to get rid of that stupid "but matched them out of order"
# warning.
our $Order_doesnt_matter = 0;

our @EXPORT = qw(
    fixtures
    new_hub
    create_test_hub
    create_test_account
    create_test_account_bypassing_factory
    create_test_user
    create_test_badmin
    create_test_workspace
    create_test_group
    clear_ldap_users
    SSS
    run_smarter_like
    smarter_like
    smarter_unlike
    ceqlotron_run_synchronously
    setup_test_appconfig_dir
    formatted_like
    formatted_unlike
    modules_loaded_by
    dump_roles
    timer_clear
    timer_report
    set_as_default_account
    looks_like_pdf_ok
    wait_for_log_lines
);

our @EXPORT_OK = qw(
    content_pane 
    main_hub
    run_manifest
    check_manifest
);

{
    my $builder = Test::Builder->new();
    my $fh = $builder->output();
    # Get around syntax checking warnings
    if (defined $fh) {
        binmode $fh, ':utf8';
        $builder->output($fh);
    }
}

our $DB_AVAILABLE = 0;
sub fixtures () {
    $ENV{SKIP_PUSHD_TICKLE} = 1 unless defined $ENV{SKIP_PUSHD_TICKLE};

    # point directly to where the config file is going to go; if we have to
    # create it, we need to tell ST::AppConfig where its *supposed* to go.
    my $testdir = Socialtext::AppConfig->test_dir();
    my $cfgfile = File::Spec->catfile(
        Cwd::cwd, $testdir, 'etc/socialtext/socialtext.conf'
    );
    $ENV{NLW_CONFIG} = $cfgfile;

    # set up the test environment, and all of its fixtures.
    my $env
        = Test::Socialtext::Environment->CreateEnvironment(fixtures => [@_]);

    # purge any in-memory caches, so we reload them with any data that may
    # have been created as part of setting up the fixtures.
    Socialtext::Cache->clear();
    Socialtext::Account->Clear_Default_Account_Cache();

    # check to see if the "DB" fixture is current (if so, we will want to
    # store and reset some state that's inside the DB)
    $DB_AVAILABLE = Test::Socialtext::Fixture->new(name => 'db', env => $env)
        ->is_current();

    # store the state of the universe "after fixtures have been created", so
    # that we can reset back to this state (as best we can) at the end of the
    # test run.
    _store_initial_state();
}

sub run_smarter_like() {
    (my ($self), @_) = find_my_self(@_);
    my $string_section = shift;
    my $regexp_section = shift;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    for my $block ($self->blocks) {
        local $SIG{__DIE__};
        smarter_like(
            $block->$string_section,
            $block->$regexp_section,
            $block->name
        );
    }
}

sub smarter_like() {
    my $str = shift;
    my $re = shift;
    my $name = shift;
    my $order_doesnt_matter = shift || 0;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my @res = split /\n/, $re;
    for my $i (0 .. $#res) {
        my $x = qr/$res[$i]/;
        unless ($str =~ $x) {
            test_more_fail(
                "The string: '$str'\n"
                . "...doesn't match $x (line $i of regexp)",
                $name
            );
            return;
        }
    }
    my $mashed = join '.*', @res;
    $mashed = qr/$mashed/sm;
    die "This looks like a crazy regexp:\n\t$mashed is a crazy regexp"
        if $mashed =~ /\.[?*]\.[?*]/;
    if (!$order_doesnt_matter) {
        unless ($str =~ $mashed) {
            test_more_fail(
                "The string: '$str'\n"
                . "...matched all the parts of $mashed\n"
                . "...but didn't match them in order.",
                $name
            );
            return;
        }
    }
    ok 1, "$name - success";
}

sub smarter_unlike() {
    my $str = shift;
    my $re = shift;
    my $name = shift;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my @res = split /\n/, $re;
    for my $i (0 .. $#res) {
        my $x = qr/$res[$i]/;
        if ($str =~ $x) {
            test_more_fail(
                "The string: '$str'\n"
                . "...matched $x (line $i of regexp)",
                $name
            );
            return;
        }
    }
    pass( "$name - success" );
}

sub formatted_like() {
    my $wikitext = shift;
    my $re       = shift;
    my $name     = shift;
    unless ($name) {
        $name = $wikitext;
        $name =~ s/\n/\\n/g;
    }
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $formatted = main_hub()->viewer->text_to_html("$wikitext\n");
    like $formatted, $re, $name;
}

sub formatted_unlike() {
    my $wikitext = shift;
    my $re       = shift;
    my $name     = shift;
    unless ($name) {
        $name = $wikitext;
        $name =~ s/\n/\\n/g;
    }
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $formatted = main_hub()->viewer->text_to_html("$wikitext\n");
    unlike $formatted, $re, $name;
}

{
    my %module_loaded_cache;

    # get a hash-ref of modules loaded by some module
    sub modules_loaded_by {
        my $module = shift;
        unless ($module_loaded_cache{$module}) {
            my $script = 'print map { "$_\n" } keys %INC';
            my @files  = `$^X -Ilib -M$module -e '$script'`;
            if ($?) {
                croak "failed to list modules loaded by '$module'; compile error?";
            }
            chomp @files;
            map { $module_loaded_cache{$module}{$_}++ }
                map { s{\.pm$}{}; $_ }
                map { s{/}{::}g;  $_ }
                @files;
        }
        return $module_loaded_cache{$module};
    }
}

sub wait_for_log_lines() {
    my ($filename, $timeout, $expect) = @_;

    my $io = IO::File->new;
    $io->open($filename,"r") or die $!;

    # Use IO::Select to block on reads
    my $s = IO::Select->new;
    $s->add($io);

    my $start = time;
    while (1) {
        $s->can_read($timeout);
        while (defined(my $data = $io->getline())) {
            chop $data;
            for my $re(@$expect) {
                if ($data =~ $re) {
                    $expect = [ grep { $_ ne $re } @$expect ];
                    pass "Log line like $re";
                }
            }
        } 
        last if !@$expect or (time - $start) >= $timeout;
    }
    fail "Log line like $_" for @$expect;
}

sub ceqlotron_run_synchronously() {
    my $funcname = shift;
    my $workspace_name_or_id = shift || '';
    my $quiet = shift || 0;
    my $workspace;

    if ($workspace_name_or_id and $workspace_name_or_id =~ /^\d+$/) {
        $workspace = Socialtext::Workspace->new(
            workspace_id => $workspace_name_or_id
        );
    }
    elsif ($workspace_name_or_id) {
        $workspace = Socialtext::Workspace->new(
            name => $workspace_name_or_id
        );
    }

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # Run all the jobs in TheCeq queue, *IN-PROCESS*
    require Socialtext::Jobs;
    Socialtext::Jobs->can_do_all();

    if ($quiet) {
        my $message = '';
        if ($workspace_name_or_id) {
            if ($funcname) {
                $message = "Waiting for $funcname jobs in $workspace_name_or_id worskapce to clear\n";
            }
            else {
                $message = "Waiting for jobs in $workspace_name_or_id workspace to clear\n";
            }
        }
        else {
            if ($funcname) {
                $message = "Waiting for $funcname jobs to clear\n";
            }
            else {
                $message = "Waiting for all jobs to clear\n";
            }
        }
        diag $message;
    }
    my @jobid;
    local $ENV{ST_JOBS_VERBOSE} = 1;
    while (my $job = Socialtext::Jobs->find_job_for_workers()) {
        diag "Running ceq job " . Socialtext::Jobs->job_to_string($job) . "\n" unless $quiet;
        if ($funcname and ($job->funcname || '') !~ /$funcname$/i) {
            next;
        }
        if ($workspace && $job->arg->{workspace_id}) {
            my $ws_id = $job->arg->{workspace_id} or next;
            ($ws_id == $workspace->workspace_id) or next;
        }

        push @jobid, $job->jobid;

        Socialtext::Jobs->work_once($job);
        Socialtext::Cache->clear();
        Socialtext::SQL::invalidate_dbh();
    }

    if (!@jobid) {
        Test::More::pass("no jobs left for ceqlotron to run");
        return;
    }

    # Make sure all jobs above completed successfully.
    require Socialtext::SQL;
    my $jobs_left;
    # Wait for 60 seconds for the previously-grabbed jobs by ceq to complete.
    # However, we only count the jobs ran by the in-process loop above.
    for (1..60) {
        $jobs_left = Socialtext::SQL::sql_singlevalue(qq{
            SELECT COUNT(*) FROM job WHERE run_after < EXTRACT(epoch from now())
                AND jobid IN (@{[join ',', @jobid]}) 
        }) || 0;
        last if $jobs_left == 0;
        sleep 1;
    }
    Test::More::is($jobs_left, 0, "ceqlotron finished all runnable jobs");
    if ($jobs_left) {
        system("ceq-read");
    }
}

# Create a temp directory and setup an AppConfig using that directory.
sub setup_test_appconfig_dir {
    my %opts = @_;

    # We want our own dir because when we try to create files later,
    # we need to make sure we're not trying to overwrite a file
    # someone else created.
    my $dir = $opts{dir} || tempdir( CLEANUP => 1 );

    # Cannot use Socialtext::File::catfile here because it depends on
    # Socialtext::AppConfig, and we don't want it reading the wrong config
    # file.
    my $config_file = File::Spec->catfile( $dir, 'socialtext.conf' );

    open(my $config_fh, ">$config_file")
        or die "Cannot open to $config_file: $!";

    select my $old = $config_fh; 
    $| = 1;  # turn on autoflush
    select $old;
    print $config_fh YAML::Dump($opts{config_data});
    close $config_fh or die "Can't write to $config_file: $!";
    return $config_file if $opts{write_config_only};

    Socialtext::AppConfig->new(
        file => $config_file,
        _singleton => 1,
    );
    return $config_file;
}

# Show a timer report when the test is finished
END { timer_report() }

sub timer_clear {
    Socialtext::Timer->Reset();
}

sub timer_report {
    return unless ($ENV{TEST_VERBOSE} and not $ENV{TEST_LESS_VERBOSE});

    diag "Socialtext::Timer report\n";
    my $report = Socialtext::Timer->ExtendedReport();
    if (%{$report}) {
        foreach my $key (sort { $report->{$b}->{duration} <=> $report->{$a}->{duration} } keys %{$report}) {
            my $dur = $report->{$key}->{duration};
            my $cnt = $report->{$key}->{count};
            my $avg = $report->{$key}->{average};
            my $str = sprintf( '%30s => %0.3f  (%5d times, avg %0.3f)', $key, $dur, $cnt, $avg );
            diag $str;
        }
    }
    else {
        diag "\treport empty; no timers called";
    }
}

# store initial state, so we can revert back to this (as best we can) at the
# end of each test run.
sub _store_initial_state {
    _store_initial_appconfig();
    if ($DB_AVAILABLE) {
        _store_initial_sysconfig();
        _store_initial_objects();
    }
}

# revert back to the initial state (as best we can) when the test run is over.
END { _teardown_cleanup() }
sub _teardown_cleanup {
    $ENV{SKIP_PUSHD_TICKLE} = 1 unless defined $ENV{SKIP_PUSHD_TICKLE};
    _reset_initial_appconfig();
    if ($DB_AVAILABLE) {
        _reset_initial_sysconfig();
        _remove_all_but_initial_objects();
    }
}

{
    my %InitialAppConfig;
    sub _store_initial_appconfig {
        my $appconfig = Socialtext::AppConfig->new();
        foreach my $opt ($appconfig->Options) {
            $InitialAppConfig{$opt} = $appconfig->$opt();
        }
    }
    sub _reset_initial_appconfig {
        my $appconfig = Socialtext::AppConfig->new();
        foreach my $opt (keys %InitialAppConfig) {
            no warnings;
            if ($appconfig->$opt() ne $InitialAppConfig{$opt}) {
                if (Test::Socialtext::Environment->instance()->verbose) {
                    Test::More::diag("CLEANUP: resetting '$opt' AppConfig "
                                    ."value; your test changed it");
                }
                $appconfig->set( $opt, $InitialAppConfig{$opt} );
                $appconfig->write();
            }
        }
    }
}

{
    my $InitialSysConfig = [];
    sub _store_initial_sysconfig {
        my $dbh = get_dbh;
        $InitialSysConfig = $dbh->selectall_arrayref(
            q{SELECT * FROM "System"});
    }
    sub _reset_initial_sysconfig {
        Test::More::diag("CLEANUP: resetting System table");
        sql_txn {
            sql_execute(q{DELETE FROM "System"});
            foreach my $setting (@$InitialSysConfig) {
                my $ph = join(',', ('?') x @$setting);
                sql_execute(
                    q{INSERT INTO "System" VALUES (}.$ph.')', @$setting);
            }
        };
        eval { Socialtext::Account->Clear_Default_Account_Cache() };
        undef $InitialSysConfig;
    }
}

{
    my %Initial;
    my %Objects = (
        user => {
            get_iterator => sub {
                my $sth = sql_execute("SELECT user_id FROM all_users");
                return Socialtext::MultiCursor->new(
                    iterables => $sth->fetchall_arrayref(),
                    apply => sub { $_[0] },
                );
            },
            get_id       => sub { $_[0] },
            identifier   => sub {
                return $_[0];
            },
            delete_item => sub {
                Test::Socialtext::User->delete_recklessly($_[0]);
            }
        },
        workspace => {
            get_iterator => sub { Socialtext::Workspace->All() },
            get_id       => sub { $_[0]->workspace_id },
            identifier   => sub {
                my $w = shift;
                return $w->workspace_id . ' (' . $w->name . ')';
            },
            delete_item => sub {
                Test::Socialtext::Workspace->delete_recklessly($_[0]);
            },
        },
        account => {
            get_iterator => sub { Socialtext::Account->All() },
            get_id => sub { $_[0]->account_id },
            identifier => sub {
                my $a = shift;
                return $a->account_id . ' (' . $a->name . ')';
            },
            delete_item => sub {
                Test::Socialtext::Account->delete_recklessly($_[0]);
            },
        },
        role => {
            get_iterator => sub { Socialtext::Role->All() },
            get_id       => sub { $_[0]->role_id },
            identifier   => sub {
                my $r = shift;
                return $r->role_id . ' (' . $r->name . ')';
            },
            delete_item => sub { $_[0]->delete },
        },
        group => {
            get_iterator => sub { Test::Socialtext::Group->All() },
            get_id       => sub { $_[0]->group_id },
            identifier   => sub {
                my $g = shift;
                return $g->group_id . ' (' . $g->driver_group_name . ')';
            },
            delete_item  => sub {
                Test::Socialtext::Group->delete_recklessly($_[0]);
            },
        }
    );

    sub _store_initial_objects {
        while (my ($key,$obj) = each %Objects) {
            my $iterator = $obj->{get_iterator}->();
            while (my $item = $iterator->next()) {
                my $id = $obj->{get_id}->($item);
                $Initial{$key}{$id} ++;
            }
        }
    }

    sub _remove_all_but_initial_objects {
        while (my ($key,$obj) = each %Objects) {
            _generic_delete($key => $obj);
        }

        if (Test::Socialtext::Environment->instance()->verbose) {
            Test::More::diag("CLEANUP: removing all ceq jobs");
        }

        # destroy theschwartz jobs, OK to leave funcmap alone
        sql_txn {
            sql_execute("TRUNCATE note, error, exitstatus, job");
        };
    }

    sub _generic_delete {
        my $key = shift;
        my $obj = shift;
        my $iterator = $obj->{get_iterator}->();
        if (Test::Socialtext::Environment->instance()->verbose) {
            Test::More::diag("CLEANUP: removing ${key}s");
        }
        while (my $item = $iterator->next()) {
            # remove all but the initial set of objects that were
            # created and available at startup.
            my $id = $obj->{get_id}->($item);
            next if $Initial{$key}{$id};

            # Delete it
            if (Test::Socialtext::Environment->instance()->verbose) {
                my $identifier = $obj->{identifier}->($item);
            }
            $obj->{delete_item}->($item);
        }
    }

    sub clear_ldap_users {
        for my $user (Socialtext::User->All->all) {
            next if $user->is_system_created;
            next unless $user->homunculus->driver_name eq 'LDAP';
            Test::Socialtext::User->delete_recklessly($user);
        }
    }
}

sub test_more_fail() {
    my $str = shift;
    my $test_name = shift || '';
    warn $str; # This doesn't get shown unless in verbose mode.
    Test::More::fail($test_name); # to get the counts right.
}

sub run_manifest() {
    (my ($self), @_) = find_my_self(@_);
    for my $block ($self->blocks) {
        $self->check_manifest($block) 
          if exists $block->{manifest};
    }
}

sub check_manifest {
    my $block = shift;
    my @manifest = $block->manifest;
    my @unfound = grep not(-e), @manifest;
    my $message = 'expected files exist';
    if (@unfound) {
        warn "$_ does not exist\n" for @unfound;
        $message = sprintf "Couldn't find %s of %s paths\n",
          scalar(@unfound),
          scalar(@manifest);
    }
    ok(0 == scalar @unfound, $message);
}

sub new_hub() {
    no warnings 'once';
    my $name     = shift or die "No name provided to new_hub\n";
    my $username = shift;

    Test::Socialtext::ensure_workspace_with_name($name);

    my $hub = Test::Socialtext::Environment->instance()->hub_for_workspace($name, $username);
    $Test::Socialtext::Filter::main_hub = $hub;
    return $hub;
}

sub ensure_workspace_with_name() {
    my $name = shift;
    return if Socialtext::Workspace->new( name => $name );

    create_test_workspace( unique_id => $name );
    return;
}

my $main_hub;

sub main_hub {
    $main_hub = shift if @_;
    $main_hub ||= Test::Socialtext::new_hub('admin');
    return $main_hub;
}

my @Added_accounts;
my @Added_users;
my @Added_groups;
{
    my $counter = 0;
    sub create_unique_id {
        my $id = time . $$ . $counter;
        $counter++;
        return $id;
    }

    sub create_test_account {
        my $unique_id = shift || create_unique_id;
        push @Added_accounts, $unique_id;
        my $hub       = main_hub();
        return $hub->account_factory->create( name => $unique_id, @_ );
    }

    sub create_test_account_bypassing_factory {
        my $unique_id = shift || create_unique_id;
        push @Added_accounts, $unique_id;
        return Socialtext::Account->create(name => $unique_id, @_);
    }

    sub create_test_user {
        my %opts = @_;
        my $uniq = delete $opts{unique_id} || create_unique_id;
        my $acct = delete $opts{account} || Socialtext::Account->Default;

        $opts{email_address} ||= $uniq.'@ken.socialtext.net';
        $opts{username} = delete $opts{username_isnt_email}
            ? $uniq : $opts{email_address};
        $opts{created_by_user_id} ||= Socialtext::User->SystemUser->user_id;

        my $user = Socialtext::User->create(
            %opts,
            primary_account_id => $acct->account_id,
        );
        push @Added_users, $user->user_id;
        return $user;
    }

    sub create_test_badmin {
        my %opts = @_;
        $opts{unique_id} = 'admin-'.create_unique_id;
        $opts{is_business_admin} = $opts{is_technical_admin} = 1;
        return create_test_user(%opts);
    }

    sub create_test_workspace {
        my %opts = @_;

        $opts{unique_id} ||= create_unique_id;
        $opts{account} ||= Socialtext::Account->Default;
        $opts{user} ||= Socialtext::User->SystemUser;

        # create a new test Workspace
        my $ws = Socialtext::Workspace->create(
            name               => $opts{unique_id},
            title              => $opts{unique_id},
            created_by_user_id => $opts{user}->user_id,
            account_id         => $opts{account}->account_id,
            skip_default_pages => 1,
        );
    }

    sub create_test_group {
        my %opts = @_;
        $opts{unique_id} ||= create_unique_id;
        $opts{account}   ||= Socialtext::Account->Default;
        $opts{user}      ||= Socialtext::User->SystemUser;

        my $group = Socialtext::Group->Create( {
            driver_group_name  => $opts{unique_id},
            created_by_user_id => $opts{user}->user_id,
            primary_account_id => $opts{account}->account_id,
        } );
        push @Added_groups, $group->group_id;

        if ($opts{refetch}) {
            # optionally re-fetch Group from DB
            $group = Socialtext::Group->GetGroup(group_id => $group->group_id);
        }
        return $group;
    }

    sub create_test_hub {
        my $unique_id = shift || '';
        $unique_id .= create_unique_id;

        # create a new test User
        my $user = create_test_user(unique_id => $unique_id);
        my $ws = create_test_workspace(unique_id => $unique_id, user => $user);

        # create a Hub based on this User/Workspace
        return new_hub($ws->name, $user->username);
    }
}

sub set_as_default_account($) {
    my $acct = shift;
    require Socialtext::SystemSettings;
    Socialtext::SystemSettings::set_system_setting(
        'default-account' => $acct->account_id);
    Socialtext::Account->Clear_Default_Account_Cache();
}

sub looks_like_pdf_ok($;$) {
    my $pdf = shift;
    my $msg = shift || 'looks like a PDF';
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $pdf_start = $pdf =~ qr/\A%PDF-\d+\.\d+/;
    my $pdf_end   = $pdf =~ qr/%%EOF\Z/;
    ok $pdf_start && $pdf_end, $msg;
}

sub SSS() {
    my $sh = $ENV{SHELL} || 'sh';
    system("$sh > `tty`");
    return @_;
}

# Provide a whole bunch of common diagnostics about our objects
sub dump_roles {
    print "\nRole Dump\n=========\n";
    if (@Added_users) {
        print "Added users:\n";
        for my $u (@Added_users) {
            my $user = Socialtext::User->new(user_id => $u);
            print "  * ($u) " . $user->username . "\n";
        }
    }
    if (@Added_groups) {
        print "Added groups:\n";
        for my $g (@Added_groups) {
            my $group = Socialtext::Group->GetGroup(group_id => $g);
            my $name = $group ? $group->driver_group_name : 'deleted';
            print "  * ($g) $name\n";
        }
    }
    if (@Added_accounts) {
        print "Added accounts\n";
        for my $name (@Added_accounts) {
            my $acct = Socialtext::Account->new(name => $name);
            my $acct_id = $acct->account_id();

            my $acct_users = $acct->users;
            my $user_count = $acct_users->count();
            my $acct_ws = $acct->workspaces;
            my $wksp_count = $acct_ws->count;
            my $acct_groups = $acct->groups(direct => 0);
            my $group_count = $acct_groups->count;
            print "  * ($acct_id) $name ($user_count users) "
                . "($wksp_count wksps) "
                . "($group_count groups)\n";


            my $sth = sql_execute(q{
                SELECT from_set_id FROM user_set_path
                 WHERE into_set_id = ?
                 }, $acct->user_set_id,
            );
            my $rows = $sth->fetchall_arrayref();
            my %related_user_sets = map { $_->[0] => 1 } @$rows;

            while (my $u = $acct_users->next) {
                my $role_id = $acct->user_set->direct_object_role($u);
                my $role = $role_id
                    ? Socialtext::Role->new(role_id => $role_id)->name
                    : 'indirect role';
                my $name = $u->username;
                my $id = $u->user_id;
                print "    U ($id) $name ($role)\n";
                
                if (! delete $related_user_sets{$u->user_set_id}) {
                    warn "      (THIS USER WAS NOT RELATED?!)\n";
                }
            }

            while (my $w = $acct_ws->next) {
                my $role_id = $acct->user_set->direct_object_role($w);
                my $role = $role_id
                    ? Socialtext::Role->new(role_id => $role_id)->name
                    : 'indirect role';
                my $name = $w->name;
                my $id = $w->workspace_id;
                print "    W ($id) $name ($role)\n";
                
                if (! delete $related_user_sets{$w->user_set_id}) {
                    warn "      (THIS WORKSPACE WAS NOT RELATED?!)\n";
                }

                my $users = $w->users;
                while (my $u = $users->next) {
                    my $name = $u->username;
                    my $id = $u->user_id;
                    my $role = $w->role_for_user($u)->name;
                    print "      U ($id) $name ($role)\n";
                }
            }

            while (my $g = $acct_groups->next) {
                my $role_id = $acct->user_set->direct_object_role($g);
                my $role = $role_id
                    ? Socialtext::Role->new(role_id => $role_id)->name
                    : 'indirect role';
                my $name = $g->driver_group_name;
                my $id = $g->group_id;
                print "    G ($id) $name ($role)\n";
                
                if (! delete $related_user_sets{$g->user_set_id}) {
                    warn "      (THIS GROUP WAS NOT RELATED?!)\n";
                }

                my $users = $g->users;
                while (my $u = $users->next) {
                    my $name = $u->username;
                    my $id = $u->user_id;
                    my $role = $g->role_for_user($u)->name;
                    print "      U ($id) $name ($role)\n";
                }
            }

            if (keys %related_user_sets) {
                warn "Other additional related user sets:\n";
                for my $set_id (sort keys %related_user_sets) {
                    if ($set_id <= USER_END) {
                        warn "  User: $set_id\n";
                    }
                    elsif ($set_id <= GROUP_END) {
                        $set_id -= GROUP_OFFSET;
                        warn "  Group: $set_id\n";
                    }
                    elsif ($set_id <= WKSP_END) {
                        $set_id -= WKSP_OFFSET;
                        warn "  Workspace: $set_id\n";
                    }
                    elsif ($set_id <= ACCT_END) {
                        $set_id -= ACCT_OFFSET;
                        warn "  Account $set_id\n";
                    }
                    else { die "Unknown user_set_id: $set_id" }
                }
            }
                  
        }
    }
    print "=========\n\n";
}

package Test::Socialtext::Filter;
use strict;
use warnings;

use base 'Test::Base::Filter';

# Add Test::Base filters that are specific to NLW here. If they are really
# generic and interesting I'll move them into Test::Base

sub interpolate_global_scalars {
    map {
        s/"/\\"/g;
        s/@/\\@/g;
        $_ = eval qq{"$_"};
        die "Error interpolating '$_': $@" 
          if $@;
        $_;
    } @_;
}

# Regexps with the '#' character seem to get messed up.
sub literal_lines_regexp {
    $self->assert_scalar(@_);
    my @lines = $self->lines(@_);
    @lines = $self->chomp(@lines);
    my $string = join '', map {
        # REVIEW: This is fragile and needs research.
        s/([\$\@\}])/\\$1/g;
        "\\Q$_\\E.*?\n";
    } @lines;
    my $flags = $Test::Base::Filter::arguments;
    $flags = 'xs' unless defined $flags;

    my $regexp = eval "qr{$string}$flags";
    die $@ if $@;
    return $regexp;
}

sub wiki_to_html {
    $self->assert_scalar(@_);
    Test::Socialtext::main_hub()->formatter->text_to_html(shift);
}

sub wrap_p_tags {
    $self->assert_scalar(@_);
    sprintf qq{<p>\n%s<\/p>\n}, shift;
}

sub wrap_wiki_div {
    $self->assert_scalar(@_);
    sprintf qq{<div class="wiki">\n%s<\/div>\n}, shift;
}

sub new_page {
    Carp::confess "new_page removed; convert your test to construct a page via accessors, sorry";
}

sub store_new_page {
    Carp::confess "store_new_page removed; convert your test to construct a page via accessors, sorry";
}

sub content_pane {
    my $html = shift;
    $html =~ s/
        .*(
        <div\ id="page-container">
        .*
        <td\ class="page-center-control-sidebar-cell"
        ).*
    /$1/xs;
    $html
}

sub _cleanerr() {
    my $output = shift;
    $output =~ s/^.*index.cgi: //gm;
    my @lines = split /\n/, $output;
    pop @lines;
    if (@lines > 15) {
        push @lines, "\n...more above\n", @lines[0..15]
    }
    join "\n", @lines;
}

1;

