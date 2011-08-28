package Socialtext::WikiFixture::SocialBase;
# @COPYRIGHT@
use strict;
use warnings;
use Carp qw(cluck);
use Socialtext::AppConfig;
use Socialtext::Account;
use Socialtext::User;
use Socialtext::SQL qw/:exec :txn/;
use Socialtext::JSON qw/encode_json decode_json_utf8 decode_json/;
use Socialtext::File;
use Socialtext::Group;
use Socialtext::System qw();
use Socialtext::HTTP::Ports;
use Socialtext::PrefsTable;
use Socialtext::Role;
use Socialtext::People::Profile;
use Socialtext::UserSet qw(ACCT_OFFSET GROUP_OFFSET);
use Socialtext::Cache;
use Socialtext::Workspace;
use Socialtext::Encode qw/ensure_is_utf8/;
use Encode;
use File::LogReader;
use File::Path qw(rmtree);
use File::Temp qw(tempfile);
use Test::More;
use Test::HTTP;
use Test::Socialtext;
use Time::HiRes qw/gettimeofday tv_interval time/;
use URI::Escape qw(uri_unescape uri_escape);
use Data::Dumper;
use List::MoreUtils qw(any);
use Cwd;
use HTTP::Request::Common;
use LWP::UserAgent;
use Socialtext::l10n qw(loc);
use YAML qw/LoadFile/;
use DateTime;
use File::Basename;
use File::Spec;

# mix-in some commands from the Socialtext fixture
# XXX move bodies to SocialBase?
{
    require Socialtext::WikiFixture::Socialtext;
    no warnings 'redefine';
    *st_admin = \&Socialtext::WikiFixture::Socialtext::st_admin;
    *st_config = \&Socialtext::WikiFixture::Socialtext::st_config;
}

=head1 NAME

Socialtext::WikiFixture::SocialBase - Base fixture class that has shared logic

=head2 init()

Creates the Test::HTTP object.

=cut

sub init {
    my $self = shift;

    # provide access to the default HTTP(S) ports in use
    $self->{http_port}          = Socialtext::HTTP::Ports->http_port();
    $self->{https_port}         = Socialtext::HTTP::Ports->https_port();
    $self->{backend_http_port}  = Socialtext::HTTP::Ports->backend_http_port();
    $self->{backend_https_port} = Socialtext::HTTP::Ports->backend_https_port();
    $self->{userd_port}         = Socialtext::HTTP::Ports->userd_port();
    $self->{pushd_port}         = Socialtext::HTTP::Ports->pushd_port();

    if ($self->_is_wikiwyg()  ) {
        $self->{miki_signal_disclaimer} = 'Post to';
        $self->{miki_signal_text} = 'Post to';
        $self->{miki_signal_submit} = 'mobile_post';
        $self->{st_mobile_account_select} = 'mobile_signal_network';
        $self->{miki_mysignals_link_name} = 'myself';
        $self->{miki_people_i_follow} = 'people I follow';
        $self->{miki_everyone} = 'everyone';
    } else {
        $self->{miki_signal_disclaimer} = 'Post to';
        $self->{miki_signal_text} = 'What are you working on?';
        $self->{miki_signal_submit} = 'st-signal-submit';
        $self->{st_mobile_account_select} = 'st-select-network';
        $self->{miki_mysignals_link_name} = 'Mine';
        $self->{miki_people_i_follow} = 'People I follow';
        $self->{miki_everyone} = 'All';
    }

    my $def = Socialtext::Account->Default;
    $self->{default_account} = $def->name;
    $self->{default_account_id} = $def->account_id;

    # reset some defaults
    $self->st_config('set challenger STLogin')
        unless Socialtext::AppConfig->challenger eq 'STLogin';
    $self->st_config('set signals_size_limit 1000')
        unless Socialtext::AppConfig->signals_size_limit == 1000;
    $self->st_config('set default_workspace ""')
        if Socialtext::AppConfig->default_workspace;

    # Set up the Test::HTTP object initially
    $self->http_user_pass($self->{username}, $self->{password});
}



sub _munge_command_and_opts {
    my $self = shift;
    my $command = lc(shift);
    my @opts = $self->_munge_options(@_);
    $command =~ s/-/_/g;
    $command =~ s/^\*(.+)\*$/$1/;

    if ($command !~ /^body_(?:un)?like$/ and $command =~ /_(?:un)?like$/) {
        $opts[1] = $self->quote_as_regex($opts[1]);
    }

    return ($command, @opts);
}

sub _handle_command {
    my $self = shift;
    my ($command, @opts) = @_;

    if (__PACKAGE__->can($command)) {
        return $self->$command(@opts);
    }
    if ($self->{http}->can($command)) {
        return $self->{http}->$command(@opts);
    }
    die "Unknown command for the fixture: ($command)\n";
}

=head2 set_nlw_cookie_for_user ( $username )

Set the NLW cookie to a valid cookie for $username

=cut

sub set_nlw_cookie_for_user {
    my ($self, $username) = @_;

    $username ||= $self->{http_username};
    my $user = Socialtext::User->Resolve($username);

    require Test::Socialtext::Cookie;
    my $cookie = Test::Socialtext::Cookie->BuildCookie(
        user_id => $user->user_id,
    );
    $self->{_cookie} = $cookie;
}

=head2 set_expired_nlw_cookie_for_user ( $username )

Set an NLW cookie for $username that has B<expired> and is no longer valid.

=cut

sub set_expired_nlw_cookie_for_user {
    my ($self, $username) = @_;

    $username ||= $self->{http_username};
    my $user = Socialtext::User->Resolve($username);

    require Test::Socialtext::Cookie;
    my $cookie = Test::Socialtext::Cookie->BuildExpiredCookie(
        user_id => $user->user_id,
    );
    $self->{_cookie} = $cookie;
}

=head2 set_nlw_cookie_needing_renewal_for_user ( $username )

Set an NLW cookie for $username that is valid but that should be renewed.

=cut

sub set_nlw_cookie_needing_renewal_for_user {
    my ($self, $username) = @_;

    $username ||= $self->{http_username};
    my $user = Socialtext::User->Resolve($username);

    require Test::Socialtext::Cookie;
    my $cookie = Test::Socialtext::Cookie->BuildCookieNeedingRenewal(
        user_id => $user->user_id,
    );
    $self->{_cookie} = $cookie;
}

=head2 set_nlw_cookie ( $cookie )

Set the NLW cookie to the given $cookie

=cut
sub set_nlw_cookie {
    my ($self, $cookie) = @_;
    require Socialtext::HTTP::Cookie;
    my $name = Socialtext::HTTP::Cookie::USER_DATA_COOKIE();
    $self->{_cookie} = "$name=$cookie";
}

=head2 clear_nlw_cookie ()

Clear the NLW cookie

=cut
sub clear_nlw_cookie { $_[0]->{_cookie} = "" }

=head2 set_cookie ($cookie)

Sets a cookie for subsequent HTTP requests
=cut

sub set_cookie {
    my ($self, $cookie) = @_;
    $self->{_cookie} = $cookie;
}

=head2 http_user_pass ( $username, $password )

Set the HTTP username and password.

=cut

sub http_user_pass {
    my $self = shift;
    my $user = shift;
    my $pass = shift;

    my $name = ($self->{http}) ? $self->{http}->name : 'SocialRest fixture';

    $self->{http} = Test::HTTP->new($name);
    $self->{http}->username($user) if $user;
    $self->{http}->password($pass) if $pass;

    # store it locally too.
    $self->{http_username} = $user if $user;
    $self->{http_password} = $pass if $pass;

    $self->clear_nlw_cookie;
}

=head2 http_user_pass_and_cookie ( $username, $password )

Set the HTTP username and password.

=cut

sub http_user_pass_and_cookie {
    my $self = shift;
    my $user = shift;
    my $pass = shift;
    $self->http_user_pass($user,$pass);
    $self->set_nlw_cookie_for_user($user);
}

=head2 follow_redirects_for ( $methods )

Choose which methods to follow redirects for.

Default: | follow_redirects_for | GET, HEAD |

Don't follow any redirects: | follow_redirects_for | |

=cut

sub follow_redirects_for {
    my $self    = shift;
    my $methods = shift || '';

    my @methods = map { uc } split m/\s*,\s*/, $methods;

    diag "Only following " . join ', ', @methods;
    $self->{http}->ua->requests_redirectable(\@methods);
}

=head2 big_db

Loads the database with records.  Configured through wiki
variables as follows:

=over 4

=item db_accounts

=item db_users

=item db_pages

=item db_events

=item db_signals

=item db_groups

=back

=cut

sub big_db {
    my $self = shift;
    my @args = map { ("--$_" => $self->{"db_$_"}) }
        grep { exists $self->{"db_$_"} }
        qw(accounts users pages events signals groups);

    Socialtext::System::shell_run('really-big-db.pl', @args);
}

=head2 stress_for <secs>

Run the stress test code for this many seconds.

=cut

sub stress_for {
    my $self = shift;
    my @args = map { ("--$_" => $self->{"torture_$_"}) }
        grep { exists $self->{"torture_$_"} }
        qw(signalsleep postsleep eventsleep background-sleep signalsclients postclients eventclients background-clients use-at get-avs server limit rampup followers sleeptime base users);

    Socialtext::System::shell_run('torture', @args);
}

=head2 invalidate_dbh

Invalidates the DBH used in-process.  If you've restarted Pg, you'll want to
run this command to force a reconnect.

=cut

sub invalidate_dbh {
    Socialtext::SQL::invalidate_dbh();
    ok 1, "dbh handle invalidated";
}

=head2 password standard-test-setup

Set up a new account, workspace and user to work with.

=cut

sub standard_test_setup {
    my $self = shift;
    my $prefix = shift || '';
    my $option = shift || '';
    my $no_group = $option eq 'no-group';
    $prefix .= '_' if $prefix;
    my $acct_name = shift || "${prefix}acct-$self->{start_time}";
    my $wksp_name = shift || "${prefix}wksp-$self->{start_time}";
    my $user_name = shift || "${prefix}user-$self->{start_time}\@ken.socialtext.net";
    my $password  = shift || "${prefix}password";
    my $group_name = shift || "${prefix}group";

    my $acct  = $self->create_account($acct_name);
    my $wksp  = $self->create_workspace($wksp_name, $acct_name);
    my $user  = $self->create_user($user_name, $password, $acct->name);
    $self->add_workspace_admin($user_name, $wksp_name);

    $self->{"${prefix}account"} = $acct_name;
    $self->{"${prefix}account_id"} = $acct->account_id;
    $self->{"${prefix}workspace"} = $wksp_name;
    $self->{"${prefix}workspace_id"} = $wksp->workspace_id;
    $self->{"${prefix}email_address"} = $user_name;
    $self->{"${prefix}username"} = $user_name;
    $self->{"${prefix}user_id"} = $user->user_id;
    $self->{"${prefix}user_name_and_email"} = $user->name_and_email;
    $self->{"${prefix}password"} = $password;

    unless ($no_group) {
        my $group = $self->create_group($group_name, $acct_name, $user_name);
        $wksp->add_group(group => $group);
        $self->{"${prefix}group"} = $group_name;
        $self->{"${prefix}group_id"} = $self->{group_id};
    }
    $self->http_user_pass($user_name, $password);
}

=head2 st_open_noeval ($url)

Opens a page that maybe should return a 404 or something

=cut

sub st_open_noeval {
    my ($self, $url) = @_;
    my %valid_pre_open_commands = (open => 1, testComplete => 1, getNewBrowserSession => 1,);
    my $command = 'open';
    if (!$self->{_page_opened} and !$valid_pre_open_commands{$command}) {
        die "You must open a page before calling $command. eg: \$sel->open('/');\n";
    }
    $command = uri_escape('open');
    my $fullurl = "http://$self->{host}:$self->{port}/selenium-server/driver/" . "\?cmd=$command";
    $fullurl .= '&1=' . URI::Escape::uri_escape_utf8($url);
    print "fullurl is $fullurl\n";
    if (defined $self->{selenium}->{session_id}) {
        $fullurl .= "&sessionId=$self->{selenium}->{session_id}";
    }
    print "---> Requesting $fullurl\n" if $self->{verbose};
    my $ua = LWP::UserAgent->new;
    my $response = $ua->request( HTTP::Request->new(GET => $fullurl) );
    #Wait for page to acutally open. 
    $self->handle_command('pause',20000);
}


=head2 st_ff_and_ie_wait_for_text_not_present ($text, $howlong)

Say some text is in javascript and is present but not visible.  FF3 and IE can see the text is not present, googlechrome is ... confused.

Check for text not present ONLY in IE and FF3

=cut

sub st_ff_and_ie_wait_for_text_not_present {
    my ($self, $text, $howlong) = @_;
    my $browser = $ENV{'selenium_browser'} || 'chrome';
    if ($browser=~/safari|chrome|firefox|iexplore/ig && !($browser=~/googlechrome/ig) )  {
       $self->handle_command('wait_for_text_not_present_ok',$text,$howlong);
    } else {
       ok 1, 'in googlechrome we do not check for text here'; 
    }
}

