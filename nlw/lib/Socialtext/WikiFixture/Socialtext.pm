# @COPYRIGHT@
package Socialtext::WikiFixture::Socialtext;
use strict;
use warnings;
use base 'Socialtext::WikiFixture::SocialBase';
use base 'Socialtext::WikiFixture::Selenese';
use Socialtext::Cache;
use Socialtext::System qw/shell_run/;
use Socialtext::Workspace;
use Test::More;
use Test::Socialtext;
use IO::Scalar;
use Text::ParseWords qw(shellwords);
use Cwd;
use Socialtext::AppConfig;
use File::Slurp qw(slurp);
use List::MoreUtils qw(before after);
use Socialtext::Account;
use Socialtext::SQL ();

=head1 NAME

Socialtext::WikiFixture::Selenese - Executes wiki tables using Selenium RC

=cut

our $VERSION = '0.03';

=head1 DESCRIPTION

This module is a subclass of Socialtext::WikiFixture::Selenese and includes
extra commands specific for testing a Socialtext wiki.

=head1 FUNCTIONS

=head2 new( %opts )

Create a new fixture object.  The same options as
Socialtext::WikiFixture::Selenese are required, as well as:

=over 4

=item workspace

Mandatory - Specifies which Socialtext workspace will be tested.

=item username

Mandatory - username to login to the wiki with.

=item password

Mandatory - password to login to the wiki with.

=back

=head2 init()

Creates the Test::WWW::Selenium object, and logs into the Socialtext
workspace.

=cut

sub init {
    my ($self) = @_;

    $self->{mandatory_args} ||= [qw(workspace username password)];
    for (@{ $self->{mandatory_args} }) {
        die "$_ is mandatory!" unless $self->{$_};
    }
   
    #Default skin to s3 since skin is obsolete
    my $ws = Socialtext::Workspace->new( name => $self->{workspace} );
    if (defined($ws)) {
        $self->{'workspace_id'} = $ws->workspace_id;
    }
  
    $self->{'skin'} = 's3';
    
    my $short_username = $self->{'username'};
    $short_username =~ s/^([\W\w\.]*)\@.+$/$1/; # truncate if email address
    $self->{'short_username'} = $short_username || $self->{'username'};
    
    $self->SUPER::init;
    Socialtext::WikiFixture::Selenese::init($self); # how to do this better?

    { # Talc/Topaz are configured to allow emailing into specific dev-envs
        (my $host = $self->{browser_url}) =~ s#^http.?://(.+):\d+#$1#;
        $self->{wikiemail} = $ENV{WIKIEMAIL} || "$ENV{USER}.$host";
        $self->{defaultaccount} = Socialtext::Account->Default->name;
        diag "wikiemail:  $self->{wikiemail}";
        diag "defaultaccount:  $self->{defaultaccount}";
    }
    for my $var (map { /^selenium_var_(.+)/ ? $1 : () } keys %ENV) {
        diag "[selenium_var] $var: ".$ENV{"selenium_var_$var"};
        $self->{$var} = $ENV{"selenium_var_$var"};
    }
    diag "Browser url is ".$self->{browser_url};
    diag "Session ID: ".$self->{selenium}{session_id};
    $self->st_login;
}

=head2 handle_command( @row )

Run the command.  Subclasses can override this.

=cut

sub handle_command {
    my $self = shift;
    
    # Try the SocialBase commands first
    my @args = $self->_munge_command_and_opts(@_);
    eval { $self->SUPER::_handle_command(@args) };
    return unless $@; # Here we see an error and so it's run twice

    # Fallback to Selenese command processing
    $self->SUPER::handle_command(@_);
}


=head2 todo()

Same as a comment, but acts as a failing TODO test.

Useful for leaving a trail of breadcrumbs for yourself for things that you
haven't gotten to yet, but that you plan on implementing.

Outputs standard TAP for a failed TODO test.

=cut

{
    no warnings 'redefine';
    sub todo {
        my $self = shift;
        my $msg  = shift;
        TODO: {
            local $TODO = 'not yet implemented';
            ok 0, $msg;
        }
    }
}

=head2 st_login()

Logs into the Socialtext wiki using supplied username and password.

=cut

sub st_login {
    my $self = shift;
    my $sel = $self->{selenium};

    my $username = shift || $self->{username};
    my $password = shift || $self->{password};
    my $workspace = shift || $self->{workspace};

    my $url = '/challenge';
    $url .= "?\%2F$workspace\%2Findex.cgi" if $workspace;
    diag "st-login: $username, $password, $workspace - $url";
    $sel->open_ok($url);
    $sel->type_ok('username', $username);
    $sel->type_ok('password', $password);
    $self->click_and_wait(q{id=login_btn}, 'log in');
}

=head2 click_and_pause

For some reason no submit-is-done event is sent, and we have no interlock to know the next step is done.

