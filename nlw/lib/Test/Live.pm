# @COPYRIGHT@
package Test::Live;
use strict;
use warnings;

use Class::Field qw(field);
use Cwd ();
use Digest::MD5 'md5_hex';
use File::Path;
use HTML::Tidy;
use HTTP::Request::Common;
use Socialtext::ApacheDaemon;
use Socialtext::Build qw(get_build_setting);
use Test::More;
use Test::Socialtext::Environment;
use Test::Socialtext::User;
use URI::Escape;

our @Import_options = qw(
    fixtures
);

our %Environment_params;

sub import {
    my $class = $_[0];
    my @passed_args;
    for (my $ii = 1; $ii <= $#_; ++$ii) {
        my $key = $_[$ii];
        if (grep { $_ eq $key } @Import_options) {
            $Environment_params{$key} = $_[++$ii];
        } else {
            push @passed_args, $key;
        }
    }
}

field 'apaches';
field 'mech';
field 'tidy';
field 'dont_log_in'  => 0;
field 'nlw_root_dir' => Cwd::getcwd . '/t/tmp';
field 'workspace'    => 'admin';
field 'ceqlotron_script' => Cwd::getcwd . '/bin/ceqlotron';

sub request_path { '/' . $_[0]->workspace . '/index.cgi' }

sub apache2 { $_[0]->apaches->{apache2} }
sub apache_perl { $_[0]->apaches->{'apache-perl'} }

sub new {
    my $class = shift;
    my $self = bless {}, $class;

    $self->prepare_apache_and_possibly_stop;
    $self->setup_env;
    $self->maybe_start_apache;
    $self->mech( Socialtext::Mechanize->new( autocheck => 1 ) );
    $self->tidy( HTML::Tidy->new );
    # The tidyer sure doesn't do a whole lot with this in place:
    $self->tidy->ignore( type => HTML::Tidy::TIDY_WARNING() );
    return $self;
}

sub DESTROY {
    my $self = shift;
    $self->stop_all unless $ENV{NLW_LIVE_DANGEROUSLY};
}

sub prepare_apache_and_possibly_stop {
    my $self = shift;

    $self->setup_env
        unless -d Cwd::getcwd() . '/t/tmp/etc';

    my @pairs = ( [qw(apache-perl httpd)], [qw(apache2 apache2)] );
    my %apaches;
    my $some_conf_dir_exists = 0;
    for my $pair ( @pairs ) {
        my ( $apache, $conf ) = @$pair;
        my $conf_file = Cwd::getcwd() . "/t/tmp/etc/$apache/nlw-$conf.conf";
        $some_conf_dir_exists ||= -e $conf_file;
        $apaches{$apache}
            = Socialtext::ApacheDaemon->new( conf_file => $conf_file );
    }

    $self->apaches( \%apaches );
    $self->stop_all if $some_conf_dir_exists and not $ENV{NLW_LIVE_DANGEROUSLY};
}

sub get_apaches {
    my $self = shift;
    return values %{ $self->apaches };
}

sub setup_env {
    my $self = shift;

    require Test::Socialtext;
    Test::Socialtext->import();

    $ENV{NLW_CONFIG} = Cwd::cwd . '/t/tmp/etc/socialtext/socialtext.conf';

    Test::Socialtext::Environment->CreateEnvironment(
        root_dir       => $self->nlw_root_dir,
        fixtures       => $Environment_params{fixtures} || ['ALL'],
    );
}

sub maybe_start_apache {
    my $self = shift;

    File::Path::mkpath( "t/tmp/$_", 0, 0755 )
        for qw(log/apache2 log/apache-perl run);
    $_->blank_log_files for $self->get_apaches;
    $self->start_all;
}

sub standard_query_validation {
    my $self = shift;

    $self->log_in
        unless $self->dont_log_in;
    Test::Socialtext::plan('no_plan');
    my $working_dir = Cwd::getcwd();
    while (my $block = Test::Socialtext::next_block()) {
        my $special_contents = $self->do_special_action( $block->do, $block )
            if $block->do;
        my $whole_page = $special_contents
            || $self->request( $block, $self->noReturnOk($block) );
        $self->run_validation($whole_page, $block);
        if( Cwd::getcwd() ne $working_dir ) {
            Test::More::diag( "changing back to $working_dir\n" );
            chdir $working_dir;
        }
    }
}