=head2 st_wait_for_text_not_present ($text, $howlong)

Say some text is in javascript and is present but not visible.  FF3 can see the text is not present, other browsers are ... confused.

Check for text not present ONLY in FF3

=cut

sub st_ff_wait_for_text_not_present {
    my ($self, $text, $howlong) = @_;
    my $browser = $ENV{'selenium_browser'} || 'chrome';
    if ($browser=~/chrome|firefox/ig && !($browser=~/googlechrome/ig) )  {
        $self->handle_command('wait_for_text_not_present_ok',$text,$howlong);
     } else {
         ok 1, 'in googlechrome we do not check for text here';
     }
}



sub _relative_filename_to_absolute {
    my $self = shift;
    my $filename = shift;
    return $filename if -e $filename;
    return $filename if File::Spec->file_name_is_absolute($filename);
    return File::Spec->rel2abs(dirname(__FILE__) . "/../../../" . $filename);
}

sub _get_random_page_content {
    my $self = shift;
    return split /\n/, qq/In the days when Sussman was a novice Minsky once came to him as he sat hacking at the PDP-6.
"What are you doing?", asked Minsky.
"I am training a randomly wired neural net to play Tic-Tac-Toe."
"Why is the net wired randomly?", inquired Minsky.
"I do not want it to have any preconceptions of how to play".
At this Minsky shut his eyes, and Sussman asked his teacher "Why do you close your eyes?"
"So that the room will be empty."
At that moment, Sussman was enlightened./;
}

=head2 st_create_pages($workspace, $numberpages, optional $pageprefix)

Creates $numpages number of pages in $workspace

=cut

sub st_create_pages {
    my ($self, $workspace, $numberpages, $pageprefix, $text) = @_;

    my $user = Socialtext::User->new(username => $self->{'username'});
    my $hub = new_hub($workspace);
    my @lines = $self->_get_random_page_content;
    for (my $idx=0; $idx<$numberpages;$idx++) {
        if (!defined($pageprefix) or length($pageprefix)<1) {
           $pageprefix = "test page ";
        }
        my $title = $pageprefix . $idx;
  
        my $content;
        if (defined($text) && length($text)>1) {
           $content = $text;
        } else { 
            $content = shift @lines; 
            push @lines, $content;
        }

        Socialtext::Page->new(hub => $hub)->create(
                                  title => $title,
                                  content => $content,
                                  creator => $user);
    }
    ok 1, "Created $numberpages of pages in $workspace";
}

=head2 st_massive_tags (post URL, start tags with, end tag with - examples 'aa' and 'az' would  make 26 tags.)

Automates multiple runs of POSTING an add tag to a workspace
Actually, it can automate pretty much any post.  To automate tagging, your URL should look something like his:

/data/workspaces/%%ws%%/pages/pagname/tags

Where %%ws%% is the workspace name and pagename is the actual page name.

=cut

sub st_massive_tags {
    my ($self, $url, $tagstart, $tagend) = @_;
    for (my $idx=$tagstart; $idx lt $tagend; $idx++) {
       $self->handle_command('POST',$url,'Content-Type=text/plain', $idx);
    }
    ok(1, 'Finished call to st_massive_tags');
    
}

sub st_create_page {
    my ($self, $workspace, $title) = @_;
    my $user = Socialtext::User->new(username => $self->{'username'});
    my $hub = new_hub($workspace);
    my $content = "Content for title test";
    Socialtext::Page->new(hub => $hub)->create(
                                  title => $title,
                                  content => $content,
                                  creator => $user);
    ok 1, "Created $title in $workspace";
}

sub stub_page {
    my ($self, $workspace, $title, $content) = @_;
    my $user = Socialtext::User->SystemUser;
    my $hub = new_hub($workspace);

    $content ||= "Placeholder content ".$self->{start_time};
    Socialtext::Page->new(hub => $hub)->create(
                              title => $title,
                              content => $content,
                              creator => Socialtext::User->SystemUser);
}

=head2 st_search_for($searchtype, $searchvalue)

Global nav search automation

Assumes the selement 'st-search-element' is on the page, selects $searchtype

Suggest searchs as of Oct 2009: 

Search My Workspaces:
Search People: 
Search Signals:

=cut

sub st_search_for {
    my ($self, $searchtype, $searchvalue) = @_;
    $self->handle_command('wait_for_element_visible_ok','st-search-action',30000);
    $self->handle_command('select_ok', 'st-search-action', $searchtype);
    $self->handle_command('wait_for_element_visible_ok','st-search-term',30000);
    $self->handle_command('type_ok','st-search-term',$searchvalue);
    $self->handle_command('wait_for_element_visible_ok','st-search-submit',30000);
    $self->handle_command('click_ok','st-search-submit');
}

=head2 st_search_cp_workspace($searchfor, $clickthrough)

Control panel workspace search automation

Goes to url /nlw/control/workspace and searches the name $searchfor 

if $clickthrough is defined and true (1), it will click through to that workspace

=cut


sub st_search_cp_workspace {
    my ($self, $searchfor, $clickthrough) = @_;
    $self->handle_command('open_ok', '/nlw/control/workspace');
    $self->handle_command('wait_for_element_visible_ok','name',30000);
    $self->handle_command('wait_for_element_visible_ok','st-ws-search-submit',30000);
    $self->handle_command('type_ok','name',$searchfor);
    $self->handle_command('click_and_wait','st-ws-search-submit');
    my $str = "Workspaces matching " . '"' . $searchfor . '"';
    $self->handle_command('wait_for_text_present_ok',$searchfor,30000);
    if (defined($clickthrough) && ($clickthrough)) {
        $self->handle_command('wait_for_element_visible_ok',"link=$searchfor",30000);
        $self->handle_command('click_and_wait',"link=$searchfor");
        $self->handle_command('wait_for_element_visible_ok','link=Usage Reports',30000);
    }
}

=head2 st_build_cp_name ($email, $variable) 

Transforms matt@foo.com into "matt" <matt@foo.com>

ASSUMES users bestfullname is first half of email.  Avoid periods, dashes, and don't customize first, last, middle, or preferred name, please.

=cut

sub st_build_cp_name { 
    my ($self, $email, $variable) = @_;
    my $full = $email;
    my @arr = split /\@/, $email;
    my $link = '"' . $arr[0] . '"' . ' <' . $email . '>';
    $self->{$variable} = $link;
}

=head2 st_search_cp_users($searchfor)

Control panel (USER) search automation

=cut

sub st_search_cp_users {
    my ($self, $searchfor) = @_;
    $self->handle_command('open_ok', '/nlw/control/user');
    $self->handle_command('wait_for_element_visible_ok','username',30000);
    $self->handle_command('wait_for_element_visible_ok','st-username-search-submit',30000);
    $self->handle_command('type_ok','username',$searchfor);
    $self->handle_command('click_and_wait','st-username-search-submit');
    my $str = "Users matching " . '"' . $searchfor . '"';
    $self->handle_command('wait_for_text_present_ok',$str,30000);
}

=head2 st_search_cp_account($searchfor)

Control panel (Account) search automation

=cut

sub st_search_cp_account {
   my ($self, $searchfor) = @_;
   $self->handle_command('open_ok', '/nlw/control/account');
   $self->handle_command('wait_for_element_visible_ok','st-search-by-name',30000);
   $self->handle_command('wait_for_element_visible_ok','st-submit-search-by-name',30000);
   $self->handle_command('type_ok','st-search-by-name',$searchfor);
   $self->handle_command('click_and_wait','st-submit-search-by-name');
   my $str = "Accounts matching " . '"' . $searchfor . '"';
   $self->handle_command('wait_for_text_present_ok',$str,30000);
}

sub create_account {
    my $self = shift;
    my $name = shift;

    my $acct = create_test_account_bypassing_factory($name);
    my $ws = Socialtext::Workspace->new(name => 'admin');
    $acct->enable_plugin($_) for qw/people dashboard widgets signals groups/;
    if ($ws) {
        $ws->enable_plugin($_) for qw/socialcalc/;
    }
    $self->{account_id} = $acct->account_id;
    diag "Created account $name ($self->{account_id})";
    return $acct;
}

sub dump_vars {
    my $self = shift;
    my %hash;
    for my $key (sort keys %$self) {
        next if ref $self->{$key};
        next unless defined $self->{$key};
        diag "Var '$key': $self->{$key}";
    }
}

sub account_config {
    my $self = shift;
    my $account_name = shift;
    my $key = shift;
    my $val = shift;
    my $acct = Socialtext::Account->new(
        name => $account_name,
    );
    $acct->update($key => $val);
    diag "Set account $account_name config: $key to $val";
}

sub account_plugin_pref {
    my $self = shift;
    my $account_name = shift;
    my $plugin_name = shift;
    my $key = shift;
    my $val = shift;
    my $acct = Socialtext::Account->new(
        name => $account_name,
    );
    my $pt = Socialtext::PrefsTable->new(
        table => 'user_set_plugin_pref',
        identity => {
            plugin => $plugin_name, 
            user_set_id => $acct->user_set_id
        }
    );
    $pt->set($key, $val);
    diag "Set account/plugin pref for plugin $plugin_name / account $account_name - $key to $val";
}

sub get_account_id {
    my ($self, $name, $variable) = @_;
    my $acct = Socialtext::Account->new(name => $name);
    $self->{$variable} = $acct->account_id;
}

sub workspace_config {
    my $self = shift;
    my $ws_name = shift;
    my $key = shift;
    my $val = shift;
    my $ws = Socialtext::Workspace->new(
        name => $ws_name,
    );
    $ws->update($key => $val);
    diag "Set workspace $ws_name config: $key to $val";
}

sub enable_account_plugin {
    my $self = shift;
    my $account_name = shift;
    my $plugin = shift;

    my $acct = Socialtext::Account->new(
        name => $account_name,
    );
    $acct->enable_plugin($plugin);
    diag "Enabled plugin $plugin in account $account_name";
}

sub disable_account_plugin {
    my $self = shift;
    my $account_name = shift;
    my $plugin = shift;

    my $acct = Socialtext::Account->new(
        name => $account_name,
    );
    $acct->disable_plugin($plugin);
    diag "Disabled plugin $plugin in account $account_name";
}

sub create_user {
    my $self = shift;
    my $arg_count = @_;
    my $email = shift;
    my $password = shift;
    my $account = shift;
    my $name = shift || ' ';
    my $username = shift || $email;

    # Special mode that DTRT
    if ($arg_count == 1) {
        $name = $email;
        unless ($email =~ /@/) {
            $email = $name . $self->{start_time} . '@ken.socialtext.net';
        }
        $password = 'password';
        $username = $email;
        $self->{$name} = $email;
    }

    my ($first_name,$last_name) = split(' ',$name,2);
    $first_name ||= '';
    $last_name ||= '';
    
    my $user = Socialtext::User->create(
        email_address => $email,
        username      => $username,
        password      => $password,
        first_name    => $first_name,
        last_name     => $last_name,
        (
            $account
            ? (primary_account_id =>
                    Socialtext::Account->new(name => $account)->account_id())
            : ()
        )
    );
    diag "Created user ".$user->email_address. ", name ".$user->guess_real_name;
    
    $self->{user_id} = $user->user_id;
    $self->{"${name}_id"} = $user->user_id;
    return $user;
}

sub user_primary_account {
    my $self = shift;
    my $username = shift;
    my $account_name = shift;

    my $user = Socialtext::User->Resolve($username);
    my $account = Socialtext::Account->new(name => $account_name);

    $user->primary_account($account);
    diag "Changed ${username}'s primary account to $account_name\n";
}

sub workspace_primary_account {
    my $self = shift;
    my $wksp_name = shift;
    my $acct_name = shift;

    my $wksp = Socialtext::Workspace->new(name => $wksp_name);
    my $account = Socialtext::Account->new(name => $acct_name);

    $wksp->update(account_id => $account->account_id);
    diag "Changed ${wksp_name}'s primary account to $acct_name\n";
}

sub group_primary_account {
    die "XXX THIS IS NOT IMPLEMENTED!";
    # Please update t/wikitests/search/person-index.wiki when you implement this


    my $self = shift;
    my $group_id  = shift || $self->{group_id};
    my $acct_name = shift;

    my $group = Socialtext::Group->GetGroup(group_id => $group_id);
    my $account = Socialtext::Account->new(name => $acct_name);

    $group->update(account_id => $account->account_id);
    diag "Changed ${group_id}'s primary account to $acct_name\n";
}

sub delete_user {
    my $self = shift;
    my $email = shift;
    sql_execute('UPDATE users SET email_address = ? WHERE email_address = ?',
        time() . '@devnull.socialtext.net', $email);
    sql_execute('UPDATE users SET driver_username = ? WHERE driver_username = ?',
        time() . '@devnull.socialtext.net', $email);
}