(For example, js is firing which changes the text and we want to match it with a regexp.  We can't use
wait_for_text_present_ok so we've got to use text_like, which has no wait_for)

=cut

sub click_and_pause {
  my ($self, $link, $pause, $andwait) = @_;
  st_click_pause($self, $link, $pause, $andwait);
}


=head2 st_logout()

Log out of the Socialtext wiki.

=cut

sub st_logout {
    my $self = shift;
    diag "st-logout";

    # go to Miki first to avoid the auto-refresh of watchlist/group in S3,
    # which could trigger a 401 Basic Auth poupup upon logout.
    $self->handle_command('open_ok', '/m/workspace_list');
    $self->handle_command('open_ok', '/nlw/submit/logout');
}

=head2 st_logoutin()

Logs out of the workspace, then logs back in.

A username and password are optional parameters, and will be used in place
of the configured username and password.

=cut

sub st_logoutin {
    my ($self, $username, $password) = @_;
    $self->st_logout;
    $self->st_login($username, $password);
}

=head2 st_check_search_stickyness ( $label, optional $workspace)

Change the search dropdown, search for test, logout, make sure dropdown is sticky

Label should be of the form 'label=Search Critera'

Example:

st-check-search-stickyness | label=Search My Workspaces: | test-data |

=cut

sub st_check_search_stickyness {
   my ($self, $label, $workspace, $url) = @_;
   my $comment = 'Test Case: Search Selector - ';
   if (!defined($url) || length($url)<2) {
       if (defined($workspace) && length($workspace)>2) {
          $url = "/$workspace";
          $comment.="Sticky test within the $workspace workspace for $label";
       } else {
          $url = '/st/dashboard/';
          $comment.="Sticky test at the dashboard level for $label";
       }
  } else {
     $comment.="Sticky test within $url\n";
  }

  $self->handle_command('comment',$comment);
  $self->handle_command('open_ok',$url);
  $self->handle_command('wait_for_element_visible_ok','st-search-submit',30000);
  $self->handle_command('wait_for_element_visible_ok','st-search-term',30000);  
  $self->handle_command('wait_for_element_visible_ok','st-search-action',30000);  
  $self->handle_command('select_ok','st-search-action',$label);  
  $self->handle_command('type_ok','st-search-term', 'test');
  $self->handle_command('click_and_wait','st-search-submit');  
  $self->handle_command('st-logoutin');
  $self->handle_command('open_ok',$url);  
  $self->handle_command('is_selected_ok','st-search-action',$label);
}


sub st_check_people_stickyness {
   my ($self, $label) = @_;
   $self->st_check_search_stickyness($label, '','/?action=people');
}

sub st_check_group_stickyness {
    my ($self, $label) = @_;
    $self->st_check_search_stickyness($label, '','/st/groups');
}

sub st_check_explore_stickyness {
    my ($self, $label) = @_;
    $self->st_check_search_stickyness($label, '','/st/explore');
}

sub st_check_signals_stickyness {
    my ($self, $label) = @_; 
    $self->st_check_search_stickyness($label, '','/st/signals');
}

sub st_check_workspaces_stickyness {
    my ($self, $label) = @_;
    $self->st_check_search_stickyness($label, '','/?action=workspaces_listall');
}

sub st_upload_if_highperms {
    my ($self, $file) = @_;
    my $browser = ((($ENV{sauce_browser} || $ENV{selenium_browser} || '') =~ /(\w+)/) ? $1 : 'firefox');
    diag "Browser is $browser\n";
    if ($browser=~/firefox/ )  {
        $self->st_upload_attachment_to_wikipage($file);
    }
}

sub st_check_files_if_highperms {
    my ($self, $file) = @_;
    my $browser = ((($ENV{sauce_browser} || $ENV{selenium_browser} || '') =~ /(\w+)/) ? $1 : 'firefox');
    if ($browser=~/firefox/ )  {
        $self->handle_command('text_like','st-display-mode-widgets',$file);
    }
}

sub st_upload_attachment_to_wikipage {
    my ($self, $file) = @_;
    $self->handle_command('wait_for_element_visible_ok', 'st-attachments-uploadbutton','60000');
    $self->handle_command('click_ok', 'st-attachments-uploadbutton');
    $self->handle_command('wait_for_element_visible_ok', 'st-attachments-attach-filename', 30000);
    $self->handle_command('type_ok', 'st-attachments-attach-filename', '%%wikitest_files%%'.$file);
    $self->handle_command('wait_for_text_present_ok','Uploaded files: ' . $file, 30000);
    $self->handle_command('wait_for_element_visible_ok', 'st-attachments-attach-closebutton', 30000);
    $self->handle_command('click_ok', 'st-attachments-attach-closebutton');
    $self->handle_command('pause_ok', 5000, 'pause to register index job');
    $self->handle_command('st_process_jobs','AttachmentIndex');
    $self->handle_command('wait_for_element_visible_ok','link='.$file,30000);
}


=head2 st_toggle_captcha ($toggle - default to 0, or off)

Disables or eanbles the captcha on the server

=cut

sub st_toggle_captcha {
    my ($self, $enable) = @_;
    $self->handle_command('st-admin','give-system-admin --e %%username%%');
    $self->handle_command('open_ok','/console/?rm=Setup');
    $self->handle_command('wait_for_element_visible_ok','captcha_enabled',3000);
    $self->handle_command('wait_for_element_visible_ok','setup-captcha',3000);    
    
    if ($enable) {
        $self->handle_command('check_ok','captcha_enabled');
    } else {
        $self->handle_command('uncheck_ok','captcha_enabled');
    }

    $self->handle_command('click_and_wait','setup-captcha');    
    $self->handle_command('st-admin','remove-system-admin --e %%username%%','no longer has system admin access');
}

=head2 st_page_title( $expected_title )

Verifies that the page title (NOT HTML title) is correct.

=cut

sub st_page_title {

    my ($self, $expectedTitle) = @_;
    my $contentDiv = '//div[@id=\'content\']';
    $self->handle_command('text_like',$contentDiv,$expectedTitle);
}

=head2 st_page_multi_view( $url, $numviews) 

Looks at the page default_server/url numviews number of times. 

Useful to canning up page views for reports, metrics widgets, etc.

Opens a different page between each view to assure reloading

=cut

sub st_page_multi_view {
  my ($self, $url, $numviews) = @_;
  $self->handle_command('set_Speed',3000);
  for (my $idx=0; $idx<$numviews;$idx++) {
      $self->{selenium}->open_ok($url);
      $self->{selenium}->open_ok('/?action=invite');
      #$self->handle_command('location_like',$url);
  }
  $self->handle_command('set_Speed',0);
}

=head2 st_page_multi_watch( $numwatches) 

Watch-On, Watch-Off, repeat.  Useful for metrics on pages, user activities, etc

=cut

sub st_page_multi_watch {
  my ($self, $numwatches) = @_;
  for (my $idx=0; $idx<$numwatches;$idx++) {
     $self->st_watch_page(1);
     $self->st_is_watched(1);
     $self->st_watch_page(0);
     $self->st_is_watched(0);
  }
}

=head2 get_url( $variable )
  Get the URL, stick it in a variable
=cut

sub get_url {
    my ($self, $variable) = @_;
    $self->{$variable} = $self->get_location();
}

=head2 get_id_from_url ($variable) 
  You're on URL ending in /d$.  Get a group ID, stick it into $variable
=cut

sub get_id_from_url {
    my ($self, $variable) = @_;
    my $str = $self->get_location();
    my @arr = split(/\//, $str);
    $self->{$variable} = $arr[scalar(@arr)-1];
}

=head2 st_page_save 
  | st_page_save |  |  |
  Pauses 3 seconds before clicking st-save-button-link; needed when the GUI element is not yet enabled
=cut

sub st_page_save {
    my ($self) = @_;
    st_pause_click($self, 3000,'st-save-button-link','andWait');
    $self->handle_command('wait_for_element_visible_ok','st-edit-button-link','15000');
}

=head2 st_pause_click
  | st_pause_click | N | button_locator | ANDWAIT |
  Pauses N msec before clicking the button_locator; needed when the GUI element is not yet enabled
  uses click_and_wait if third arg is not empty
=cut

sub st_pause_click {
    my ($self, $pause, $locator, $andwait) = @_;
    my $cmd = $andwait ? 'click_and_wait' : 'click_ok';
    diag "st_pause_click: pausing $pause, then $cmd $locator";
    $self->handle_command('pause_ok',$pause);
    $self->handle_command($cmd, $locator);
}

=head2 st_click_pause
  | st_click_pause | button_locator | N | ANDWAIT |
  Clicks the button_locator then pauses for N msec; needed to prevent race conditions after saving comments
  uses click_and_wait if third arg is not empty
=cut

sub st_click_pause {
    my ($self, $locator, $pause, $andwait) = @_;
    my $cmd = $andwait ? 'click_and_wait' : 'click_ok';
    my $mypause = $pause ? $pause : '15000';
    diag "st_click_pause: $cmd $locator, pausing $mypause";
    $self->handle_command($cmd, $locator);
    $self->handle_command('pause_ok',$mypause);
}

=head2 st_create_wikipage ( $workspace, pagename )

Creates a plain-english page at server/workspace/pagname and leaves you in view mode.  

So if you pass in page name of "Super Matt", it will save as "Super Matt" and have
a url of super_matt

This is done through the GUI. (You may want to do this through the GUI if, say, you 
want the output written to nlw.log)

=cut

sub st_create_wikipage {
    my ($self, $workspace, $pagename)  = @_;
    my $url = '/' . $workspace . '/?action=new_page';
    $self->{selenium}->open_ok($url);
    $self->handle_command('set_Speed',3000);
    $self->handle_command('wait_for_element_visible_ok','st-newpage-pagename-edit',30000);
    $self->handle_command('type_ok','st-newpage-pagename-edit',$pagename);
    $self->handle_command('wait_for_element_visible_ok','st-save-button-link',5000);
    $self->handle_command('set_Speed',0);
    st_pause_click($self, 8000,'st-save-button-link','andWait');
    $self->handle_command('pause_ok',8000);
}

=head2 st_update_wikipage ( $workspace, $page, $content) 

Goes to a wiki page, clicks edit, types in $content, clicks save

=cut

sub st_update_wikipage {
    my $pause = 2000;
    my ($self, $workspace, $page, $content)  = @_;
    my $url = '/' . $workspace . '/?'  . $page;
           
    $self->{selenium}->open_ok($url);
    $self->handle_command('wait_for_element_visible_ok', 'st-edit-button-link', 30000);
    $self->handle_command('click_ok', 'st-edit-button-link');
    $self->handle_command('wait_for_element_present_ok','//a[contains(@class,"cke_button_wikitext")]',5000);
    $self->handle_command('click_ok','//a[contains(@class,"cke_button_wikitext")]');
    $self->handle_command('wait_for_element_present_ok','//textarea[contains(@class,"cke_source")]',5000);
    $self->handle_command('type_ok','//textarea[contains(@class,"cke_source")]',$content);
    $self->handle_command('type_ok','//textarea[contains(@class,"cke_source")]',$content);
    $self->handle_command('type_ok','//textarea[contains(@class,"cke_source")]',$content);
    $self->handle_command('wait_for_element_visible_ok','st-save-button-link',5000);
    $self->handle_command('click_and_wait','st-save-button-link');
}


=head2 st_add_page_tag ($url, $page, @tags)

Adds one (or more) tags to a wikipage through the GUI.

First goes to server/$url (url should include workspace)

The page must exist in order to have a tag added.

=cut

sub st_add_page_tag {
   my ($self, $url, @tags) = @_;
   $self->handle_command('open_ok',$url);
   $self->handle_command('set_Speed',2000);
   $self->handle_command('wait_for_element_visible_ok','st-pagetools-email', 30000);
   $self->handle_command('wait_for_element_visible_ok','link=Add Tag',30000);
   foreach my $tag (@tags) {
       $self->handle_command('click_ok','link=Add Tag');
       $self->handle_command('wait_for_element_visible_ok','st-tags-field',30000);
       $self->handle_command('type_ok', 'st-tags-field', $tag);
       $self->handle_command('wait_for_element_visible_ok', 'st-tags-plusbutton-link', 30000);
       $self->handle_command('click_ok','st-tags-plusbutton-link');
       $self->handle_command('wait_for_element_visible_ok','link='.$tag, 30000);
   }
   $self->handle_command('set_Speed',0);
}


=head2 st_comment_on_page ($workspace, $url, $comment)

Opens up a specific page via $url, which should be of the form:

/workspace/?page OR /workspace/index.cgi?page

clicks the comment button and leaves your note.

=cut

sub st_comment_on_page {
    my ($self, $url, $comment) = @_;
    my $commentbutton = '//li[@id=\'st-comment-button\']';
    my $commentlink = $commentbutton . '/a';
    my $commentarea = '//textarea[@name="comment"]';
    my $commentsave = '//div[@class="comment"]//a[contains(@class,"saveButton")]';
    $self->handle_command('set_Speed',2000);
    $self->handle_command('open_ok', $url);  
    $self->handle_command('wait_for_element_visible_ok',$commentbutton, 5000);
    $self->handle_command('click_ok',$commentlink);
    $self->handle_command('wait_for_element_visible_ok',$commentarea,10000);
    $self->handle_command('type_ok', $commentarea,$comment);
    $self->handle_command('wait_for_element_present_ok',$commentsave,5000);
    $self->handle_command('click_ok',$commentsave);
    $self->handle_command('set_Speed',0);
}   

=head2 st_edit_page ($workspace, $page, $text)

Opens up a specific page via $url, which should be of the form:

/workspace?page or /workspace/index.cgi?page

Then edits it and types the text you suggest

=cut

sub st_edit_page {
  my ($self, $url, $content) = @_;
  $self->handle_command('open_ok',  $url); 
  $self->handle_command('wait_for_element_visible_ok', 'st-edit-button-link', 30000);  
  $self->handle_command('click_ok','st-edit-button-link');
  $self->handle_command('wait_for_element_present_ok','//a[contains(@class,"cke_button_wikitext")]',5000);
  $self->handle_command('click_ok','//a[contains(@class,"cke_button_wikitext")]');
  $self->handle_command('wait_for_element_present_ok','//textarea[contains(@class,"cke_source")]',5000);
  $self->handle_command('type_ok','//textarea[contains(@class,"cke_source")]',$content);
  $self->handle_command('wait_for_element_visible_ok','st-save-button-link',5000);
  $self->handle_command('click_and_wait','st-save-button-link');
}


=head2 st_email_page ($self, $url, $email_address) 

Emails a page

=cut

sub st_email_page {
    my ($self, $url, $email) = @_;
    $self->handle_command('open_ok',$url);
    $self->handle_command('wait_for_element_visible_ok','st-pagetools-email', 30000);
    $self->handle_command('pause_ok', 2000);
    $self->handle_command('click_ok','st-pagetools-email');
    $self->handle_command('wait_for_element_visible_ok','st-email-lightbox', 30000);
    $self->handle_command('wait_for_element_visible_ok','email_recipient', 30000);
    $self->handle_command('type_ok', 'email_recipient', $email);
    $self->handle_command('wait_for_element_visible_ok','email_add', 30000);
    $self->handle_command('click_ok', 'email_add');
    $self->handle_command('text_like', 'email_page_user_choices', $email);
    $self->handle_command('wait_for_element_visible_ok','email_send', 30000);
    $self->handle_command('click_ok', 'email_send');
    $self->handle_command('wait_for_element_not_visible_ok', 'st-email-lightbox',30000);
}

=head2 st_search( $search_term, $expected_result_title )

Performs a search, and then validates the result page has the correct title.

=cut


sub st_search {
    my ($self, $searchFor, $resultTitle) = @_;
    my $contentDiv = '//div[@id=\'content\']';

    $self->handle_command('wait_for_element_visible_ok','st-search-term',5000);
    $self->handle_command('wait_for_element_visible_ok','st-search-submit',5000);
    $self->handle_command('type_ok','st-search-term',$searchFor);
    $self->handle_command('click_and_wait','st-search-submit');
    $self->handle_command('text_like',$contentDiv,$resultTitle );
    
}

=head2 st_result( $expected_result )

Validates that the search result content contains a correct result.

=cut

sub st_result {
    my ($self, $result) = @_;
    my $contentDiv = '//div[@id=\'content\']';

    $self->handle_command('text_like',$contentDiv,$result );
}

=head2 st_match_text ($match, $variable_name) 

does a text_like on $match and sticks the results in $variable

=cut

sub st_match_text {
    my ($self, $match, $variable) = @_;
   
    my $text = $self->{selenium}->get_text('//body');
    if ($text=~ qr/$match/) {
        $self->{$variable} = $1;
        ok(1, 'st_match_text matched $match');
    } else {
        ok(0,'st_match_text failed to match the parens in $match');
        print "text is \n ( $text ) \n";
    }
}

=head2 st_submit()

Submits the current form

=cut

sub st_submit {
    my ($self) = @_;

    $self->click_and_wait(q{//input[@value='Submit']}, 'click submit button');
}

=head2 st_message()

Verifies an error or message appears.

=cut

sub st_message {
    my ($self, $message) = @_;

    $self->text_like(q{errors-and-messages},
                     $self->quote_as_regex($message));
}


=head2 st_stop_webserver

Stops the webserver.
    
=cut

sub st_stop_webserver {
    my ($self) = @_;
    if ($self->_is_appliance) {
        diag "sudo /usr/sbin/st-appliance-ctl stop";
        my $output = `sudo /usr/sbin/st-appliance-ctl stop`;
        ok($output=~/stop/, 'nlw-psgi is stopped');
    }
    else {
        diag "st_stop_webserver: nlwctl stop -1";
        _run_command("nlwctl stop -1", "ignore output");
    }
    $self->pause(5000);
}

=head2 st_start_webserver 
   
   Starts the webserver

=cut

sub st_start_webserver {
    my ($self) = @_;
    if ($self->_is_appliance) {
        # Appliance-specific
        diag "sudo /usr/sbin/st-appliance-ctl start";
        my $output = `sudo /usr/sbin/st-appliance-ctl start`;
        ok($output=~/start/, 'nlw-psgi is started');
    }
    else {
        diag "st_start_webserver: nlwctl -1 start";
        _run_command("nlwctl -1 start", 'ignore output');
    }
    $self->pause(5000);
}



=head2 st_watch_page( $watch_on, $page_name, $verify_only )

Adds/removes a page to the watchlist.

If the first argument is true, the page will be added to the watchlist.
If the first argument is false, it will be removed from the watchlist.

If the second argument is not specified, it is assumed that the browser
is already open to a wiki page, and the opened page should be watched.

If the second argument is supplied, it is assumed that the browser
is on the watchlist page, and only the given page name should be watched.

If the 3rd argument is true, only checks will be performed as to whether
the specified page is watched or not.

=cut

sub st_watch_page {
    my ($self, $watch_on, $page_name, $verify_only) = @_;
    my $expected_watch = $watch_on ? 'on' : 'off';
    my $watch_re = qr/watch-$expected_watch(?:-list)?\.gif$/;
 
    #which aspect of the HTML id we will look at to determine
    #If the correct value is set
    my $s3_id_type = 'title'; # legacy
    
    my $s3_expected = $watch_on ? 'Stop Watching' : 'Watch';
    my $is_s3 = 1; #legacy
    $page_name = '' if $page_name and $page_name =~ /^#/; # ignore comments
    $verify_only = '' if $verify_only and $verify_only =~ /^#/; # ignore comments

    unless ($page_name) {
        #my $html_type = $is_s3 ? "a" : "img";
            
        return $self->_watch_page_xpath("//li[\@id='st-watchlist-indicator']/a", 
                                        $watch_re, $verify_only, $s3_expected, $is_s3, $s3_id_type);
    }

    # A page is specified, so assume we're on the watchlist page
    # We need to find which row the page we're interested in is in
    my $sel = $self->{selenium};
    my $row = 2; # starts at 1, which is the table header
    my $found_page = 0;
    (my $short_name = lc($page_name)) =~ s/\s/_/g;
    
    if ($is_s3) {
        my $xpath = '//a[@id=' . "'st-watchlist-indicator-$short_name" . "']";
        $xpath = qq{$xpath};
        my $expected_list = $watch_on ? 'Stop watching' : 'Watch';
        my $title= '';
        eval { $title = $sel->get_attribute("$xpath/\@title") };
        if (length($title)>0) {
            my $expected;
            if (defined($page_name) and length($page_name)>0) {
               $expected = $expected_list; # Expected title of the watch page for listview  
            } else { 
               $expected = $expected_watch; #Expected title of the watch page for 
            }
            $self->_watch_page_xpath($xpath, $watch_re, $verify_only, $expected, $is_s3, $s3_id_type);
            ok 1, "st-watch-page $expected_list - $page_name"
        } else {
            ok 0, "Failed to find watch icon\n";
        }
    } else {
        while (1) {
            my $xpath = qq{//div[\@id='st-watchlist-content']/div[$row]/div[2]/img}; 
            my $alt;
            eval { $alt = $sel->get_attribute("$xpath/\@alt") };
            last unless $alt;
            if ($alt eq $short_name) {
                $self->_watch_page_xpath($xpath, $watch_re);
                $found_page++;
                last;
            }
            else {
                diag "Looking at watchlist for ($short_name), found ($alt)\n";
            }
            $row++;
        }
        ok $found_page, "st-watch-page $watch_on - $page_name"
            unless $ENV{ST_WF_TEST};
    }
}

sub _watch_page_xpath {
    my ($self, $xpath, $watch_re, $verify_only, $s3_expected, $is_s3, $id_type) = @_;
    my $sel = $self->{selenium};
    
    my $xpath_src = $is_s3 ? "$xpath/\@$id_type" : "$xpath/\@src";
    my $src = $sel->get_attribute($xpath_src);
    
    if ($is_s3) {
       #Capitalization is inconsisent for "stop watching" between list view
       #and page view.  Yes, really.
       if ($verify_only or lc($src) eq lc($s3_expected)) {
           is lc($src), lc($s3_expected), "$src - $s3_expected (Searching with $xpath)";
           return;
       }
    } else {
      if ($verify_only or $src=~ $watch_re) {
          like $src, $watch_re, "$xpath - $watch_re";
          return;
      }
    }
    

    $sel->click_ok($xpath, "clicking watch button");
    my $timeout = time + $self->{selenium_timeout} / 1000;
    while(1) {
        my $new_src = $sel->get_attribute($xpath_src);
        my $compare = 0;
        if ($is_s3) {
            $compare = (lc($new_src) eq lc($s3_expected));
        } else {
            $compare = ($new_src =~ $watch_re);
       }        
        
        last if $compare;
        select undef, undef, undef, 0.25; # sleep
        if ($timeout < time) {
            ok 0, 'Timeout waiting for watchlist icon to change';
            last;
        }
    }
}

=head2 st_is_watched( $watch_on, $page_name )

Validates that the current page is or is not on the watchlist.

The logic for the second argument are the same as for st_watch_page() above.

=cut

sub st_is_watched {
    my ($self, $watch_on, $page_name) = @_;
    return $self->st_watch_page($watch_on, $page_name, 'verify only');
}


=head2 st_rm_rf( $command_options )

Runs on command-line rm -Rf command with the supplied options.

Note that this will delete files, directories, and not prompt.  Use at your own risk.

=cut

sub st_rm_rf {
    my $self = shift;
    my $options = shift;
    unless (defined $options) {
        die "parameter required in call to st_rm_rf\n";
    }
    
    _run_command("rm -Rf $options", 'ignore output');
}

=head2 st_ceq_rm( $command_options )

Runs on command-line ceq-rm  command with the supplied options.

Note that this will delete ceqlotron jobs.  Use at your own risk.

=cut

sub st_ceq_rm {
    my $self = shift;
    my $options = shift;
    unless (defined $options) {
        die "parameter required in call to st_ceq_rm\n";
    }
    
    _run_command("ceq-rm $options", 'ignore output');
}

=head2 st_qa_setup_reports 

Run the command-line script st_qa_setup_reports that populates reports in order to test the usage growth report

=cut

sub st_qa_setup_reports {
    _run_command("st-qa-setup-reports",'ignore output');
}

=head2 st_admin( $command_options )

Runs st_admin command line script with the supplied options.

If the export-workspace command is used, I'll attempt to remove any existing
workspace tarballs before running the command.

=cut

sub st_admin {
    my $self    = shift;
    my $options = shift || '';
    my $verify  = shift;
    $verify = $self->quote_as_regex($verify) if $verify;

    # If we're exporting a workspace, attempt to remove the tarball first
    if ($options =~ /export-workspace.+--workspace(?:\s+|=)(\S+)/) {
        my $tarball = "/tmp/$1.1.tar.gz";
        if (-e $tarball) {
            diag "Deleting $tarball\n";
            unlink $tarball;
        }
    }

    # Explode out the command line options to a list.
    my @argv = shellwords($options);

    # Invocations with redirected input *needs* to be done against the shell,
    # but other commands can be done in-process.  Also have to watch out for
    # "st-admin help", which *has* to be shelled out for.
    my ($out, $err) = ($options =~ /<|^\s*-*help|index-workspace/)
        ? _st_admin_shell_out(@argv)
        : _st_admin_in_process(@argv);

    if ($verify) {
        my $combined = $out . $err;
        like $combined, qr/$verify/s, "st-admin $options";
    }
    else {
        diag "st-admin $options";
    }
    diag $err if ($err && ($err ne "\n"));
}

sub _st_admin_in_process {
    my @argv = @_;

    # Override "_exit()" so that we don't exit while running in-process.
    # We *do*, however, want to make sure that we stop whatever we're
    # doing, so throw a fatal exception and get us outta there.
    require Socialtext::CLI;
    no warnings 'redefine';
    local *Socialtext::CLI::_exit = sub { die "\n" };

    # IPC::Run will barf on IO::Scalar's lack of a fileno().  We can safely
    # return undef since it seems IPC::Run ignores it anyway.
    local *IPC::Run::_debug_fd = sub {};

    # clear any in-memory caches that exist, so that we pick up changes that
    # _may_ have been made outside of this process.
    Socialtext::Cache->clear();

    # mark any cached DBI handles as invalid, so that the DB server can safely
    # restart between wikiQtest commands.
    Socialtext::SQL::invalidate_dbh();

    # Set up the real @ARGV so that ST::CLI can do proper logging
    local @ARGV = @argv;

    # Run st-admin in process, capturing STDOUT/STDERR individually.
    #
    # Unfortunately, Test::Output doesn't let us capture them both separately
    # but simultaneously. :(
    my ($out, $err) = ('', '');
    {
        my $fh_out = IO::Scalar->new(\$out);
        my $fh_err = IO::Scalar->new(\$err);
        local *STDOUT = $fh_out;
        local *STDERR = $fh_err;
        eval { Socialtext::CLI->new(argv => \@argv)->run };
        if ($@) { warn $@ };
    }
    return ($out, $err);
}

sub _st_admin_shell_out {
    my @argv = @_;
    my ($in, $out, $err);

    # Doing a shell input redirect requires a bit more effort, so grab the
    # standard command stuff and the redirect bits separately
    my @standard = before { $_ eq '<' } @argv;
    my ($file)   = after  { $_ eq '<' } @argv;
    $in = slurp($file) if ($file);

    # Run the command, capturing output.
    IPC::Run::run ['st-admin', @standard], \$in, \$out, \$err;

    return ($out, $err);
}

#=head2 st_appliance_config($command_options)
#
#Runs st-appliance-config command line script with the supplied options.
#
#=cut

sub st_appliance_config {
    my $self = shift;
    my $options = shift || '';
    my $verify = shift;
    $verify = $self->quote_as_regex($verify) if $verify;
    #ONLY runs on an appliance
    if (!Socialtext::AppConfig->startup_user_is_human_user()) {
       #On An Appliance
       my $str = "sudo st-appliance-config $options";
       diag $str;
       _run_command($str, $verify);
    }
}

=head2 st_ldap( $command_options )

Runs st_bootstrap_openldap command line script with the supplied options.

If the "start" command is used, the OpenLDAP instance is fired off into the
background, which may take a second or two while we wait for it to start.

=cut

sub st_ldap {
    my $self = shift;
    my $options = shift || '';
    my $verify = shift;
    $verify = $self->quote_as_regex($verify) if $verify;

    # If we're starting up an LDAP server, be sure to daemonize it and make
    # sure that it gets fired off into the background on its own.
    if ($options eq 'start') {
        $options .= ' --daemonize';
    }

    diag "st-ldap $options";
    _run_command("st-bootstrap-openldap $options", $verify);
}

=head2 st_ldap_vanilla ($command_options )

Run st_ldap, not st_bootstrap_openldap.

=cut

sub st_ldap_vanilla {
    my $self = shift;
    my $options = shift || '';
    my $verify = shift;
    $verify = $self->quote_as_regex($verify) if $verify;
    diag "st-ldap $options";
    _run_command("st-ldap $options", $verify);
}

=head2 st_config( $command_options )

Runs st_config command line script with the supplied options.

=cut

sub st_config {
    my $self = shift;
    my $options = shift || '';
    my $verify = shift;
    $verify = $self->quote_as_regex($verify) if $verify;

    diag "st-config $options";
    _run_command("st-config $options", $verify);
}

=head2 st_appliance_config_set( $command_options )

Runs `st-appliance-config set $command_options` in-process. Note that multiple
keys and values can be passed, so long as each param is separated by
whitespace.

=cut

sub st_appliance_config_set {
    my $self    = shift;
    my %options = split / +/, shift;

    require Socialtext::Appliance::Config;

    my $config = Socialtext::Appliance::Config->new();
    for my $key ( keys %options ) {
        $config->value( $key, $options{$key} );
    }

    $config->save();
    diag "st-appliance-config set "
        . join( ", ", map { "$_ $options{$_}" } keys %options ) . "\n";
}

=head2 st_admin_export_workspace_ok( $workspace )

Verifies that a workspace tarball was created.

The workspace parameter is optional.

=cut

sub st_admin_export_workspace_ok {
    my $self = shift;
    my $workspace = shift || $self->{workspace};
    my $tarball = "/tmp/$workspace.1.tar.gz";
    ok -e $tarball, "$tarball exists";
}

=head2 st_import_workspace( $options, $verify )

Imports a workspace from a tarball.  If the import is successful,
a test passes, if not, it fails.  The output is checked against
$verify.

C<$options> are passed through to "st-admin import-workspace"

=cut

sub st_import_workspace {
    my $self = shift;
    my $options = shift || '';
    my $verify = $self->quote_as_regex(shift);

    _run_command("st-admin import-workspace $options", $verify);
}

=head2 st_force_confirmation( $email, $password )

Forces confirmation of the supplied email address, and sets the user's
password to the second option.

=cut

sub st_force_confirmation {
    my ($self, $email, $password) = @_;

    require Socialtext::User;
    Socialtext::User->new(email_address => $email)->confirm_email_address();
    $self->st_admin("change-password --email '$email' --password '$password'",
                    'has been changed');
}

=head2 st_open_confirmation_uri

Open the correct url to confirm an email address.

=cut

sub st_open_confirmation_uri {
    my ($self, $email) = @_;

    require Socialtext::User;
    my $uri = Socialtext::User->new(email_address => $email)->confirmation_uri();
    # strip off host part
    $uri =~ s#.+(/nlw/submit/confirm)#$1#;
    $self->{selenium}->open_ok($uri);
}

=head2 st_open_change_password_uri

Open the correct URL to change a User's password.

=cut

sub st_open_change_password_uri {
    my ($self, $email) = @_;

    require Socialtext::User;
    my $user = Socialtext::User->new(email_address => $email);
    my $uri  = $user->password_change_uri;

    # strip off host part
    $uri =~ s#.+(/nlw/submit/confirm)#$1#;
    $self->{selenium}->open_ok($uri);
}

=head2 st_should_be_admin( $email, $should_be )

Clicks the admin check box to for the given user.

=cut

sub st_should_be_admin {
    my ($self, $email, $should_be) = @_;
    my $method = ($should_be ? '' : 'un') . 'check_ok';
    $self->_click_user_row($email, $method, '/td[3]/input');
}

=head2 st_click_reset_password( $email )

Clicks the reset password check box to for the given user.

Also verifies that the checkbox is no longer checked.

=cut

sub st_click_reset_password {
    my ($self, $email, $should_be) = @_;
    my $chk_xpath = $self->_click_user_row($email, 'check_ok', '/td[4]/input');
    ok !$self->is_checked($chk_xpath), 'reset password checkbox not checked';
}

sub type_lookahead_ok {
    die "Deprecated - Please use select-autocompleted-option-ok\n";
}

sub _autocomplete_element {
    my $locator = shift;
    my $element = qq{selenium.browserbot.findElement("$locator")};
    return qq{
        (function(){
            var el = $element;
            var win = el.ownerDocument.defaultView
                ? el.ownerDocument.defaultView
                : el.ownerDocument.parentWindow;
            return win.jQuery(el);
        })()
    };
}

sub _autocomplete_widget {
    my $locator = shift;
    return _autocomplete_element($locator) . ".autocomplete('widget')";
};

sub _autocomplete_search {
    my ($self, $locator, $type) = @_;

    my $el = _autocomplete_element($locator);
    my $widget = _autocomplete_widget($locator);

    # Clear the auto complete
    $self->{selenium}->get_eval(qq{$widget.find("li").remove()});

    # Wait until our element is present
    $self->wait_for_element_present_ok($locator);

    # Search for $type_text
    $self->{selenium}->type_ok($locator, $type);
    $self->{selenium}->get_eval(qq{$el.autocomplete("search", "$type")});

    # Wait for items to be rendered
    $self->wait_for_condition("$widget.find('li').size() > 0", 30000);

    # return the number of li elements
    return $self->get_eval("$widget.find('li').size()");
}

sub _autocomplete_trigger_event {
    my ($self, $locator, $key) = @_;
    my $el = _autocomplete_element($locator);
    my $type = 'keydown.autocomplete';
    $self->{selenium}->get_eval(
        qq{$el.trigger({type:"$type",keyCode:window.jQuery.ui.keyCode.$key})}
    );
}

sub _autocomplete_selected_option {
    my ($self, $locator) = @_;
    my $widget = _autocomplete_widget($locator);
    my $text = $self->get_eval("$widget.find('.ui-state-hover').text()");
    $text =~ s{\s*$}{};
    $text =~ s{^\s*}{};
    return $text;
}

sub _autocomplete_error {
    my ($self, $locator) = @_;
    my $widget = _autocomplete_widget($locator);
    return $self->get_eval("$widget.find('.ui-autocomplete-error').text()")
}

sub has_autocompleted_options_ok {
    my ($self, $locator, $type) = @_;
    my $elements = $self->_autocomplete_search($locator, $type);
    ok !$self->_autocomplete_error($locator), 'has_autocompleted_options';
}

sub has_no_autocompleted_options_ok {
    my ($self, $locator, $type) = @_;
    my $elements = $self->_autocomplete_search($locator, $type);
    is $elements, 1, 'has_autocompleted_options';
    is $self->_autocomplete_error($locator), "No matches for '$type'",
        'has_no_autocompleted_options';
}

sub _autocompleted_option_exists {
    my ($self, $locator, $type, $match) = @_;
    my $elements = $self->_autocomplete_search($locator, $type);

    # Click down until the correct item is selected
    for (1 .. $elements) {
        $self->_autocomplete_trigger_event($locator, 'DOWN');
        if ($match eq $self->_autocomplete_selected_option($locator)) {
            return 1;
        }
    }
    return 0;
}

sub autocompleted_option_exists {
    my ($self, $locator, $type, $match) = @_;
    ok $self->_autocompleted_option_exists($locator, $type, $match),
        "autocompleted_option_exists $match";
}

sub autocompleted_option_not_exists {
    my ($self, $locator, $type, $match) = @_;
    ok !$self->_autocompleted_option_exists($locator, $type, $match),
        "autocompleted_option_not_exists $match";
}

sub select_autocompleted_option_ok {
    my ($self, $locator, $type, $match) = @_;
    $match ||= $type;

    my $elements = $self->_autocomplete_search($locator, $type);

    # Click down until the correct item is selected
    for (1 .. $elements) {
        $self->_autocomplete_trigger_event($locator, 'DOWN');
        last if $match eq $self->_autocomplete_selected_option($locator);
    }

    # Just select the element we're on - this might just be the last match
    $self->_autocomplete_trigger_event($locator, 'ENTER');
    return;
}

sub st_unchecked_ok {
    my ($self, $locator) = @_;
    ok !$self->is_checked($locator), "$locator is not checked";
}

sub st_uneditable_ok {
    my ($self, $locator) = @_;
    ok !$self->is_editable($locator), "$locator is not editable";
}

sub st_mobile_account_select_ok {
    my ($self, $accountdesc) = @_;
    $self->handle_command('open_ok', '/st/m/signals');
    if ($self->_is_wikiwyg()) { 
        $self->wait_for_element_visible_ok($self->{st_mobile_account_select}, 30000);
        $self->wait_for_element_present_ok("link=$accountdesc",30000);
        $self->click_ok("link=$accountdesc");
        $self->wait_for_element_visible_ok("link=$accountdesc");
     } else {
        $self->wait_for_element_visible_ok($self->{st_mobile_account_select}, 30000);
        $self->select_ok($self->{st_mobile_account_select}, "label=" . $accountdesc);
     }
}



=head2 st_check_emergent_signal_wikiwyg_mobile

Sends a signal and waits to see if in the miki ... if and only if you are on a "smart mobile" browser

=cut

sub st_check_emergent_signal_wikiwyg_mobile {
    my ($self) = @_;
    if ( $self->_is_wikiwyg() ) {
        $self->handle_command('Comment', 'Test case: Miki Open global nav has emergent checking');
        $self->handle_command('set', 'emergent_signal','hello %%start_time%% this is an emergent signal');
        $self->handle_command('http-user-pass','%%othermikiuser%%','%%password%%');
        $self->handle_command('post-signal','%%emergent_signal%%');
        $self->handle_command('wait_for_text_present_ok','%%emergent_signal%%', 120000);
    }
}

=head2 st_if_ie_check_mobile_signaltypes

IE contains hard links to display only certain signal types.  Other browsers do not.

=cut


sub st_if_ie_check_mobile_signaltypes {
   my ($self) = @_;
   if (! ($self->_is_wikiwyg()) ) {
      $self->handle_command('wait_for_element_visible_ok','link=Mine','30000'); 
      $self->handle_command('click_and_wait','link=Mine');
      $self->handle_command('text_unlike','//body','%%signal1%%');
      $self->handle_command('click_and_wait','link=All','30000');
      $self->handle_command('wait_for_text_present_ok','%%signal1%%', 30000); 
      $self->handle_command('wait_for_element_visible_ok','link=%%othershortuser%%');
   }
}

sub st_unlike_signal {
    my $self = shift;
    my $signal = shift; # signal ID
    my $user  = shift; # username or email

    $self->delete("/data/signals/$signal/likes/$user");
    $self->code_is(204);
    ok(!$@, "$user unlikes $signal");
}

sub st_like_signal {
    my $self = shift;
    my $signal = shift; # signal ID
    my $user  = shift; # username or email

    $self->put("/data/signals/$signal/likes/$user");
    $self->code_is(204);
    ok(!$@, "$user likes $signal");
}

sub _click_user_row {
    my ($self, $email, $method_name, $click_col) = @_;
    my $sel = $self->{selenium};

    my $row = 1;
    my $chk_xpath;
    while(1) {
        $row++;
        my $row_email = $sel->get_text("//tbody/tr[$row]/td[2]");
        diag "row=$row email=($row_email)";
        last unless $row_email;
        next unless $email and $row_email =~ /\Q$email\E/;
        $chk_xpath = "//tbody/tr[$row]$click_col";
        
        $sel->$method_name($chk_xpath);
        $self->click_and_wait('link=Save');
        $sel->text_like('content', qr/\QChanges Saved\E/);
        return $chk_xpath;
    }
    ok 0, "Could not find '$email' in the table";
    return;
}

sub _run_command {
    Socialtext::WikiFixture::SocialBase->can('_run_command')->(@_);
}

sub _is_appliance {
    my $self = shift;
    return($self->{browser_url} !~ /:2\d\d\d\d/);
}

=head1 AUTHOR

Luke Closs, C<< <luke.closs at socialtext.com> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-socialtext-editpage at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Socialtext-WikiTest>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Socialtext::WikiFixture::Socialtext

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Socialtext-WikiTest>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Socialtext-WikiTest>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Socialtext-WikiTest>

=item * Search CPAN

L<http://search.cpan.org/dist/Socialtext-WikiTest>

=back

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2006 Luke Closs, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