sub noReturnOk {
    my $self = shift;
    my $block = shift;

    for (keys %$block) {
        if (/^(match_noreturn.*)/) {
            return 1;
        }
    }

    return 0;
}

sub run_validation {
    my $self = shift;

    my $whole_page = shift;
    my $block = shift;
    my $relevant_content =
        defined $block->MATCH_WHOLE_PAGE
        ? $whole_page
        : Test::Socialtext::Filter->content_pane($whole_page);

    my $header_content = $self->mech->response()->headers()->as_string();

    if (defined $block->SNAPSHOT) {
        my $output = 'snapshot_of_live_test_output'; # . "_$$" ?
        Test::More::diag("--- SNAPSHOT'ing to $output\n");
        open my $fh, '>', $output
            or die "Cannot write to $output: $!";
        print $fh $relevant_content
            or die "Cannot write to $output: $!";
        close $fh
            or die "Cannot write to $output: $!";
    }

    $self->sanity_check($whole_page, $block);

    for (keys %$block) {
        next unless /^(nomatch|mail_alias_sends_to|manifest)$/ or
                    /^(match.*)/ or
                    /^(match_\w+.*)/;
        my $method = "validate_$1";
        if ($self->_checksHeader($_)) {
            $self->$method($header_content, $block, $_);
        } elsif ($self->_checksStatus($_)) {
            $self->$method($self->mech()->status(), $block, $_);
        } else {
            $self->$method($relevant_content, $block, $_);
        }
    }
}

sub _checksHeader {
    my $self = shift;
    my $MATCH_TYPE = shift;

    return $MATCH_TYPE =~ /^match_header/;
}

sub _checksStatus {
    my $self = shift;
    my $MATCH_TYPE = shift;

    return $MATCH_TYPE =~ /^match_status/;
}

sub static_sums_match {
    my $self = shift;

    my($static_path) = @_;

    my $expected_sum = _md5file("share/$static_path");
    my $got_sum = md5_hex($self->get_content("/static/$static_path"));

    is($got_sum, $expected_sum, "$static_path md5sum is correct");
}

sub _md5file {
    my $path = shift;

    open MD5FILE, $path or die "$path: $!";

    my $md5 = Digest::MD5->new;
    $md5->addfile(\*MD5FILE);
    return $md5->hexdigest;
}

sub get_content {
    my $self = shift;

    my($request_path, $query_string, $block) = @_;

    my $url = $self->base_url . $request_path;
    $url .= "?$query_string" if $query_string;

    if ($block && $block->accept) {
        $self->mech->add_header(Accept => $block->accept);
    }

    $self->mech->get($url);

    return $self->mech->content;
}

sub request {
    my $self = shift;
    my $block = shift;
    my $ALLOW_EMPTY_RETURN = shift;

    my $ret;
    eval {
        if ($block->follow_link) {
            my $block = YAML::Load($block->follow_link);
            if ($block->{text_regex}) {
                my $regex = delete $block->{text_regex};
                $block->{text_regex} = qr/$regex/;
            }
            $self->mech->follow_link(%{$block});
            $ret = $self->mech->content;
        }
        else { # check request_path, query, and post
            if ($block->multipart_post) {
                my $request_path = $block->request_path || $self->request_path;
                my $post = YAML::Load($block->multipart_post);

                my $request = POST(
                    $self->base_url . $request_path,
                    Content_Type => 'form-data',
                    Content => [
                        embed => $post->{embed},
                        creator  => Test::Socialtext::User->test_username(),
                        filename => [$post->{file}],
                    ],
                );

                my $mech = $self->mech;
                my $response = $mech->request($request);
                $ret = $response->content;
            } elsif ($block->put) {
                my $request_path = $block->request_path || $self->request_path;
                if ($block->accept) {
                    $self->mech->add_header(Accept => $block->accept);
                }
                my $request = HTTP::Request->new(PUT => $self->base_url . $request_path . '/' . $block->put );
                my $mech = $self->mech;
                my $response = '';
                eval {
                    $response = $mech->request($request);
                };
                if (!$@) {
                    $ret = $response->content;
                }
            } elsif ($block->delete) {
                my $request_path = $block->request_path || $self->request_path;
                if ($block->accept) {
                    $self->mech->add_header(Accept => $block->accept);
                }
                my $request = HTTP::Request->new(DELETE => $self->base_url . $request_path . '/' . $block->delete );
                my $mech = $self->mech;
                my $response = '';
                eval {
                    $response = $mech->request($request);
                };
                if (!$@) {
                    $ret = $response->content;
                }
            } elsif ($block->post) {
                $self->mech->submit_form($self->_yaml_to_post($block));
                $ret = $self->mech->content;
            }
            else {
                my $request_path = $block->request_path || $self->request_path;
                my $query;
                $query = $self->_yaml_to_query_string($block->query)
                    if $block->query;
                $ret = $self->get_content($request_path, $query, $block);
            }
        }
    };
    if ($@) {
        my $additional = $@ =~ /^(?:No such field|No clickable input)/
          ? $@ . "\n" . $self->_debug_dump_available_forms
          : '';
        Test::More::fail($block->name);
        die
            "\n\e[034mAccess Log\e[0m:\n"
            . $self->apache_perl->access_log
            . "\n\e[031mError Log\e[0m:\n"
            . $self->apache_perl->error_log
            . "\n\e[035mDollar At\e[0m:\n"
            . "$@\n"
            . $additional
            . "\n";
    }
    Test::More::diag($block->name . " request returned nothing.\n")
      unless ($ret || (defined($ALLOW_EMPTY_RETURN) && $ALLOW_EMPTY_RETURN));
    return $ret;
}