sub deactivate_user {
    my $self = shift;
    my $email = shift;
    my $user = Socialtext::User->Resolve($email);

    $user->deactivate();
}

sub create_group {
    my $self         = shift;
    my $group_name   = shift;
    my $account_name = shift;
    my $user_name    = shift;
    my $description  = shift;
    my $permission_set = shift;

    my $account = $account_name
        ? Socialtext::Account->new(name => $account_name)
        : Socialtext::Account->Default();

    my $user = $user_name
        ? Socialtext::User->Resolve($user_name)
        : Socialtext::User->SystemUser();

    my $group;
    eval {
        $group = Socialtext::Group->Create({
            driver_group_name  => $group_name,
            primary_account_id => $account->account_id,
            created_by_user_id => $user->user_id,
            description        => $description || 'no description',
            permission_set     => $permission_set || 'private',
        });
    };
    if (my $err = $@) {
        if ($err =~ m/duplicate key value violates/) {
            diag "Group $group_name already exists";
            return;
        }
        die $@;
    }

    # store the "group_id" variable so people can assign it to other vars
    # e.g. | set | my_group_id | %%group_id%% |

    $self->{group_id} = $group->group_id;
    push @{$self->{created_groups}}, $group->group_id;

    diag "Created group $group_name (".$group->driver_unique_id."), ID: $self->{group_id} (use the \%\%group_id\%\% var to access this)" if $group;
    return $group;
}

sub workspace_permission_set {
    my $self = shift;
    my $ws_name = shift;
    my $permission_set = shift;

    my $ws = Socialtext::Workspace->new(name => $ws_name);
    eval { $ws->permissions->set(set_name => $permission_set); };
    if (my $e = $@) {
        die "could not update workspace permissions: $e";
    }

    diag "workspace $ws_name now has set $permission_set";
}

sub group_permission_set {
    my $self     = shift;
    my $group_id = shift;
    my $set_name = shift;

    my $group;
    eval {
        $group = Socialtext::Group->GetGroup({group_id => $group_id});
        $group->update_store({permission_set => $set_name});
    };
    if (my $e = $@) {
        die "couldn't update group permissions: $e";
    }

    diag "Group " . $group->name . " now has $set_name permissions";
}

sub create_multi_groups {
   my ($self, $name, $num) = @_;
   for (my $idx=0; $idx<$num; $idx++) {
       my $fullname = $name . $idx;
       $self->handle_command('create-group',"$fullname");
   }
}

sub get_group_id {
    my ($self, $group_name, $variable) = @_;

    # opportunistic search; presumes that you've got *ONLY* one Group with the
    # given name.
    my ($group) =
        grep { $_->name eq $group_name }
        Socialtext::Group->All->all;
    $self->{$variable} = $group->group_id;
}

sub delete_created_groups {
    my $self = shift;
    $self->handle_command('delete-group', $_) for (@{$self->{created_groups}});
}

sub delete_all_groups {
    my $self = shift;

    my $groups = Socialtext::Group->All(ids_only => 1);
    while (my $g = $groups->next) {
        Test::Socialtext::Group->delete_recklessly($g);
    }
}

sub delete_group {
    my $self     = shift;
    my $group_or_id = shift || $self->{group_id};

    my $group = (ref($group_or_id))
        ? $group_or_id
        : Socialtext::Group->GetGroup(group_id => $group_or_id);

    if ($group) {
        my $group_id = $group->group_id;
        diag "Recklessly deleting group $group_id";

        require Test::Socialtext::Group;
        Test::Socialtext::Group->delete_recklessly($group);
    }
}

sub delete_all_workspaces {
    my $self = shift;

    my $workspaces = Socialtext::Workspace->All();
    while (my $w = $workspaces->next()) {
        $self->delete_workspace($w);
    }
}

sub delete_workspace {
    my $self = shift;
    my $ws_or_id = shift || $self->{workspace_id};

    my $ws = (ref($ws_or_id))
        ? $ws_or_id
        : Socialtext::Workspace->new(
            (($ws_or_id =~ /^\d+$/) ? 'workspace_id' : 'name') => $ws_or_id
        );

    if ($ws) {
        my $ws_id = $ws->workspace_id;
        my $ws_name = $ws->name;
        diag "Recklessly deleting workspace $ws_name (ID: $ws_id)";

        require Test::Socialtext::Workspace;
        Test::Socialtext::Workspace->delete_recklessly($ws);
    }
}

sub add_group_to_workspace {
    my $self      = shift;
    my $group_id  = shift || $self->{group_id};
    my $ws_name   = shift;
    my $role_name = shift || '';

    my $ws    = Socialtext::Workspace->new(name      => $ws_name);
    my $group = Socialtext::Group->GetGroup(group_id => $group_id);

    my $role = $role_name
        ? Socialtext::Role->new(name => $role_name)
        : undef;

    $ws->assign_role_to_group( group => $group, role => $role );

    diag 'Added ' . $group->driver_group_name . ' Group'
       . " to $ws_name WS"
       . ' with ' . $role_name . ' Role';
}

sub remove_group_from_workspace {
    my $self     = shift;
    my $group_id = shift || $self->{group_id};
    my $ws_name  = shift;

    my $ws    = Socialtext::Workspace->new(name      => $ws_name);
    my $group = Socialtext::Group->GetGroup(group_id => $group_id);

    $ws->remove_group( group => $group );
    diag "Removed group $group_id from $ws_name";
}

sub add_account_to_workspace {
    my $self      = shift;
    my $acct_name = shift || $self->{account};
    my $ws_name   = shift;

    my $ws   = Socialtext::Workspace->new(name => $ws_name);
    my $acct = Socialtext::Account->new(name   => $acct_name);

    $ws->assign_role_to_account( account => $acct );

    diag 'Added ' . $acct->name . ' Account'
       . " to $ws_name WS";
}

sub add_group_to_account {
    my $self         = shift;
    my $group_id     = shift || $self->{group_id};
    my $account_name = shift;
    my $role_name    = shift || '';

    my $group   = Socialtext::Group->GetGroup(group_id => $group_id);
    my $account = Socialtext::Account->new(name        => $account_name);

    my $role = $role_name
        ? Socialtext::Role->new(name => $role_name)
        : undef;

    $account->assign_role_to_group(group => $group, role => $role);

    diag 'Added ' . $group->driver_group_name . ' Group'
       . " to $account_name Account"
       . ' with ' . $role_name . ' Role';
}

sub remove_group_from_account {
    my $self         = shift;
    my $group_id     = shift || $self->{group_id};
    my $account_name = shift;

    my $group   = Socialtext::Group->GetGroup(group_id => $group_id);
    my $account = Socialtext::Account->new(name        => $account_name);
    my $old_role = $account->remove_group(group => $group);

    diag "Removed $group_id from $account_name (had role ".$old_role->name.")";
}

sub add_user_to_group {
    my $self      = shift;
    my $user_name = shift;
    my $group_id  = shift || $self->{group_id};
    my $role_name = shift || '';
    my $actor_name = shift || Socialtext::User->SystemUser->user_id;

    my $group = Socialtext::Group->GetGroup(group_id => $group_id);
    my $user  = Socialtext::User->Resolve($user_name);
    my $actor = Socialtext::User->Resolve($actor_name);

    my $role = $role_name
        ? Socialtext::Role->new(name => $role_name)
        : undef;

    $group->assign_role_to_user( user => $user, role => $role, actor => $actor );

    diag "Added User $user_name"
       . ' to ' . $group->driver_group_name . ' Group'
       . ' with ' . $role_name . ' Role';
}

sub remove_user_from_group {
    my $self      = shift;
    my $user_name = shift;
    my $group_id  = shift || $self->{group_id};

    my $group = Socialtext::Group->GetGroup(group_id => $group_id);
    my $user  = Socialtext::User->Resolve($user_name);
    $group->remove_user(user => $user);
    diag "Remove user $user_name from group $group_id";
}

sub add_user_to_account {
    my $self      = shift;
    my $user_name = shift;
    my $account  = shift;
    my $role_name = shift || '';

    my $user  = Socialtext::User->Resolve($user_name);
    my $acct = Socialtext::Account->new(name => $account);

    my $role = $role_name
        ? Socialtext::Role->new(name => $role_name)
        : undef;

    $acct->assign_role_to_user( user => $user, role => $role );

    diag "Added User $user_name"
       . ' to ' . $acct->name . ' Account'
       . ' with ' . $role_name . ' Role';
}

sub remove_user_from_account {
    my $self      = shift;
    my $user_name = shift;
    my $account   = shift;

    my $user  = Socialtext::User->Resolve($user_name);
    my $acct = Socialtext::Account->new(name => $account);
    $acct->remove_user(user => $user);
    diag "Remove user $user_name from account $account";
}

sub create_workspace {
    my $self      = shift;
    my $name      = shift;
    my $acct_name = shift;
    my $title     = shift;
    my $allusers  = shift;

    if (!defined($title) || length($title)<2) {
       $title = $name;
    }
  
    my $ws = Socialtext::Workspace->new(name => $name, title => $title);
    if ($ws) {
        diag "Workspace $name already exists";
        return
    }


    my $account = $acct_name
        ? Socialtext::Account->new(name => $acct_name)
        : Socialtext::Account->Default;

    $ws = Socialtext::Workspace->create(
        name => $name, title => $title,
        account_id => $account->account_id(),
        skip_default_pages => 1,
    );

    $ws->assign_role_to_account(account => $account) if ($allusers);

    $ws->enable_plugin($_) for qw/socialcalc/;
    $self->{workspace_id} = $ws->workspace_id;
    diag "Created workspace $name";
    return $ws;
}


sub purge_workspace {
    my $self = shift;
    my $name = shift;
    my $del_users = shift;
    $del_users = 1 unless defined($del_users);

    my $ws = Socialtext::Workspace->new(name => $name);
    unless ($ws) {
        die "Workspace $name doesn't already exist";
    }

    if ($del_users) {
        my $users = $ws->users;
        while (my $user = $users->next) {
            sql_execute('DELETE FROM users WHERE user_id = ? CASCADE',
                $user->user_id);
        }
        $ws->delete();
        diag "Workspace $name was purged, along with all users in that workspace.";
    } else {
        $ws->delete();
        diag "Workspace $name was purged";
    };


}

sub set_ws_permissions {
    my $self       = shift;
    my $workspace  = shift;
    my $permission = shift;

    my $ws = Socialtext::Workspace->new(name => $workspace);
    die "No such workspace $workspace" unless $ws;
    $ws->permissions->set( set_name => $permission );
    diag "Set workspace $workspace permission to $permission";
}

sub set_workspace_id {
    my $self      = shift;
    my $var       = shift;
    my $workspace = shift;

    my $ws = Socialtext::Workspace->new(name => $workspace);
    die "No such workspace $workspace" unless $ws;
    $self->{$var} = $ws->workspace_id;
    diag "Set variable '$var' to $workspace id: $self->{$var}";
}

sub set_group_id {
    my $self       = shift;
    my $var        = shift;
    my $group_name = shift;

    my $sth = sql_execute(q{
        SELECT group_id FROM groups WHERE driver_key = 'Default' AND driver_group_name = ?
    }, $group_name);

    if ($sth->rows == 0) {
        die "no group '$group_name' found";
    }
    elsif ($sth->rows > 1) {
        die "ambiguous group name '$group_name': ".
            "found ".$sth->rows." groups with that name";
    }
    my ($group_id) = $sth->fetchrow_array;

    $self->{$var} = $group_id;
    diag "Set variable '$var' to group id: $self->{$var}";
}

sub add_member {
    my $self = shift;
    my $email = shift;
    my $workspace = shift;
    my $role_name = shift;

    my $ws = Socialtext::Workspace->new(name => $workspace);
    die "No such workspace $workspace" unless $ws;
    my $user = Socialtext::User->Resolve($email);
    die "No such user $email" unless $user;

    my $role = Socialtext::Role->new(name => $role_name || 'member');
    $ws->assign_role_to_user( user => $user, role => $role );
    diag "Added user $email to $workspace with role " . $role->name;
}

sub remove_member {
    my $self = shift;
    my $email = shift;
    my $workspace = shift;

    my $ws = Socialtext::Workspace->new(name => $workspace);
    die "No such workspace $workspace" unless $ws;
    my $user = Socialtext::User->Resolve($email);
    die "No such user $email" unless $user;

    $ws->remove_user(user => $user);
    diag "Removed user $email from $workspace";
}

sub add_workspace_admin {
    my $self = shift;
    my $email = shift;
    my $workspace = shift;

    my $ws = Socialtext::Workspace->new(name => $workspace);
    die "No such workspace $workspace" unless $ws;
    my $user = Socialtext::User->Resolve($email);
    die "No such user $email" unless $user;

    $ws->assign_role_to_user(
        user => $user,
        role => Socialtext::Role->Admin(),
    );
    diag "Added user $email to $workspace as admin";
}

sub set_business_admin {
    my $self = shift;
    my $email = shift;
    my $value = shift;
    $value = 1 unless defined $value;

    my $user = Socialtext::User->Resolve($email);
    die "No such user $email" unless $user;

    $user->set_business_admin($value);
    diag "Set user $email is_business_admin to '$value'";
}

sub set_technical_admin {
    my $self = shift;
    my $email = shift;
    my $value = shift;

    my $user = Socialtext::User->Resolve($email);
    die "No such user $email" unless $user;

    $user->set_technical_admin($value);
    diag "Set user $email is_technical_admin to '$value'";
}

sub set_json_from_perl {
    my ($self, $name, $value) = @_;
    $self->{$name} = encode_json(eval $value);
    diag "Set $name to $self->{$name}";
}

sub set_json_from_string {
    my ($self, $name, $value) = @_;
    $self->{$name} = encode_json($value);
    diag "Set $name to $self->{$name}";
}

sub set_uri_escaped {
    my ($self, $name, $value) = @_;
    $self->{$name} = uri_escape($value);
    diag "Set $name to $self->{$name}";
}

sub set_user_id {
    my $self = shift;
    my $var_name = shift;
    my $email = shift;

    my $user = Socialtext::User->Resolve($email);
    die "No such user $email" unless $user;
    $self->{$var_name} = $user->user_id;
    diag "Set variable $var_name to $self->{$var_name}";
}

sub set_user_bfn {
    my $self = shift;
    my $var_name = shift;
    my $email = shift;

    my $user = Socialtext::User->Resolve($email);
    die "No such user $email" unless $user;
    $self->{$var_name} = $user->best_full_name;
    diag "Set variable $var_name to $self->{$var_name}";
}

sub set_account_id {
    my $self = shift;
    my $var_name = shift;
    my $acct_name = shift;

    Socialtext::Cache->clear('account');

    my $acct = Socialtext::Account->new(name => $acct_name);
    die "No such user $acct_name" unless $acct;
    $self->{$var_name} = $acct->account_id;
    diag "Set variable $var_name to $self->{$var_name}";
}

sub set_gadget_id {
    my $self     = shift;
    my $var_name = shift;
    my $src      = shift;
    $self->{$var_name} = sql_singlevalue(
        'SELECT gadget_id FROM gadget WHERE src = ?', $src
    );
    diag "Set variable $var_name to $self->{$var_name}";
}

sub set_latest_gadget_instance_id {
    my $self = shift;
    my $var_name = shift;
    $self->{$var_name} = sql_singlevalue(
        'SELECT MAX(gadget_instance_id) FROM gadget_instance'
    );
    diag "Set variable $var_name to $self->{$var_name}";
}

=head2 set_regex_escape( $varname, $value )

Takes a value and places a regex-escaped value in a variable that should be used
for the value of a *like command.

This is convenient when you are constructing a string with / that needs escaping
(the / needs escaping inside or outside of a qr//) for use with *like commands

=cut
sub set_regex_escaped {
    my $self = shift;
    my $var_name = shift;
    my $value = shift;

    #$value =~ s/\//\\\//;
    $self->{$var_name} = "\Q$value\E";
}

sub exec_regex {
    my $self = shift;
    my $name = shift;
    my $content = shift;
    my $regex = $self->quote_as_regex(shift || '');
    if ($content =~ $regex) {
        if (defined $1) {
            $self->{$name} = $1;
            diag "# Set $name to '$1' from response content\n";
        }
        else {
            die "Could not set $name - regex didn't capture!";
        }
    }
    else {
        die "Could not set $name - regex ($regex) did not match $content";
    }

}

sub sleep {
    my $self = shift;
    my $secs = shift;
    CORE::sleep $secs;
}

=head2 get ( uri, accept )

GET a URI, with the specified accept type.

accept defaults to 'text/html'.

=cut

sub get {
    my ($self, $uri, $accept, $headers) = @_;
    $accept ||= 'text/html';

    my @headers = (
        Accept => $accept,
        $self->{_cookie} ? (Cookie => $self->{_cookie}) : (),
    );
    if ($headers) {
        push @headers, map { split m/\s*=\s*/ } split m/\s*,\s*/, $headers;
    }
    $self->_get($uri, \@headers);
}

=head2 cond_get ( uri, accept, ims, inm )

GET a URI, specifying Accept, If-Modified-Since and If-None-Match headers.

Accept defaults to text/html.

The IMS and INS headers aren't sent unless specified and non-zero.

=cut

sub cond_get {
    my ($self, $uri, $accept, $ims, $inm) = @_;
    $accept ||= 'text/html';
    my @headers = ( Accept => $accept );
    push @headers, 'If-Modified-Since', $ims if $ims;
    push @headers, 'If-None-Match', $inm if $inm;
    push @headers, Cookie => $self->{_cookie} if $self->{_cookie};

    diag "Calling get on $uri";
    my $start = time();
    $self->{http}->get($self->{browser_url} . $uri, \@headers);
    $self->{_last_http_time} = time() - $start;
}

sub was_faster_than {
    my ($self, $secs) = @_;

    my $elapsed = delete $self->{_last_http_time} || -1;
    cmp_ok $elapsed, '<=', $secs, "timer was faster than $secs";
}

=head2 delete ( uri, accept )

DELETE a URI, with the specified accept type.

accept defaults to 'text/html'.

=cut

sub delete {
    my ($self, $uri, $accept) = @_;
    $accept ||= 'text/html';

    $self->_call_method('delete', $uri, [Accept => $accept]);
}


=head2 code_is( code [, expected_message])

Check that the return code is correct.

=cut

sub code_is {
    my ($self, $code, $msg) = @_;
    my $http = $self->{http};
    my $resp = $http->response;
    $http->status_code_is($code);
    if ($resp->code != $code) {
        diag "Response message: " . ($resp->message || 'None') ."\n";
        diag "Content: " . (substr($resp->content,0,256) || 'No content') . "\n"
            unless $resp->code == 200;
        diag "url(" . $http->request->url . ")\n";
    }
    if ($msg) {
        like $self->{http}->response->content(), $self->quote_as_regex($msg),
             "Status content matches";
    }
    return $code;
}

=head2 code_like( code [, expected_message])

Check that the return code is correct.

=cut

sub code_like {
    my ($self, $regex) = @_;
    $regex = $self->quote_as_regex($regex);
    my $http = $self->{http};
    my $resp = $http->response;
    if ($resp->code =~ $regex) {
        pass "code is " . $resp->code;
    }
    else {
        diag "Response message: " . ($resp->message || 'None') ."\n";
        diag "Content: " . (substr($resp->content,0,256) || 'No content') . "\n"
            unless $resp->code == 200;
        diag "url(" . $http->request->url . ")\n";
    }
}

=head2 dump_http_response 

Dump the headers of the last http response.

=cut

sub dump_http_response {
    my $self = shift;
    my $content = $self->{http}->response->content;
    $self->{http}->response->content("Content removed");
    diag $self->{http}->response->as_string;
    $self->{http}->response->content($content);
}

=head2 dump_json

Decode the last response as JSON, produce Data::Dumper diag output.

=cut

sub dump_json {
    my $self = shift;
    my $json = $self->{http}->_decoded_content;
    $json =~ s/^throw 1; < don't be evil' >\s*//ms;
    my $blob = decode_json_utf8($json);
    diag(Dumper($blob));
}

=head2 has_header( header [, expected_value])

Check that the specified header is in the response, with an optional second check for the header's value.

=cut

sub has_header {
    my ($self, $header, $value) = @_;
    my $hval = $self->{http}->response->header($header);
    ok $hval, "header $header is defined";
    if ($value) {
        like $hval, $self->quote_as_regex($value), "header content matches";
    }
}

=head2 post( uri, headers, body )

Post to the specified URI

=cut

sub post { shift->_call_method('post', @_) }

=head2 post_json( uri, body )

Post to the specified URI with header 'Content-Type=application/json'

=cut

sub post_json {
    my $self = shift;
    my $uri = shift;
    $self->post($uri, 'Content-Type=application/json', @_);
}

=head2 get_json( uri )

GET the specified URI with header 'Content-Type=application/json'

=cut

sub get_json {
    my $self = shift;
    my $uri = shift;
    $self->get($uri, 'application/json');
}

=head2 post_form( uri, body )

Post to the specified URI with header 'Content-Type=application/x-www-form-urlencoded'

=cut

sub post_form {
    my $self = shift;
    my $uri = shift;
    $self->post($uri, 'Content-Type=application/x-www-form-urlencoded', @_);
}

=head2 put_form( uri, body )

Post to the specified URI with header 'Content-Type=application/x-www-form-urlencoded'

=cut

sub put_form {
    my $self = shift;
    my $uri = shift;
    $self->put($uri, 'Content-Type=application/x-www-form-urlencoded', @_);
}

=head2 put_wikitext( uri, body )

Post to the specified URI with header 'Content-type=text/x.socialtext-wiki'

=cut

sub put_wikitext {
    my $self = shift;
    my $uri = shift;
    $self->put($uri, 'Content-type=text/x.socialtext-wiki', @_);
}

=head2 post_file( uri, post_vars, filename_var filename )

Post a local file to the specified URI

    | post-file | other_var=1&something_else=1 | file | bob.txt |

=cut

sub post_file {
    my $self = shift;
    my $uri = shift;
    my $vars = shift;
    my $filename_var = shift;
    my $filename = shift;

    my @vars = map { /^(.*)=(.*)$/ } split /;&/, $vars;
    push @vars, ($filename_var, [$filename]);

    my $ua = LWP::UserAgent->new;
    my $req = POST $self->{browser_url} . $uri,
        Content_Type => 'multipart/form-data',
        Content => \@vars;
    $req->authorization_basic($self->{http_username}, $self->{http_password});
    my $start = time();
    my $res = $ua->request($req);
    $self->{http}->response($res);
    $self->{_last_http_time} = time() - $start;
}

=head2 upload_file( filename )

Post a local file to the specified URI, DWIMy

    | upload-file | bob.txt |
    | set | your_var | %%upload_id%% |

To check for a 413 Request Entity Too Large error:

    | upload-file | huge.dat | fail-413 |

=cut

sub upload_file {
    my $self = shift;
    my $filename = shift;
    my $opt = shift || '';
    $self->post_file('/data/uploads', 'method=file', 'file', $filename);
    if ($opt eq 'fail-413') {
        $self->code_is(413);
        $self->body_like(q{nginx}, "nginx blocked the upload");
    }
    else {
        $self->code_is(201);
        $self->body_like(q{"status":"success"});
        $self->set_from_content('upload_id', 'qr/"id":"([^"]+)"/');
        diag "Uploaded $filename, got id $self->{upload_id}";
    }
}

=head2 generate_large_file( kb )

Make a large file full of nul-bytes.  Sets the large_filename variable.  File
is deleted during global destruction (of Perl).

    | generate-large-file | 1024 |
    | set | one_mb_filename | %%large_filename%% |

=cut

our @generated_temp_files;
sub generate_large_file {
    my ($self, $size_in_kb) = @_;

    die "size must be in kb" if ($size_in_kb =~ /\D/);

    my $tmp = File::Temp->new(UNLINK => 1);
    my $filename = $tmp->filename;
    $tmp->close;
    my $rc = system("dd if=/dev/zero of=$filename bs=1024 count=$size_in_kb");
    is $rc, 0, "created large file $filename";
    $self->{large_filename} = $filename;
    push @generated_temp_files, $tmp;
}

=head2 put( uri, headers, body )

Put to the specified URI

=cut

sub put { shift->_call_method('put', @_) }

=head2 put_json( uri, json )

Put json to the specified URI

=cut

sub put_json {
    my $self = shift;
    my $uri = shift;
    $self->put($uri, 'Content-Type=application/json', @_);
}

=head2 put_sheet( uri, sheet_filename )

Put the contents of the specified file to the URI as a spreadsheet.

=cut

sub put_sheet {
    my $self     = shift;
    my $uri      = shift;
    my $filename = shift;

    my $dir = $self->_relative_filename_to_absolute("t/wikitests/test-data/socialcalc");
    my $file = "$dir/$filename";
    die "Can't find spreadsheet at $file" unless -e $file;
    my $content = Socialtext::File::get_contents($file);
    my $json = encode_json({
        content => $content,
        type => 'spreadsheet',
    });

    $self->put($uri, 'Content-Type=application/json', $json);
}

=head2 put_sheet_csv( uri, sheet_filename )

Put the contents of the specified file to the URI as a spreadsheet using CSV.

=cut

sub put_sheet_csv {
    my $self     = shift;
    my $uri      = shift;
    my $filename = shift;

    my $dir = $self->_relative_filename_to_absolute("t/wikitests/test-data/socialcalc");
    my $file = "$dir/$filename";
    die "Can't find spreadsheet at $file" unless -e $file;
    my $content = Socialtext::File::get_contents($file);
    $self->put($uri, 'Content-Type=text/csv', $content);
}

=head2 set_http_keepalive ( on_off )

Enables/disables support for HTTP "Keep-Alive" connections (defaulting to I<off>).

When called, this method re-instantiates the C<Test::HTTP> object
that is being used for testing; be aware of this when writing your tests.

=cut

sub set_http_keepalive {
    my $self   = shift;
    my $on_off = shift;

    # switch User-Agent classes
    $Test::HTTP::UaClass = $on_off
        ? 'Test::LWP::UserAgent::keep_alive' : 'LWP::UserAgent';

    # re-instantiate our Test::HTTP object
    delete $self->{http};
    $self->http_user_pass($self->{http_username}, $self->{http_password});
}

=head2 set_user_agent ( $ua_string )

=cut

sub set_user_agent {
    my $self = shift;
    my $ua_string = shift;
    $self->{http}->ua->agent($ua_string);
    diag "Set UserAgent string to '$ua_string'";
}

=head2 set_from_content ( name, regex )

Set a variable from content in the last response.

=cut

sub set_from_content {
    my $self = shift;
    my $name = shift || die "name is mandatory for set-from-content";
    my $regex = shift;
    $self->exec_regex($name, $self->{http}->response->content, $regex);
}

=head2 set_from_header ( name, header )

Set a variable from a header in the last response.

=cut

sub set_from_header {
    my $self = shift;
    my $name = shift || die "name is mandatory for set-from-header";
    my $header = shift || die "header is mandatory for set-from-header";
    my $regex = shift;
    my $content = $self->{http}->response->header($header);

    if ($header eq 'Location') {
        $content =~ s#^\w+://[^/]+##;
    }

    if (defined $content) {
        if (defined $regex) {
            $self->exec_regex($name, $content, $regex);
        }
        else {
            $self->{$name} = $content;
        }
        pass "Set $name to '$self->{$name}' from response header\n";
    }
    else {
        fail "Could not set $name - header $header not present\n";
        $self->{$name} = '';
    }
}

=head2 st_clear_cache

Clears the server cache for the widgets

=cut

sub set_date_from_interval {
    my $self = shift;
    my $name = shift;
    my $interval = shift;
    my $tz = DateTime::TimeZone->new( name => 'local' );
    my $dt = DateTime->now(time_zone => $tz);

    if ($interval) {
        my $do = $interval =~ s/^\-// ? 'subtract' : 'add';
        
        $interval =~ /^(\d+)(.+)$/ or die "invalid interval";
        my ($val,$units) = ($1,$2);
        $units .= $units =~ /s$/ ? '' : 's'; # make sure units is plural

        $dt->$do($units => $val);
    }

    $self->{$name} = $dt->mdy('-');
}

=head2 set_date_from_interval (name, interval)

Set a data variable. The value is based on an interval from now.

| set-date-from-interval | tomorrow  | 1day   |
| set-date-from-interval | last_week | -1week |

=cut

sub st_clear_json_cache {
    _run_command("st-purge-json-proxy-cache",'ignore output');
}

=head2 st-clear-events

Delete all events

=cut

sub st_clear_events {
    sql_execute('TRUNCATE event, event_page_contrib, event_archive');
}

=head2 st-clear-webhooks

Delete all webhooks.

=cut

sub st_clear_webhooks {
    sql_execute('DELETE FROM webhook');
}

=head2 st-clear-log

Clear any log lines.

=cut

sub st_clear_log {
    my $self = shift;
    $self->{_log} = '';
    my $lr = $self->_logreader;
    while ($lr->read_line) {}
}

sub _logreader {
    my $self = shift;
    return $self->{_logreader} ||= File::LogReader->new(
        filename  => "$ENV{HOME}/.nlw/log/nlw.log",
        state_dir => "$ENV{HOME}/.nlw/wikitest-logreader.state",
    );
}

sub _log_test {
    my $self = shift;
    my $cmd = shift;
    my $expected = shift;

    $self->{_log} ||= '';
    my $lr = $self->_logreader;
    while(my $line = $lr->read_line) {
        $self->{_log} .= "$line\n";
    }

    no strict 'refs';
    $cmd->($self->{_log}, qr/$expected/, $cmd);
}

=head2 log-like

Checks that the nlw.log matches your expected output.

=cut

sub log_like {
    my $self = shift;
    $self->_log_test('like', @_);
}

=head2 log-unlike

Checks that the nlw.log doesn't match your regexp.

=cut

sub log_unlike {
    my $self = shift;
    $self->_log_test('unlike', @_);
}

=head2 st-clear-signals

Delete all signals

=cut

sub st_clear_signals {
    sql_execute("DELETE FROM signal");
}


=head2 st-delete-people-tags

Delete all people tags.

=cut

sub st_delete_people_tags {
    sql_execute('DELETE FROM tag_people__person_tags');
    sql_execute('DELETE FROM person_tag');
}

=head2 json-parse

Try to parse the body as JSON, remembering the result for additional tests.

=cut

sub json_parse {
    my $self = shift;
    $self->{json} = undef;
    my $content = $self->{http}->_decoded_content || '';
    $content =~ s/^throw 1; < don't be evil' >\s*//ms;
    $self->{json} = eval { decode_json_utf8($content) };
    ok !$@ && defined $self->{json} && ref($self->{json}) =~ /^ARRAY|HASH$/,
        $self->{http}->name . " parsed content" . ($@ ? " \$\@=$@" : "");
    unless (defined $self->{json}) {
        diag "Bad content: '$content'\n";
    }
}

=head2 json-response-is

A macro for C<json-parse> C<code-is> and an optional C<json-array-size>.

E.g. to check for a 200 response with 50 elements in an array:

   | GET-json         | /data/foo |    |
   | json-response-is | 200       | 50 |

... is equivalent to ...

   | GET-json        | /data/foo |
   | code-is         | 200       |
   | json-parse      |           |
   | json-array-size | 50        |

E.g. to check for a 201 response without a number-of-elements check:

   | POST-json        | /data/bar | {"blah":"blah"} |
   | json-response-is | 201       |                 |

... is equivalent to ...

   | POST-json  | /data/bar | {"blah":"blah"} |
   | code-is    | 201       |                 |
   | json-parse |           |                 |

If the "expected code" param is missing, it defaults to 200.  If the response
code doesn't match the expected code, instead of parsing an empty json object
or array is substituted.

=cut

sub json_response_is {
    my ($self,$expected_code,$expected_array_size) = @_;
    $expected_code ||= 200;
    my $code = $self->code_is($expected_code);
    if ($code == $expected_code) {
        $self->json_parse;
    }
    else {
        $self->{json} = defined($expected_array_size) ? [] : {};
    }
    $self->json_array_size($expected_array_size)
        if defined $expected_array_size;
}

=head2 json-proxy-response-is

Lise json-response-is, but for json-proxy requests.

| json-proxy-response-is | GET | JSON | http://ok.com | numEntries=1 | 200 |

This will fetch data from ok.com using the JSON proxy. Since we are proxying
JSON data, the JSON data in body will end up being accessible to json-path-*
commands after the status is checked to match the value passed as $status.

=cut

sub json_proxy_response_is {
    my ($self, $method, $type, $url, $opts, $status) = @_;
    $self->{json} = undef;

    my $proxy_url = "/nlw/json-proxy?url=" . uri_escape($url);
    $proxy_url .= "&httpMethod=$method&contentType=$type";
    $proxy_url .= '&' . $opts if $opts;

    $self->get_json($proxy_url);
    $self->code_is(200);
    $self->json_parse;

    $self->{json} = $self->{json}{$url};

    $self->json_path_is('$.rc', $status);

    # If we're fetching JSON, parse the json body
    $self->json_path_parse('$.body') if $type eq 'JSON' or $type eq 'FEED';
}

=head2 json-like

Confirm that the resulting body is a JSON object which is like (ignoring order
for arrays/dicts) the value given.

The comparison is as follows between the 'candidate' given as a param in the
wikitest, and the value object derived from decoding hte json object from the
wikitest.  this is performed recursively): 1) if the value object is a scalar,
perform comparison with candidate (both must be scalars), 2) if the object is
an array, then for each object in the candidate, ensure the object in the is a
dictionary, then for each key in the candidate object, ensure that the same
key exists in the value object and that it maps to a value that is equivalent
to the value mapped to in the candidate object.