sub log_in {
    my $self = shift;
    my $username = shift || Test::Socialtext::User->test_username();
    my $password = shift || Test::Socialtext::User->test_password();

    $self->mech->get($self->base_url . '/challenge');
    $self->mech->submit_form(
        fields => {
            username => $username,
            password => $password
        }
    );
}

sub sanity_check {
    my $self = shift;
    my $content = shift;
    my $block = shift;

    my $name = '"' . $block->name . '"';

    unless (defined $block->SKIP_DOUBLE_ESCAPE_SANITY_CHECK) {
        fail("$name showed what appears to be double-escaped html: $1")
          if $content =~ /(.{50}&(\w+);\2;.{50})/s;
    }

    $self->tidy->clear_messages;
    $self->tidy->parse($content);
    fail("$name - " . $_->as_string) for $self->tidy->messages;

    # TODO - make this more aggressive when we no longer have legacy img's in
    # the help docs.
    if ($content =~ m{(/static/(css|javascript)[^"]*)}) {
        fail("$name had $1 - should use Socialtext::Helpers->static_path");
    }

    # ...and may there be many more.
}

sub validate_match_file {
    my ($self, $relevant_content, $block, $re) = @_;
    my $filename = $block->match_file;

    open my $fh, '<', $filename or die "Can't open $filename: $!\n";
    my $content = do {local $/; <$fh>};
    close $fh or die "Can't close $filename: $!\n";

    is $relevant_content, $content,
        $block->name . " - Request content matched $filename";
}

sub validate_match_noreturn {
    my $self = shift;
    my $relevant_content = shift;
    my $block = shift;
    my $re = shift;

    ok ((!defined($relevant_content)) || length($relevant_content) == 0), $block->name . ' - noreturn- success';
}

sub validate_match_status {
    my $self = shift;
    my $relevant_content = shift;
    my $block = shift;
    my $re = shift;

    smarter_like(
        $relevant_content,
        $block->$re,
        $block->name . " - match",
        $Test::Live::Order_doesnt_matter,
    );
}

sub validate_match_header {
    my $self = shift;
    my $relevant_content = shift;
    my $block = shift;
    my $re = shift;

    smarter_like(
        $relevant_content,
        $block->$re,
        $block->name . " - match",
        $Test::Live::Order_doesnt_matter,
    );
}

sub validate_match {
    my $self = shift;
    my $relevant_content = shift;
    my $block = shift;
    my $re = shift;

    smarter_like(
        $relevant_content,
        $block->$re,
        $block->name . " - match",
        $Test::Live::Order_doesnt_matter,
    );
}

sub validate_match_unreliable {
    my $self = shift;
    my $relevant_content = shift;
    my $block = shift;
    my $pattern = $block->match_unreliable;

    $self->validate_match($relevant_content, $block, 'match_unreliable')
        if $ENV{TEST_VERBOSE};

    my $result = $block->name . ' - '
        . ($relevant_content =~ qr/$pattern/ ? 'passed' : 'failed')
        . " pid: $$, date: " . Socialtext::System::backtick('date');

    Test::More::diag($result)
        # because we've already admitted failure (from inside validate_match):
        unless $ENV{TEST_VERBOSE};

    my $file = "/tmp/test-live-failures-$<";
    open my $fh, '>>', $file
        or die "Cannot append to $file: $!";
    print $fh $result
        or die "Cannot append to $file: $!";
    close $fh
        or die "Cannot append to $file: $!";
}

sub validate_nomatch {
    my $self = shift;
    my $relevant_content = shift;
    my $block = shift;
    smarter_unlike(
        $relevant_content,
        $block->nomatch,
        $block->name . " - nomatch",
    );
}

sub validate_mail_alias_sends_to {
    my $self = shift;
    my $relevant_content = shift;
    my $block = shift;

    my $hub = Test::Socialtext::Environment->instance()->hub_for_workspace($block->new_workspace_id);
    smarter_like(
        Socialtext::EmailAlias::find_alias($block->new_workspace_id),
        $block->mail_alias_sends_to,
        "mail alias properly set",
    );
}

sub validate_manifest {
    my $self = shift;
    my $relevant_content = shift;
    my $block = shift;

    require Test::Socialtext;
    Test::Socialtext->check_manifest($block);
}

sub validate_match_content_type {
    my $self = shift;
    my $relevant_content = shift;
    my $block = shift;

    Test::More::is($self->mech->ct, $block->match_content_type,
        "content-type for " . $block->name);
}

# Now that autocheck is on, this overlaps the functionality some (but not
# entirely - e.g., check the page for Errors isn't covered by autocheck)
# It could use a little thoughtful refactoring, though.
sub check_mech {
    my $self = shift;
    my $fetch_name = shift;
    my $message = shift;

    if (not($self->mech->success) or
        $self->mech->content =~ /Software error/ or
        $self->mech->content =~ /500 Internal Server Error/
    ) {
        Test::More::fail(
             "\n$fetch_name failed.\n"
             . $message
             . "\nstatus: " . $self->mech->status
             . "\n   log: ...\n" . $self->apache_perl->error_log . "\n");
        return 0;
    }
    return 1;
}

sub confirm_page_active {
    my $self = shift;
    my $workspace = shift;
    my $page_name = shift;

    my $hub = Test::Socialtext::Environment->instance()->
        hub_for_workspace($workspace);
    my $page = $hub->pages->new_from_name($page_name);
    return $page->active;
}

sub _yaml_to_query_string {
    my $self = shift;

    require YAML;
    my $yaml = shift;
    my $params = $yaml
      ? YAML::Load($yaml)
      : {};
    return join ';', map {
        uri_escape($_) . '=' . uri_escape($params->{$_})
    } keys %$params;
}

sub _yaml_to_post {
    my $self = shift;
    my $block = shift;

    my $post = YAML::Load($block->post);

    if ($block->form) {
        if ($block->form =~ /^\s*[0-9]+\s*$/) {
            $self->mech->form_number($block->form);
        }
        else {
            $self->mech->form_name($block->form);
        }
    }
    else {
        $self->mech->form_number(1);
    }

    # The rest of this is to doctor the data structures up so we can keep the
    # live test specifications as simple as possible, hiding irrelevant
    # WWW::Mechanize details where it makes sense.
    if (my $checkboxes = delete $post->{_checkboxes}) {
        for my $name (keys %$checkboxes) {
            my %values = %{$checkboxes->{$name}};
            while (my ($value, $is_set) = each %values) {
                $self->mech->tick($name, $value, $is_set);
            }
        }
    }
    my %args = ( fields => $post );
    if ($post->{Button}) {
        $args{button} = delete $post->{Button};
    }

    if ($block->accept) {
        $self->mech->add_header(Accept => $block->accept);
    }

    return %args;
}

sub _debug_dump_available_forms {
    my $self = shift;

    return "Available forms: " . YAML::Dump([$self->mech->forms]) . "\n"
}

sub base_url {
    my $self = shift;

    my $base = Test::Socialtext::Environment->instance()->wiki_url_base;
}

sub do_special_action {
    my $self = shift;
    my $action = shift;
    my $block = shift;

    my @args = split /\s+/, $action;
    my $cmd = shift @args;
    my %actions = (
        setPermissions => sub {
            $self->_use_class('Socialtext::Workspace');

            my $workspace
                = Socialtext::Workspace->new( name => $self->workspace );
            $workspace->permissions->set( @args );
        },
        addPermission => sub {
            $self->_use_class($_)
                for qw( Socialtext::Permission Socialtext::Role
                        Socialtext::Workspace );

            my $workspace
                = Socialtext::Workspace->new( name => $self->workspace );
            $workspace->permissions->add(
                role       => Socialtext::Role->new( name => shift ),
                permission => Socialtext::Permission->new( name => shift ),
            );
        },
        removePermission => sub {
            $self->_use_class($_)
                for qw( Socialtext::Permission Socialtext::Role
                        Socialtext::Workspace );

            my $workspace
                = Socialtext::Workspace->new( name => $self->workspace );
            $workspace->permissions->remove(
                role       => Socialtext::Role->new( name => shift ),
                permission => Socialtext::Permission->new( name => shift ),
            );
        },
        sleep => sub {
            my $seconds = shift || 10; # a default so it doesn't sleep forever
            Test::More::ok(1, "$seconds second sleep");
            sleep $seconds;
            return;
        },
        waitForSearchIndex => sub {
            sleep 2; # XXX possible race while waiting for fork to start
            return $self->do_special_action(
                "waitUntilNomatch Search Index is currently being updated",
                $block,
            );
        },
        waitUntilNomatch => sub {
            my $pattern = join ' ', @args;
            my ($snooze_time, $max_snoozes) = (2, 100);
            my $x = 0;
            Test::More::diag("Matched $pattern") if $ENV{TEST_VERBOSE};
            until ($x++ == $max_snoozes) {
                sleep $snooze_time;
                my $page = $self->request($block);
                if ($page !~ /$pattern/) {
                    Test::More::diag("\n") if $ENV{TEST_VERBOSE};
                    return $page;
                }
                Test::More::diag(".") if $ENV{TEST_VERBOSE};
            }
            Test::More::diag(
                "$max_snoozes x $snooze_time seconds wasn't enough"
            );
            return;
        },
        log_in => sub {
            $self->log_in(@args);
            return;
        },
        pause => sub {
            Test::More::diag("Waiting for ^C (or 10 minutes).  Feel free to explore:\n\t"
                             . $self->base_url . "\n");
            local $SIG{INT} = sub { $self->stop_all };
            sleep 10 * 60;
            return;
        },
        chdir => sub {
            my ( $dir ) = @args;
            Test::More::diag( "changing dir to $dir\n" );
            chdir( $dir ) || die "can't chdir to $dir: $@\n";
            return;
        },
        accept => sub { # XXX
            my ($header, $value) = @args;
            warn "accept command - $value\n";
            $self->mech->add_header('Accept' => $value);
            return;
        },
        header => sub {
            my ($header, $value) = @args;
            $self->mech->default_header($header => $value);
            return;
        },
        setWorkspaceConfig => sub {
            my( $config_name, $config_value ) = @args;
            my $workspace
                = Socialtext::Workspace->new( name => $self->workspace );
            $workspace->update( $config_name => $config_value );
            return;
        },

    );
    $actions{$cmd} or die "No can do: $cmd";
    $actions{$cmd}->(@args);
}

sub _use_class {
    my $self = shift;
    my $class = shift;

    return if $class->can('new');

    eval "use $class";
}

sub start_all {
    my $self = shift;

    $_->start for grep { ! $_->is_running } $self->get_apaches;
}

sub stop_all {
    my $self = shift;

    $_->stop for $self->get_apaches;
}

package Socialtext::Mechanize;
use strict;
use warnings;

use base 'WWW::Mechanize';
# If we revive this, here's how it was working before, from Test::Live::new
#    $self->mech->set_basic_credentials(
#        $args{user}     || Test::Socialtext::Environment->instance()->owner,
#        $args{password} || Test::Socialtext::Environment->instance()->password,
#    );
sub set_basic_credentials { @{ $_[0] }{qw(__user__ __password__)} = @_[1,2] }
sub get_basic_credentials { @{ $_[0] }{qw(__user__ __password__)} }


1;

__END__

=head1 METHODS

=over 4

=item * get_content($request_path, $query_string);

Uses WWW:Mechanize to GET the content at the given path relative to the test
server instance.  $query_string is tacked on to the end if given.

=item * static_sums_match($static_file);

GETs the file at /static/$static_file and verifies that its md5sum matches the
one from base/$static_file in the local filesystem.

=back