*WARNING* - Right now, this is stupid about JSON numbers as strings v.
numbers. That is, the values "3" and 3 are considered equivalent (e.g.
{"foo":3} and {"foo":"3"} are considered equivalent - this is a known bug in
this fixture)

=head2 json-unlike

C<json-like> with negated result.

=cut


sub json_unlike {
    my $self = shift;
    my $candidate = shift;
    return $self->_json_test(unlike => $candidate);
}

sub json_like {
    my $self = shift;
    my $candidate = shift;
    return $self->_json_test(like => $candidate);
}

sub _json_test {
    my $self = shift;
    my $cmd = shift;
    my $candidate = shift;

    my $json = $self->{json};

    if (not defined $json ) {
        fail $self->{http}->name . " no json result";
    }
    my $parsed_candidate = eval { decode_json_utf8($candidate) };
    if ($@ || ! defined $parsed_candidate || ref($parsed_candidate) !~ /^|ARRAY|HASH|SCALAR$/)  {
        fail $self->{http}->name . " failed to find or parse candidate " . ($@ ? " \$\@=$@" : "");
        return;
    }

    my $result=0;
    $result = eval {$self->_compare_json($parsed_candidate, $json)};

    if ($cmd eq 'unlike') {
        $result = !$result;
        undef $@;
    }

    my $e = $@;
    ok !$e && $result,
    $self->{http}->name . " compared content and candidate ($cmd)";
    unless (!$e && $result) {
        diag "Failure:   $e";
        diag "Candidate: $candidate\n";
        diag "Got:       ".encode_json($json)."\n";
    }
}

sub _compare_json {
    my $self = shift;
    my $candidate = shift;
    my $json = shift;


    die "Candidate is undefined" unless defined $candidate;
    die "JSON is undefined" unless defined $json;
    if (ref($json) eq 'SCALAR' || ref($json) eq '') {
        die "Types of json and candidate disagree"
            unless (ref($json) eq ref($candidate));
        die "No match for candidate $candidate, got $json" unless ($json eq $candidate);
    }
    elsif (ref($json) eq 'JSON::XS::Boolean') {
        die "Types of json and candidate disagree"
            unless (ref($json) eq ref($candidate));
        die "No match for candidate $candidate, got $json" unless ($json == $candidate);
    }
    elsif (ref($json) eq 'ARRAY') {
        my $match = 1;
        die "Expecting array" unless ref ($candidate) eq 'ARRAY';
        for my $candobj (@$candidate) {
            my $exists = 0;
            for my $gotobj (@$json) {
                $exists ||= eval {$self->_compare_json($candobj, $gotobj)};
            }
            $match &&= $exists;
        }
        die "No match for array candidates" unless $match;
    }
    elsif (ref($json) eq 'HASH') {
        die  "Expecting hash" unless ref($candidate) eq 'HASH';
        my $match = 1;
        for my $key (keys %$candidate) {
            die "Can't find value for key '$key' in JSON" unless defined($json->{$key});
            $match &&= $self->_compare_json($candidate->{$key}, $json->{$key});
        }
        die "No match for hash candidates" unless $match;
    }
}

=head2 json-array-size

Confirm that the resulting body is a JSON array of length X.

=cut

sub json_array_size {
    my $self = shift;
    my $comparator = shift;
    my $size = shift;

    if (!defined($size) or $size eq '') {
        $size = $comparator;
        $comparator = '==';
    }

    my $json = $self->{json};
    if (not defined $json ) {
        fail $self->{http}->name . " no json result";
    }
    elsif (ref($json) ne 'ARRAY') {
        fail $self->{http}->name . " json result is not an array";
    }
    else {
        my $count = @$json;
        cmp_ok $count, $comparator, $size,
            $self->{http}->name . " array is $comparator $size" ;
        if ($comparator eq '==' and $count != $size) {
            use YAML ();
            use Clone ();
            diag YAML::Dump([map { my $x = Clone::clone($_); delete $x->{html}; $x } @$json]);
        }
    }
}

sub _call_method {
    my ($self, $method, $uri, $headers, $body) = @_;
    if ($headers) {
        $headers = [
            map {
                my ($k,$v) = split m/\s*=\s*/, $_;
                $k =~ s/-/_/g;
                ($k,$v);
            } split m/\s*,\s*/, $headers
        ];
    }
    $headers ||= [];
    push @$headers, Cookie => $self->{_cookie} if $self->{_cookie};

    # nginx requires a C-L header for PUTs
    if ($method eq 'put') {
        my $cl = 0;
        if (defined($body) && length($body)) {
            use bytes;
            $cl = length($body); # bytes::length, hack for utf-8
        }
        push @$headers, 'Content-Length' => $cl;
    }

    my $start = time();
    if ($uri !~ m#^http://localhost:\d+#) {
        $uri = $self->{browser_url} . $uri;
    }
    $self->{http}->$method($uri, $headers, $body);
    $self->{_last_http_time} = time() - $start;
}

sub _get {
    my ($self, $uri, $opts) = @_;
    my $start = time();
    $uri = "$self->{browser_url}$uri" if $uri =~ m#^/#;
    diag "GET: $uri\n";
    $self->{http}->get( $uri, $opts );
    $self->{_last_http_time} = time() - $start;
}

sub edit_page {
    my $self = shift;
    my $workspace = shift;
    my $page_name = shift;
    my $content = shift;
    my @tags = split qr/\s*,\s*/, shift(@_) || '';

    Encode::_utf8_on($content);
    my $blob = {
        content => $content,
        from => $self->{http_username},
        tags => \@tags,
    };
    $self->put("/data/workspaces/$workspace/pages/$page_name",
        'Accept=text/html,Content-Type=application/json',
        encode_json($blob),
    );
    my $code = $self->{http}->response->code;
    my $success = $code == 201 || $code == 204;
    ok( $success, "Edited $workspace/$page_name");

    if ($success) {
        diag "Edited page $workspace/[$page_name]";
    }
    else {
        diag "Failed to edit page $workspace/[$page_name]";
    }
}

sub watch_page {
    my $self = shift;
    my $workspace = shift;
    my $page_name = shift;

    $self->get("/$workspace/?action=add_to_watchlist;page=$page_name");
    my $code = $self->{http}->response->code;
    ok( $code == 200, "Watched $workspace/$page_name" );
}

sub unwatch_page {
    my $self = shift;
    my $workspace = shift;
    my $page_name = shift;

    $self->get("/$workspace/?action=remove_from_watchlist;page=$page_name");
    my $code = $self->{http}->response->code;
    ok( $code == 200, "Stopped watching $workspace/$page_name" );
}

sub tag_page {
    my $self = shift;
    my $workspace = shift;
    my $page_name = shift;
    my @tags = split qr/\s*,\s*/, shift(@_) || '';

    for my $t (@tags) {
        $self->put("/data/workspaces/$workspace/pages/$page_name/tags/$t");
        $self->code_is(201);
    }
}

sub untag_page {
    my $self = shift;
    my $workspace = shift;
    my $page_name = shift;
    my @tags = split qr/\s*,\s*/, shift(@_) || '';

    for my $t (@tags) {
        $self->delete("/data/workspaces/$workspace/pages/$page_name/tags/$t");
        $self->code_is(204);
    }
}

sub delete_page {
    my $self = shift;
    my $workspace = shift;
    my $page_name = shift;
    $self->delete("/data/workspaces/$workspace/pages/$page_name");
    my $code = $self->{http}->response->code;
    ok( $code == 204, "Deleted $workspace/$page_name" );
}

sub comment_page {
    my $self = shift;
    my $workspace = shift;
    my $page_name = shift;
    my $content = shift;
    $self->post("/data/workspaces/$workspace/pages/$page_name/comments",
        'Accept=text/html,Content-Type=text/x.socialtext-wiki',
        $content,
    );
    my $code = $self->{http}->response->code;
    ok( (($code == 201) or ($code == 204)), "Code is $code");
    diag "Commented page [$page_name]/$workspace";
}

sub post_signal {
    my $self = shift;
    my $content = shift;
    my $extra = shift;

    my $blob;
    if (defined $extra) {
        $blob = decode_json($extra);
    }
    else {
        $blob = {
            all_accounts => 1, 
        };
    }

    $blob->{signal} = $content;
    $self->post_json('/data/signals', encode_json( $blob ));
    $self->code_is(201);
    $self->{last_signal_id} = $self->{http}->response->header('X-Signal-ID');
    diag "Posted signal '$blob->{signal}' (id $self->{last_signal_id})";
}

sub send_signal {
    my $self = shift;
    my $content = shift;
    my %opts = @_;

    require Socialtext::Signal;

    # Find our user_id if it isn't set
    my $user_id = $self->{user_id}
        || Socialtext::User->new(username => $self->{username})->user_id;

    my $signal = eval {
        Socialtext::Signal->Create(
            user_id => $user_id,
            body => $content,
            %opts,
        );
    };
    if ($@) {
        fail("Couldn't create signal: $@");
    }

    $self->{signal_id} = $signal->signal_id;
    pass("Created signal $self->{signal_id}");
}

sub send_signal_reply {
    my $self = shift;
    my $signal_id = shift;

    $self->send_signal(@_, in_reply_to_id => $signal_id);
}

sub send_signal_dm {
    my $self = shift;
    my $user_id = shift;
    $self->send_signal(@_, recipient_id => $user_id);
}

sub post_signals {
    my $self = shift;
    my $count = shift or die;
    my $message = shift or die;
    my $offset = shift || 1200;

    for my $i ($offset .. $offset+$count-1) {
        my $time = CORE::time();
        my $location = $self->post_signal($message . " $i");

        # Separate each signal by 1+ seconds for Solr
        do { CORE::sleep(1) } until (CORE::time() - $time >= 1);
    }
}

=head2 st_deliver_email( )

Imitates sending an email to a workspace

=cut

sub deliver_email {
    my ($self, $workspace, $email_name) = @_;

    my $in = Socialtext::File::get_contents($self->_relative_filename_to_absolute("t/test-data/email/$email_name"));
    $in =~ s{^Subject: (.*)}{Subject: $1 $^T}m;

    my ($out, $err);
    my @command = ('bin/st-admin', 'deliver-email', '--workspace', $workspace);

    IPC::Run::run \@command, \$in, \$out, \$err;
    $self->{_deliver_email_result} = $? >> 8;
    $self->{_deliver_email_err} = $err;
    diag "Delivered $email_name email to the $workspace workspace";
}

sub deliver_email_result_is {
    my ($self, $result) = @_;
    is $self->{_deliver_email_result}, $result,
        "Delivering email returns $result";
}

sub deliver_email_error_like {
    my ($self, $regex) = @_;
    $regex = $self->quote_as_regex($regex);
    like $self->{_deliver_email_err}, $regex,
        "Delivering email stderr matches $regex";
}

sub set_from_json {
    my $self = shift;
    my $var  = shift;
    my @keys = @_;

    my $cur = $self->{json};
    for (@keys) {
        return unless ref $cur;
        $cur = ref $cur eq 'HASH' ? $cur->{$_} : $cur->[$_];
    }
    $self->{$var} = $cur;
    diag "Set variable $var to $self->{$var}";
}

sub set_from_subject {
    my $self = shift;
    my $name = shift || die "email-name is mandatory for set-from-email";
    my $email_name = shift || die "name is mandatory for set-from-email";
    my $in = Socialtext::File::get_contents($self->_relative_filename_to_absolute("t/test-data/email/$email_name"));
    if ($in =~ m{^Subject: (.*)}m) {
        ($self->{$name} = "$1 $^T") =~ s{^Re: }{};
    }
    else {
        die "Can't find subject in $email_name";
    }
}

sub remove_workspace_permission {
    my ($self, $workspace, $role, $permission) = @_;

    require Socialtext::Role;
    require Socialtext::Permission;

    my $ws = Socialtext::Workspace->new(name => $workspace);
    my $perms = $ws->permissions;
    $perms->remove(
        role => Socialtext::Role->$role,
        permission => Socialtext::Permission->new( name => $permission ),
    );
    diag "Removed $permission permission for $workspace workspace $role role";
}

sub add_workspace_permission {
    my ($self, $workspace, $role, $permission) = @_;

    require Socialtext::Role;
    require Socialtext::Permission;

    my $ws = Socialtext::Workspace->new(name => $workspace);
    my $perms = $ws->permissions;
    $perms->add(
        role => Socialtext::Role->$role,
        permission => Socialtext::Permission->new( name => $permission ),
    );
    diag "Added $permission permission for $workspace workspace $role role";
}

sub start_timer {
    my $self = shift;
    my $name = shift || 'default';

    $self->{_timer}{$name} = [ gettimeofday ];
}

sub faster_than {
    my $self = shift;
    my $ms = shift or die "faster_than requires a time in ms!";
    my $name = shift || 'default';
    my $start = $self->{_timer}{$name} || die "$name is not a valid timer!";

    my $elapsed = tv_interval($start);
    cmp_ok $elapsed, '<=', $ms, "$name timer was faster than $ms";
}

sub parse_logs {
    my $self = shift;
    my $file = shift;

    die "File doesn't exist!" unless -e $file;
    my $report_perl = "$^X -I$ENV{ST_CURRENT}/socialtext-reports/lib"
        . " -I$ENV{ST_CURRENT}/nlw/lib $ENV{ST_CURRENT}/socialtext-reports";
    Socialtext::System::shell_run("$report_perl/bin/st-reports-consume-access-log $file");
}

sub clear_reports {
    my $self = shift;
Socialtext::System::shell_run("cd $ENV{ST_CURRENT}/socialtext-reports; ./setup-dev-env");
}

sub clear_webhooks {
    sql_execute(q{DELETE FROM webhook});
}

=head2 header_isnt ( header, value )

Asserts that a header in the response does not contain the specified value.

=cut

sub header_isnt {
    my $self = shift;
    if ($self->{http}->can('header_isnt')) {
        return $self->{http}->header_isnt(@_);
    }
    else {
        my $header = shift;
        my $expected = shift;
        my $value = $self->{http}->response->header($header);
        isnt($value, $expected, "header $header isnt $expected");
    }
}

=head2 reset_plugins

Reset any global plugin enabled.

=cut

sub reset_plugins {
    my $self = shift;
    sql_execute(q{DELETE FROM "System" WHERE field like '%-enabled-all'});
}

=head2 st-clear-jobs

Clear out any queued jobs.

=cut

sub st_clear_jobs {
    require Socialtext::Jobs;
    Socialtext::Jobs->clear_jobs();
}

=head2 st-process-jobs

Run any queued jobs synchronously.

Takes an optional TYPE as the first parameter. If present, only run jobs matching the given TYPE.

Takes an optional WORKSPACE_ID or NAME as the second parameter. If present, only run jobs pertaining to that workspace.

=cut

sub st_process_jobs {
    my $self = shift;
    my $job = shift || '';
    my $workspace = shift || '';
    my $quiet = shift || 0;
    # sleep a bit, to avoid race conditions w/jobs that don't have sub-second
    # timings (e.g. the "email-notify" wikiD test.
    CORE::sleep(1);

    Test::Socialtext::ceqlotron_run_synchronously($job, $workspace, $quiet);
    CORE::sleep(1);
}


=head2 shell-run any-command and args

=cut

sub shell_run {
    my $self = shift;
    Socialtext::System::shell_run(join ' ', @_);
}

=head2 st_setup_group_if_need(group_name, optional $create_and_add_account, optional $create_ws, optional $add_ws_to_group)

Examines self to see if %%group_name%% is defined, if it not defined, it calls st_setup_group with the provided parameters.

The big advantage of this is that if you do st_setup_a_group, then include a page, the included page can run independently if it sets up it's own group, or as part of the bigger test if it does not.

=cut


sub st_setup_group_if_needed {
    my ($self, $create_and_add_account, $create_ws, $add_ws_to_group, $base) = @_;
    
    if (!defined($self->{'group_name'})) {
        st_setup_a_group($self, $create_and_add_account, $create_ws, $add_ws_to_group, $base);
    }
}

=head2 st-setup_a_group(group_name, optional $create_and_add_account, optional $create_ws, optional $add_ws_to_group)
optional fields are BINARY - blank (0) or true (1)

Guarentted work:
  Create a group named $group_name, populate %%group_id%% with the group id 
  Create a variable %%group_user%% also %%group_short%%
  Create the user %%group_user%% with that user.  Use %%password%% as the password 
  Add that user to group $group_name

If true, they create:
 create_and_add_account - creates variable %%group_acct%% with an account to match; the group and user will be members of said account
 create_ws - creates variable %%group_ws%% with a workspace to match.  If create_and_add_account is true, the ws will be a member of the account
 add_ws_to_group - will add %%group_ws%% to the group

PS: If you've got a more object-oriented, less structured way to do this, I'd be all ears.  
    It feels awkward as is.
 
=cut

sub st_setup_a_group {
     my ($self, $create_and_add_account, $create_ws, $add_ws_to_group, $base) = @_;
     $base = $base || 'gmu';
     $self->handle_command('set','group_user', $base . '%%start_time%%@matt.socialtext.net');
     $self->handle_command('set','group_user_escaped',$base . '%%start_time%%\@matt.socialtext.net');
     $self->handle_command('set','group_user_short', $base . '%%start_time%%');
     $self->handle_command('set','group_name', $base . 'name-%%start_time%%');
    
     #Create the user, the account, and possible the group
     if (defined($create_and_add_account) && ($create_and_add_account) ) {
         $self->handle_command('set','group_acct', $base . 'acct-%%start_time%%');
         $self->handle_command('st-admin','create_account --name %%group_acct%%',' was created');
         $self->handle_command('st-admin','enable-plugin --account %%group_acct%% --plugin people');
         $self->handle_command('st-admin','enable-plugin --account %%group_acct%% --plugin groups');
         #$self->handle_command('st-admin','create_group --name %%group_name%% --account %%group_acct%%', 'has been created');
         $self->handle_command('create_group','%%group_name%%','%%group_acct%%');
         $self->handle_command('st-admin','create_user --account %%group_acct%% --email %%group_user%% --password %%password%%','was created');
         $self->handle_command('st-admin', 'add-member --email %%group_user%% --group %%group_id%%','is now a member of');
     } 
    else {
         $self->handle_command('st-admin', 'create_user --email %%group_user%% --password %%password%%', 'was created');
    #    $self->handle_command('st-admin', 'create_group --name %%%group_name%%','has been created');
         $self->handle_command('create_group','%%group_name%%','%%group_acct%%');
         $self->handle_command('st-admin', 'add-member --email %%group_user%% --group %%group_id%%','is now a member of');
     }

     #Create Workspace if requested
     if (defined($create_ws) && ($create_ws) ) { 
         $self->handle_command('set','group_ws', $base . '-ws-%%start_time%%');
         if (defined($create_and_add_account) && ($create_and_add_account) ) {
             $self->handle_command('st-admin', 'create_workspace --name %%group_ws%% --title %%group_ws%% --empty --account %%group_acct%%','was created');
         } else {
             $self->handle_command('st-admin', 'create_workspace --name %%group_ws%% --empty --title %%group_ws%%','was created');
         }
     }

     #Add Workspace To Group if requested
     if (defined($add_ws_to_group) &&  ($add_ws_to_group) ) {
         $self->handle_command('st-admin','add-member --group %%group_id%% --workspace %%group_ws%%','now has the role of');
     }
}

sub body_like {
    my ($self, $expected) = @_;
    my $body = $self->{http}->_decoded_content;

    my $re_expected = $self->quote_as_regex($expected);

    if ($ENV{TEST_LESS_VERBOSE} and length($body) > 3000 ) {
        ok $body =~ $re_expected,
            $self->{http}->name() . " body-like $re_expected";
    }
    else {
        like $body, $re_expected,
            $self->{http}->name() . " body-like $re_expected";
    }
}

sub body_unlike {
    my ($self, $expected) = @_;
    my $body = $self->{http}->_decoded_content;

    my $re_expected = $self->quote_as_regex($expected);

    if ($ENV{TEST_LESS_VERBOSE} and length($body) > 3000 ) {
        ok $body !~ $re_expected,
            $self->{http}->name() . " body-unlike $re_expected";
    }
    else {
        unlike $body, $re_expected,
            $self->{http}->name() . " body-unlike $re_expected";
    }
}

sub job_count {
    my ($self, $class, $count) = @_;
    if ($class && $class ne '*') {
        $class = "Socialtext::Job::$class";
    }
    $class ||= '*';
    my $actual;
    if ($class eq '*') {
        $actual = sql_singlevalue("SELECT COUNT(*) FROM job");
    }
    else {
        $actual = sql_singlevalue(q{
            SELECT COUNT(*) FROM job NATURAL JOIN funcmap WHERE funcname = ?
        }, $class);
    }
    is $actual, $count, "$count jobs with class '$class'";
}

sub job_exists {
    my ($self, $class, $uniqkey) = @_;
    $class = "Socialtext::Job::$class";

    my $actual = sql_singlevalue(q{
        SELECT COUNT(*)
          FROM job NATURAL JOIN funcmap
         WHERE funcname = ? AND uniqkey = ?
    }, $class, $uniqkey);
    $actual ||= 0;
    ok $actual == 1, "job with key '$uniqkey' and class '$class' exists";
}

sub st_fast_forward_jobs {
    my ($self, $minutes) = @_;
    my $s = $minutes * 60;
    eval { sql_txn {
        sql_execute(q{
            UPDATE job SET
                insert_time = insert_time - $1,
                run_after = run_after - $1,
                grabbed_until = grabbed_until - $1
        }, $s);
        sql_execute(q{UPDATE error SET error_time = error_time-$1}, $s);
        sql_execute(q{UPDATE exitstatus SET completion_time = completion_time-$1}, $s);
    }};
    ok !$@, "fast-forwarded jobs by $minutes minutes";
}

sub ceq_read { system("ceq-read") }

sub st_account_type_is {
    my $self = shift;
    my $name = shift;
    my $type = shift;

    my $acct = Socialtext::Account->new( name => $name );
    die "Couldn't find account $name" unless $acct;
    is $acct->account_type, $type, "Account type matches";
}

sub delete_account {
    my $self = shift;
    my $name = shift;
    my $acct = Socialtext::Account->new( name => $name );
    die "Couldn't find account $name" unless $acct;
    $acct->delete;
}

my @exports;
END { rmtree(\@exports) if @exports };

sub st_export_account {
    my $self = shift;
    my $account = shift;
    my $dir = "/tmp/$account.export";
    push @exports, $dir;
    Socialtext::System::shell_run(
        'st-admin', 'export-account', '--account', $account, '--dir', $dir,
    );
}

sub st_import_account {
    my $self = shift;
    my $account = shift;
    my $dir = "/tmp/$account.export";
    Socialtext::System::shell_run(
        'st-admin', 'import-account', '--dir', $dir,
    );
}

sub _st_account_export_field {
    my $self = shift;
    my $account = shift;
    my $field = shift;
    my $yaml = YAML::LoadFile("/tmp/$account.export/account.yaml");
    for my $part (split /\./, $field) {
        $yaml = $part =~ /^\d+$/ ? $yaml->[$part] : $yaml->{$part};
    }
    return $yaml;
}

sub st_account_export_field_is {
    my $self = shift;
    my $account = shift;
    my $field = shift;
    my $expected = shift;
    is $self->_st_account_export_field($account, $field),
        $expected,
        "$account $field";
}

sub st_account_export_field_is_undef {
    my $self = shift;
    my $account = shift;
    my $field = shift;
    is $self->_st_account_export_field($account, $field),
        undef,
        "$account $field";
}

sub st_account_export_field_like {
    my $self = shift;
    my $account = shift;
    my $field = shift;
    my $expected = shift;
    like $self->_st_account_export_field($account, $field),
        $expected,
        "$account $field";
}

sub st_purge_account_gallery {
    my ($self, $acct_name) = @_;
    my $acct = Socialtext::Account->new(name => $acct_name);
    my $sth = sql_execute('
        DELETE FROM gallery WHERE account_id = ?
    ', $acct->account_id);
    diag loc("test.deleted-galleries=count", $sth->rows)."\n";
}

sub st_purge_account_containers {
    my ($self, $acct_name) = @_;
    my $acct = Socialtext::Account->new(name => $acct_name);
    my $sth = sql_execute('
        DELETE FROM container
         WHERE user_set_id
            IN (
                SELECT user_id
                  FROM "UserMetadata"
                 WHERE primary_account_id = $1
            )
            OR user_set_id = ' . ACCT_OFFSET . ' + $1
    ', $acct->account_id);
    diag loc("test.deleted-containers=count", $sth->rows)."\n";
}

sub st_purge_uploaded_widgets {
    my ($self, $acct_name) = @_;
    my $acct = Socialtext::Account->new(name => $acct_name);
    my $sth = sql_execute(q{
        DELETE FROM gadget
         WHERE src IS NULL
            OR src like 'file:/tmp/acct-%/%.xml'
            OR src like 'urn:%'
    });
    diag loc("test.deleted-uploaded-widgets=count", $sth->rows)."\n";
}

sub st_purge_widget {
    my ($self, $src) = @_;
    my $sth = sql_execute('DELETE FROM gadget WHERE src = ?', $src);
    diag loc("test.deleted-widgets=count", $sth->rows)."\n";
}

sub enable_ws_plugin    { shift; _change_plugin('Workspace', 1, @_) }
sub disable_ws_plugin   { shift; _change_plugin('Workspace', 0, @_) }
sub enable_acct_plugin  { shift; _change_plugin('Account',   1, @_) }
sub disable_acct_plugin { shift; _change_plugin('Account',   0, @_) }

sub _change_plugin {
    my $class  = 'Socialtext::' . shift;
    my $method = shift() ? 'enable_plugin' : 'disable_plugin';
    my $plugin = shift;
    my $name = shift;

    my $obj = $class->new(name => $name);
    $obj->$method($plugin);
    diag "$method($plugin) for $name\n";
}

sub st_catchup_logs {
   my $self = shift;
   if (Socialtext::AppConfig->startup_user_is_human_user()) {
       #In Dev Env
       my $current_dir = cwd;
       my $new_dir =  $ENV{ST_CURRENT} . "/socialtext-reports/";
       chdir($new_dir);
       my $str = $ENV{ST_CURRENT} . "/socialtext-reports/parse-dev-env-logs  >/dev/null 2>&1";
       system($str);
       chdir($current_dir);
   } else {
       # call the log consumer
       # Note: THIS ONLY WORKS AFTER RUNNING st-appliance-wikitests to set it
       # up
       #
       my $str = "/usr/sbin/st-appliance-reports-consume-nlw-log /var/log/nlw.log";
       system($str);
   }
}

sub _run_command {
    my $command = shift;
    my $verify = shift || '';
    my $output = qx($command 2>&1);
    return if $verify eq 'ignore output';

    if ($verify) {
        like $output, $verify, $command;
    }
    else {
        diag $output;
    }
}

sub set_profile_field {
    my $self = shift;
    my $user_name = shift;
    my $field_name = shift;
    my $field_value = shift;

    my $user = Socialtext::User->Resolve( $user_name );
    my $profile = Socialtext::People::Profile->GetProfile($user);
    diag "Setting "
        . $user->email_address
        . " field $field_name to $field_value";
    $profile->update_from_resource( {$field_name => $field_value} );
    $profile->save;
}

sub set_profile_relationship {
    my $self = shift;
    my $user_name = shift;
    my $field_name = shift;
    my $other_user_name = shift;

    my $user = Socialtext::User->Resolve( $user_name );
    my $otheruser = Socialtext::User->Resolve( $other_user_name );
    my $profile = Socialtext::People::Profile->GetProfile($user);
    diag "Setting "
        . $user->email_address
        . "'s $field_name field to " . $otheruser->email_address;

    $profile->update_from_resource( {$field_name => { id => $otheruser->user_id} } );
    $profile->save;
}


sub tag_profile_via_gui {
    my ($self, $tag) = @_;
    $self->handle_command('open_ok','/st/profile');    
    $self->handle_command('wait_for_element_visible_ok','new_tag', 30000);
    $self->handle_command('type_ok', 'new_tag', $tag);
    $self->handle_command('click_ok','//input[@value=' . "'" . 'Add Tag' . "'" . ']');      
    $self->handle_command('wait_for_element_visible_ok',"link=$tag", 30000);
}

sub tag_profile {
    my $self = shift;
    my $user_name = shift;
    my $tag = shift;

    my $user = Socialtext::User->Resolve( $user_name );
    my $profile = Socialtext::People::Profile->GetProfile($user);

    my $tag_name = Socialtext::People::Profile::normalize_tag($tag);
    my $tags = $profile->tags;
    if ($tag_name =~ m/^-(.+)/) {
        delete $tags->{$1};
        diag "Removed tag $tag_name from " . $user->email_address;
    }
    else {
        $tags->{$tag_name} = 1;
        diag "Tagged " . $user->email_address . " with '$tag_name'";
    }

    $profile->tags($tags);
    $profile->save;
}

sub add_profile_field {
    my $self = shift;
    my $account_name = shift;
    my $field_name = shift;
    my $field_title = shift;
    my $hidden = shift || 0;

    my $account = Socialtext::Account->new(name => $account_name);
    my $plugin_class = Socialtext::Pluggable::Adapter->plugin_class('people');
    $plugin_class->AddProfileField({
            account => $account,
            name => $field_name,
            title => $field_title,
            is_hidden => $hidden,
        },
    );
    diag "Added profile field '$field_name' to $account_name";
}

sub show_profile_field {
    shift->_set_profile_field_hidden(0, @_);
}

sub hide_profile_field {
    shift->_set_profile_field_hidden(1, @_);
}

sub _set_profile_field_hidden {
    my $self = shift;
    my $hidden = shift;
    my $account_name = shift;
    my $field_name = shift;

    my $account = Socialtext::Account->new(name => $account_name);
    my $fields = Socialtext::People::Fields->new(
        account_id => $account->account_id,
    );
    my $field = $fields->by_name($field_name);
    die "Couldn't find field $field_name" unless $field;

    $field->is_hidden($hidden);
    $field->save;
}

sub set_substr {
    my $self = shift;
    my $dest_var = shift;
    my $src_data = shift;
    my $characters = shift;

    $self->{$dest_var} = substr($src_data, 0, $characters);
    diag "Set $dest_var to '$self->{$dest_var}'";
}

# Gross hack workaround
sub set_pipe {
    my $self = shift;
    my $var  = shift || 'pipe';
    $self->{$var} = '|';
}

=head2 json_path_is

=head2 json_path_isnt

Test that the value selected by the path (first argument) is/isn't equal to the
specified value (second argument).

Only a sub-set of JSONPath is supported.  All expressions are anchored to the
root of the parsed JSON object, so the leading C<$> is optional.  Only scalar
values can be selected; selecing objects, lists and collections are not
supported.  JSONPath functions are also not supported.

Use C<< [0] >> notation to select an element of an array.  Processed as a perl
array offset, so negative values can be used.

Use C<< .element >> or C<< ['element'] >> to select a hash key.

Examples:

    # select the string at baz, nested inside of bar and foo elements.
    $.foo.bar.baz
    $['foo'].bar['baz']

    # select the user_id of the first array element
    $[0].user_id

=head2 json_path_like

=head2 json_path_unlike

Test that the string at the specified path matches the specified regex.  If a
regex is not supplied, a substring match is performed.

=head2 json_path_exists

=head2 json_path_missing

Test that something exists or doesn't exist at the specified path.

=cut

sub _select_json_path {
    my ($self,$path,$o) = @_;

    return $o if $path eq '';

    my ($subpath,$subobj);
    my ($key,$idx);
    # .foo
    # ['foo']
    if ($path =~ /^\.([a-zA-Z][a-zA-Z0-9_]+)(.*?)$/ or
        $path =~ /^\['(.+?)'\](.*?)$/) 
    {
        ($key,$subpath) = ($1,$2);
        die "missing: expected hash\n" unless (ref($o) eq 'HASH');
        die "missing: no such key $key\n" unless (exists $o->{$key});
        $subobj = $o->{$key};
    }
    # [10]
    elsif ($path =~ /^\[(\d+)\](.*?)$/) {
        ($idx,$subpath) = ($1,$2);
        die "missing: expected array\n" unless (ref($o) eq 'ARRAY');
        die "missing: array index $idx is out of bounds\n" if ($idx > $#$o);
        $subobj = $o->[$idx];
    }
    else {
        die "can't parse simple path expression: >>>$path<<<\n";
    }

    return $self->_select_json_path($subpath, $subobj);
}

sub _json_path_test {
    my ($self, $test, $path, $expected) = @_;

    my $comment = $self->{http}->{name}." json_path_$test, path $path";

    $path =~ s/^\$//; # remove leading $

    unless ($self->{json}) {
        fail $self->{http}->name." did you forget to json-parse?";
        return;
    }

    my $sel = eval { $self->_select_json_path($path, $self->{json}) };
    if (my $e = $@) {
        if ($test eq 'missing') { # grep json_path_missing
            return like $e, qr/^missing/, $comment;
        }
        diag "path selection error: $e";
        if ($test eq 'exists') { # grep json_path_exists (failure case)
            fail $comment;
            return;
        }
    }

    # work around the fact that we aren't reading .wiki files in unicode mode
    $expected = ensure_is_utf8($expected) if $test =~ /^is/;
    if ($test eq 'is') { # grep json_path_is
        return is $sel, $expected, $comment;
    }
    elsif ($test eq 'isnt') { # grep json_path_isnt
        return isnt $sel, $expected, $comment;
    }
    elsif ($test eq 'like') { # grep json_path_like
        return like $sel, $expected, $comment;
    }
    elsif ($test eq 'unlike') { # grep json_path_unlike
        return unlike $sel, $expected, $comment;
    }
    elsif ($test eq 'exists') { # grep json_path_exists (success case)
        pass $comment;
        return 1;
    }
    elsif ($test eq 'size') { # grep json_path_size
        if ('ARRAY' ne ref($sel)) {
            fail $comment. ' - selection is not an array';
            return;
        }
        return is scalar(@$sel), $expected, $comment;
    }

    fail $comment;
    return;
}

{
    no strict 'refs';
    for my $cmd (qw(
        json_path_is 
        json_path_isnt 
        json_path_like 
        json_path_unlike 
        json_path_exists 
        json_path_missing 
        json_path_size
    )) {
        (my $test = $cmd) =~ s/^json_path_//;
        *{$cmd} = sub {
            my $self = shift;
            $self->_json_path_test($test,@_);
        };
    }
}

=head2 json_in_array

Test that a string occurs within a json array.

=cut

sub json_in_array {
    my ($self, $path, $element) = @_;
    $path =~ s/^\$//; # remove leading $

    my $selected = eval { $self->_select_json_path($path, $self->{json}) };
    if (my $e = $@) {
        fail $@;
        return;
    }

    fail "'$path' is not an array'"
        unless ref($selected) && ref($selected) eq 'ARRAY';

    # breaks if $_ is not a scalar.
    my $exists = any { "$_" eq "$element" } @$selected;
    ok $exists, "found '$element' in json path";
}

=head2 json_path_set

Set the specified wikitest variale (first argument) to the value of the
selected json path.

=cut

sub json_path_set {
    my ($self, $key, $path) = @_;

    $path =~ s/^\$//; # remove leading $
    my $sel = eval { $self->_select_json_path($path, $self->{json}) };
    if (my $e = $@) {
        fail "path selection error: $e";
    }
    else {
        $self->{$key} = $sel;
        pass "set $key to $sel (\$$path)";
    }
}

=head2 json-path-parse

Parse a json-path selection as if it were JSON itself (the OpenSocial
json-proxy specification does this sort of embedding).

After parsing, the other C<json-path-> directives will work as expected.

=cut

sub json_path_parse {
    my $self = shift;
    my $path = shift;

    if (!$self->{json}) {
        fail "json-path-parse error: you need to call 'json-parse' first (or it failed previously)";
        return;
    }

    $path =~ s/^\$//; # remove leading $
    my $sel = eval { $self->_select_json_path($path, $self->{json}) };
    if (my $e = $@) {
        fail "json-path-parse selection error: $e";
        $self->{json} = {};
        return;
    }

    my $json = eval { decode_json_utf8($sel) };
    if (my $e = $@) {
        fail "json-path-parse error: $e";
        $self->{json} = {};
    }
    else {
        pass "json-path-parse ok";
        $self->{json} = $json;
    }
}

sub header_unlike {
    my $self = shift;
    my $name = shift || die "header name is mandatory for header_unlike";
    my $rgx  = shift || die "regex is mandatory for header_unlike";
    my $header   = $self->{http}->response->header($name);
    my $expected = $self->quote_as_regex($rgx);
    unlike $header, $rgx, "$name header-unlike $expected";
}

sub st_widgets {
    my $self    = shift;
    my $options = shift || '';
    Socialtext::System::shell_run('st-widgets', $options);
}

sub signal_search {
    my $self = shift;
    my $query = shift;
    my $expected_result_count = shift;

    $self->get_json("/data/signals?$query");
    $self->code_is(200);
    $self->json_parse;
    $self->json_array_size($expected_result_count);
}

sub add_webhook {
    my $self = shift;
    my $class = shift;
    my $url = shift;
    my $extra = shift || '{}';

    my $args = decode_json($extra);
    $args->{class} = $class;
    $args->{url}   = $url;
    $self->post_json('/data/webhooks', encode_json($args));
    $self->code_is(201);
    unless ($self->{http}->response->code == 201) {
        die "Failed to create webhook: " . encode_json($args);
    }
    diag "Created webhook $args->{class}=$args->{url}";
}

# XXX This will only work on appliances/VEs
sub wait_for_backup_to_finish {
    my $self = shift;
    my $state_file = '/var/run/socialtext/st-daemon-backup.state';
    my $yaml = LoadFile($state_file);
    diag "Backup status:\n" . Dumper $yaml;
    while (1) {
        $yaml = LoadFile($state_file);
        if ($yaml->{status} eq 'finished') {
            ok 1, 'Backup has finished';
            return;
        }
        CORE::sleep(10);
        ok 1, "Backup still in progress";
    }
}

# XXX This will only work on appliances/VEs
sub wait_for_restore_to_finish {
    my $self = shift;
    my $state_file = '/var/run/socialtext/st-daemon-restore.state';
    my $yaml = LoadFile($state_file);
    diag "Restore status:\n" . Dumper $yaml;
    while (1) {
        $yaml = LoadFile($state_file);
        if ($yaml->{status} eq 'finished') {
            ok 1, 'Restore has finished';
            return;
        }
        CORE::sleep(30);
        ok 1, "Restore still in progress. Checking again in 30 seconds.";
    }
}

sub signal_targeted {
    my ($self, $signal_id, $what, $id, $yes_no) = @_;
    $yes_no ||= 'yes';
    my $expect = ($yes_no eq 'yes') ? 1 : 0;
    my $uset_id = $id + (($what eq 'group') ? GROUP_OFFSET : ACCT_OFFSET);
    my $sth = sql_execute(q{
        SELECT COUNT(*) FROM signal_user_set
        WHERE signal_id = ? AND user_set_id = ?
    }, $signal_id, $uset_id);
    my ($count) = $sth->fetchrow_array();

    if ($expect) {
        ok($count == $expect, "signal targeted $what $id ($uset_id)");
    }
    else {
        ok($count == $expect, "signal did not target $what $id ($uset_id)");
    }
}

sub set_basic_auth_header {
    my ($self, $name, $user, $pass) = @_;

    $user ||= $self->{username};
    $pass ||= $self->{password};

    $self->{$name} = "Basic ".  MIME::Base64::encode("$user:$pass", '');
}

sub restart_userd {
    my $self = shift;
    Socialtext::System::shell_run('nlwctl', '-s','restart');
    my $ua = LWP::UserAgent->new;
    my $req = HTTP::Request->new(GET => 
        'http://localhost:'.$self->{userd_port}.'/ping',
        [Accept => 'application/json']);
    # assumes graceful shutdown delay is 5 seconds:
    for (1..18) {
        my $resp = $ua->request($req);
        if ($resp->is_success) {
            pass "userd restarted";
            return;
        }
        Time::HiRes::sleep(0.5);
    }
    fail "userd could not be restarted";
}

sub restart_everything {
    my $self = shift;
    Socialtext::System::shell_run(qw( nlwctl restart ));

    my $host = $self->{hostname};
    my @to_check = (
        # UserD
        HTTP::Request->new(
            GET => 'http://localhost:' . $self->{userd_port} . '/ping',
            [ Accept => 'application/json' ]
        ),
        # NLW
        HTTP::Request->new(
            GET => "http://$host:" . $self->{http_port} . '/nlw/login.html'
        ),
    );

    my $ua = LWP::UserAgent->new;
  SERVICE:
    foreach my $req (@to_check) {
      ATTEMPT:
        for (1 .. 18) {
            my $resp = $ua->request($req);
            next SERVICE unless ($resp->is_error);
            Time::HiRes::sleep(0.5);
        }
        fail "unable to reach: " . $req->uri;
        BAIL_OUT("services could not be restarted");
    }
    pass "services restarted";
}

sub jsmake {
    my ($self, $target, $dir) = @_;
    require Socialtext::MakeJS;
    if ($target eq 'all') {
        Socialtext::MakeJS->BuildAll;
    }
    elsif ($target eq 'cleanall') {
        Socialtext::MakeJS->CleanAll;;
    }
    elsif ($target eq 'clean') {
        Socialtext::MakeJS->CleanDir($dir);
    }
    else {
        Socialtext::MakeJS->Build($dir, $target);
    }
}

sub download_ok {
    my ($self, $path, $body_re) = @_;
    my $basename = File::Basename::basename($path);
    $self->get($path);
    $self->code_is(200);
    $self->body_like($body_re);
    $self->has_header('content-disposition', qq{filename="$basename"});
}

sub _is_wikiwyg {
    my $browser = $ENV{'selenium_browser'} || 'chrome';
    if ($browser=~/safari|chrome|firefox/ig)  {
        return 1;
    } else {
        return 0;
    }
}

sub masked_url_is {
    my ($self, $url, $expected) = @_;
    $self->get($url, 'text/html', "User-Agent=Gecko");

    my $resp = $self->{http}->response;
    if ($resp->code == 301 or $resp->code == 302) {
        my $location = $resp->header('Location') || die 'No Location header';
        diag "Redirect $location";
        return $self->masked_url_is($location, $expected);
    }

    $self->code_is(200);
    if ($resp->content =~ /Socialtext\.masked_url = "([^"]*)";/) {
        is $1, $expected, "masked-url-is $expected";
    }
    else {
        fail "No masked url found - $url";
    }
}

1;
