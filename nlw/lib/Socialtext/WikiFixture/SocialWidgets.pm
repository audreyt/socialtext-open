# @COPYRIGHT@
package Socialtext::WikiFixture::SocialWidgets;
use strict;
use warnings;
use base 'Socialtext::WikiFixture::Socialtext';
use Test::More;
use Socialtext::URI;
use Cwd;

=head1 NAME

Socialtext::WikiFixture::SocialWidgets - Test the Widgets using Selenium

=cut

our $VERSION = '0.01';
our $speed = '2000';

=head1 DESCRIPTION

This module is a subclass of Socialtext::WikiFixture::Socialtext and includes
extra commands specifically for testing the Socialtext Widgets (gadgets) containers.

=head1 FUNCTIONS

=head2 new( %opts )

Create a new fixture object. The same options as 
Socialtext::WikiFixture::Socialtext are required except that no workspace is required:

=over 4

=item username

Mandatory - the username to login to the wiki with.

=item password 

Mandatory - the password to login to the wiki with.

=back

=head2 init()

Initializes the object, and logs into the Socialtext server.

=cut

sub init {
    my ($self) = @_;
    $self->{mandatory_args} = [qw(username password)];
    $self->{workspace} ||= "test-data";
    $self->{_widgets}={};
    $self->SUPER::init;
}

=head2 st_empty_container ( )

Navigates to and empties the Dashboard.

=cut
sub st_empty_container { 
    my ($self) = @_;
    my $location = '/st/dashboard?clear=1';
    eval {
        $self->{selenium}->open($location);
        $self->{selenium}->wait_for_page_to_load(30000);
        my $widgetlist = $self->{selenium}->get_value("id=widgetList");
        diag "Widgets after empty: $widgetlist\n"; 
    };
    diag $@ if $@;
    ok( !$@, 'st_empty_container' );
}

=head2 st_reset_container ( )

Resets the current container to default contehnts using the action=reset_container parameter. 
You should navigate to the container URL using normal Selenese test command like "open"

=cut
sub st_reset_container {
    my ($self) = @_;
    my $location = Socialtext::URI::uri(
        path => '/st/dashboard', query => { reset => 1 },
    );
    eval {
        $self->{selenium}->open($location);
        $self->{selenium}->wait_for_page_to_load(10000);
    };
    ok( !$@, 'st_reset_container' );
     
}

=head2 st_add_widget ( widgetpath, logical_name )

Adds a widget to the container. The widget is identified with the widgetpath parameter
and is the same value that is used by the file parameter in the add_widget action.

The logical_name parameter is the logical name that is assigned to this instance of the
widget. All future references to this widget will be made using this logical name. In
addition, the logical name can be used as a wikitest substitution var (%%logical_name%%)
whose value is the id of the widget (ie the value of __MODULE_ID__)

3rd Party Hosted widgets are not yet supported.

=cut

sub st_add_widget {
    my ($self, $widgetpath, $logical) = @_;

    # backwards compat:
    $widgetpath = "file:$widgetpath" unless $widgetpath =~ m{^\w+:};

    my $location = Socialtext::URI::uri(
        path => '/st/dashboard',
        query => {
            add_widget => 1,
            src => $widgetpath,
        },
    );
    eval {
        my @widgetsbefore = $self->_getWidgetList;
        $self->{selenium}->open($location);
        $self->{selenium}->wait_for_page_to_load(10000);
        my @widgetsafter = $self->_getWidgetList;
        my @newwidgets = $self->_listDiff(\@widgetsafter, \@widgetsbefore);
        $self->{_widgets}{$logical} = $newwidgets[0];
        $self->set($logical, $newwidgets[0]); # Set a varname for %%substitution%% 
        diag "Named this widget '$logical': ".$self->{_widgets}{$logical}."\n";
    };
    ok( !$@, "st-add-widget" );
}

=head2 st_name_widget ( position, logical_name )

Assigns a name to the widget in the container which is at the given position. This
is useful for precooked containers where specific widgets are always placed in a specific
order. The position parameter is used to match against the insertion order in the 
yaml file describing this container or the order in which the widget was installed.

The position is 1-based (1st widget matches position, etc). 

The logical_name parameter is the logical name that is assigned to this instance of the
widget. All future references to this widget will be made using this logical name. In
addition, the logical name can be used as a wikitest substitution var (%%logical_name%%)
whose value is the id of the widget (ie the value of __MODULE_ID__)
 

=cut

sub st_name_widget {
    my ($self, $position, $logical) = @_;
    diag "Called st_name_widget with position '$position' and name '$logical'. Sleeping 5. "."\n";
    sleep(5);
    eval {
        my @widgetlist = $self->_getWidgetList;
        $self->{_widgets}{$logical} = $widgetlist[$position-1];
        $self->set($logical, $widgetlist[$position-1]); # Set a varname for %%substitution%% 
        diag "Named this widget '$logical': ".$self->{_widgets}{$logical}."\n";
    };
    ok( !$@, "st-name-widget");
}

=head2 st_minimize_widget ( logical_name )

This clicks on the minimize button for the widget with the logical name given. This
also "restores" the widget to original size if the widget is already minimized.

This assumes that the currently selected frame is the "parent" container frame.

=cut

sub st_minimize_widget {
    my ($self, $logical) = @_;
    eval {
        my $widget = $self->{_widgets}{$logical};
        $self->{selenium}->click("xpath=//div[\@id='$widget']//img[\@id='st-dashboard-minimize']");
    };
    ok( !$@, "st-minimize-widget" );
}

=head2 st_remove_widget ( logical_name )

This clicks on the remove button for the widget with the logical name given. 

This assumes that the currently selected frame is the "parent" container frame.

=cut

sub st_remove_widget {
    my ($self, $logical) = @_;
    eval {
        my $widget = $self->{_widgets}{$logical};
        # This removes from the javascript container - but not from the 
        # widgetList element in the page
        $self->{selenium}->click("xpath=//div[\@id='$widget']//img[\@id='st-dashboard-close']");
        $self->{selenium}->pause(2000);
        delete($self->{_widgets}{$logical});
    };
    ok ( !$@, "st-remove-widget" );
}

=head2 st_widget_settings ( logical_name )

This clicks on the settings button for the widget with the logical name given. 

This assumes that the currently selected frame is the "parent" container frame.

=cut
sub st_widget_settings {
    my ($self, $logical) = @_;
    eval {
        my $widget = $self->{_widgets}{$logical};
        my $xpath = "xpath=//a\[\@id='gadget-" . $widget . "-settings'\]";
        diag "Clicking $xpath";
        $self->{selenium}->click("$xpath");
    };
    ok( !$@, "st-widget-settings" );
}


=head2 st_cycle_network_select

  On /st/signals loops through the network-select dropdown to trigger javascript events

=cut

sub st_cycle_network_select {
    my ($self, $numelements) = @_;
    $self->handle_command('wait_for_element_visible_ok','network-select','30000'); 
    $self->handle_command('pause',3000);
    for (my $idx=0; $idx<$numelements;$idx++) {
        $self->handle_command('pause',3000);
        $self->handle_command('select_ok','network-select',"index=$idx");    
    }
    $self->handle_command('select_ok','network-select','index=0');
    $self->handle_command('pause',3000);     
}

=head2 st_widget_title_like ( logical_name, regex )

This performs a regex text match on the title of the widget (outside the iframe) with the 
given logical name.

This assumes that the currently selected frame is the "parent" container frame.

=cut

sub st_widget_title_like {
    my ($self, $logical, $opt1) = @_;
    eval {
        $self->{selenium}->text_like_ok("//span[\@class='widgetHeaderTitleText' and \@id='gadget-".$self->{_widgets}{$logical}."-title-text']", $opt1);
    };
    ok( !$@, "st-widget-title-like" );

}

=head2 st_widget_body_like ( logical_name, regex )

This performs a regex text match on the body (body element inside the iframe) of the widget 
with the given logical name.

This assumes that the currently selected frame is the "parent" container frame.

=cut
sub st_widget_body_like {
    my ($self, $logical, $opt1) = @_;
    eval {
        $self->{selenium}->select_frame('xpath=//iframe[@id="'.$self->{_widgets}{$logical}.'-iframe"]');
        $self->{selenium}->text_like('//body', $opt1);
        $self->{selenium}->select_frame("relative=top");
    };
    ok( !$@, "st-widget-body-like" );
}

=head2 st_select_widget_frame ( logical_name )

This sets the current frame to the one containing the widget with the logical name given.

It operates like select_frame, and will allow the full set of selenium commands to operate 
within the context of the widget iframe content, rather than the container. 

Note that for other commands in Socialtext::WikiFixture::SocialWidgets to work, a test 
script should call select-frame("reletive=parent") after invoking this to select the
parent (default) container frame.

=cut

sub st_select_widget_frame {
    my ($self, $logical) = @_;
    eval {
        $self->{selenium}->select_frame('xpath=//iframe[@id="'.$self->{_widgets}{$logical}.'-iframe"]');
    };
    #ok( !$@, "st-select-widget-frame");
    # let this return OK even if it fails for now since it is called from
    # non-framed widgets for the moment.
}

=head2 st_wait_for_widget_load (logical_name, timeout )

Waits for a widget's contents to finish loading, waiting for up to timeout milliseconds. Timeout 
defaults to 10000 (10 seconds).

This function waits until the widget has set the gadgets.loaded var to be true. Thus, it is up to
each widget to set this js var, or else the st_wait_for_widget_load function cannot be used with
that widget.

=cut

sub st_wait_for_widget_load {
    my ($self, $logical, $timeout) = @_;
    $timeout = $timeout || 10000;
    eval {
        my $widget=$self->{_widgets}{$logical};
        my $js = <<ENDJS;
        var curwin=selenium.browserbot.getCurrentWindow();
        var myframe=curwin.document.getElementById("$widget-iframe");
        myframe.contentWindow.gadgets.loaded;
ENDJS
        $self->{selenium}->wait_for_condition($js, $timeout);
    };
    diag $@ if $@;
    ok( !$@, "st-wait-for-widget-load");
}

=head2 st_wait_for_all_widgets_load ( timeout )

Waits for all widgets in the container to finish loading, waiting for up to timeout milliseconds. 
Timeout defaults to 10000 (10 seconds).

Note that this command only waits until a widgets' html and javascript are loaded completely - 
it does not wait for the widget to complete any behavior it is programmed to perform after loading.

=cut

sub st_wait_for_all_widgets_load {
    my ($self, $timeout) = @_;
    $timeout = $timeout || 10000;
    eval {
        my $js = <<ENDJS2;
        var curwin=selenium.browserbot.getCurrentWindow();
        var iframeIterator=curwin.document.evaluate('//iframe', curwin.document, null, XPathResult.ORDERED_NODE_ITERATOR_TYPE, null);
        var thisNode = iframeIterator.iterateNext();
        var allLoaded=true;
        while (thisNode) {
            allLoaded = allLoaded && thisNode.contentDocument.loaded;
            thisNode = iframeIterator.iterateNext();
        }    
        allLoaded;
ENDJS2
        $self->{selenium}->wait_for_condition($js, $timeout);
    };
    ok( !$@, "st-wait-for-all-widgets-load");
}

=head2 st_single_widget_in_dashboard

Clears dashboard, adds a single widget in location 1.  

You pass in the link name in add content screen.

=cut

sub st_single_widget_in_dashboard {
    my ($self, $linkid) = @_;
    eval {
        $self->handle_command('st-empty-container');
        $self->handle_command('wait_for_element_visible_ok','link=Add Widget','30000');
        $self->handle_command('click_and_wait','link=Add Widget');
        my $str = '//a[@id=' . "'" . $linkid . "'" . ']';
        $self->handle_command('wait_for_element_visible_ok', $str, 30000);
        $self->handle_command('click_and_wait' ,$str); 
    };
    ok(!$@, 'st_single_widget_in_dashboard' );
}

=head2 st_open_m_signals

Opens the mobile signals page as a function of is_wikiwyg

=cut

sub st_open_m_signals {
    my ($self) = @_;
    my $msignal =  $self->_is_wikiwyg() ? '/st/m/signals' : '/m/signals';
    $self->handle_command('open_ok',$msignal); 
}

=head2 st_send_page_signal ($signaltosend)

The send page signal box does not contain the wikiwkg stuff that the ActivitiesWidget does.

So you don't need as much of the prepare signal function.

=cut

sub st_send_page_signal {
   my ($self, $signaltosend) = @_;

   $self->st_type_signal($signaltosend);
   $self->handle_command('wait_for_element_visible_ok','//a[@class="btn post"]', 5000);
   $self->handle_command('click_ok', '//a[@class="btn post"]');
   $self->handle_command('pause',3000);
   $self->handle_command('set_Speed',0);

}

=head2 st_send_reply

Parameters: You pass in the signal text, followed by 1 if this is a mobile signal 

=cut

sub st_send_reply {
    my ($self, $signaltosend, $is_mobile) = @_;
    $self->handle_command('wait_for_element_visible_ok', '//a[@class="hoverLink replyLink"]', 15000);
    $self->handle_command('click_ok', '//a[@class="hoverLink replyLink"]');

    $self->handle_command('set_Speed',4000);
    if ($self->_is_wikiwyg() ) { #wikiwyg
        $self->handle_command('wait_for_element_visible_ok', '//div[@class="replies"]//iframe[@name="signalFrame"]', 15000);
        $self->handle_command('selectFrame', '//div[@class="replies"]//iframe[@name="signalFrame"]');
        $self->handle_command('click_ok' ,'//body', $signaltosend);
        $self->handle_command('type_ok' ,'//body', $signaltosend);
        $self->handle_command('select-frame' ,'relative=parent');
     } else { #IE. When IE is driven by Selenium, we start it without wikiwyg
         my $textbox_name;
         if ($is_mobile) {
             $textbox_name = 'st-signal-text';
         } else {
             $textbox_name = 'wikiwyg_wikitext_textarea';
         }
         $self->handle_command('wait_for_element_visible_ok','//div[@class="wikiwyg"][last()]', 15000);
         $self->handle_command('click_ok','//div[@class="wikiwyg"][last()]');
         $self->handle_command('wait_for_element_visible_ok',$textbox_name, 15000);
         $self->handle_command('type_ok',$textbox_name,$signaltosend);
    }
    
    $self->handle_command('wait_for_element_visible_ok','//a[@class="btn post postReply"]', 5000);
    $self->handle_command('click_ok', '//a[@class="btn post postReply"]');
    $self->handle_command('set_Speed',0);
}

=head2 st_type_signal 

Parameters: You pass in the signal text, followed by 1 if this is a mobile signal 

=cut

sub st_type_signal {
    my ($self, $signaltosend, $is_mobile) = @_;
    $self->handle_command('set_Speed',4000);
   
    if ($self->_is_wikiwyg() ) { #wikiwyg
        $self->handle_command('wait_for_element_visible_ok', 'signalFrame', 15000);
        $self->handle_command('selectFrame', 'signalFrame');
        $self->handle_command('type_ok' ,'//body', $signaltosend);
        $self->handle_command('select-frame' ,'relative=parent');
     } else { #IE. When IE is driven by Selenium, we start it without wikiwyg
         my $textbox_name;
         if ($is_mobile) {
             $textbox_name = 'st-signal-text';
         } else {
             $textbox_name = 'wikiwyg_wikitext_textarea';
         }
         $self->handle_command('wait_for_element_visible_ok',$textbox_name, 15000);
         $self->handle_command('type_ok',$textbox_name,$signaltosend);
    }
}

=head2 st_prepare_signal_within_activities_widget

Parameters: You pass in the signal text and private flag.  The signal is
readied, but not sent.  Used for testing private signal cancel.
PostCondition: Signal is sent,frame focus remains on widget

=cut

sub st_prepare_signal_within_activities_widget {
    my ($self, $signaltosend, $private) = @_;
    # The next two commands are REQUIRED to expose either the signalFrame or
    # the wikiwyg_wikitext_textarea before sending the signal
    $self->handle_command('wait_for_element_present_ok', '//div[@class=' . "'mainWikiwyg setupWikiwyg wikiwyg']", 15000);
    $self->handle_command('click_ok', '//div[@class=' . "'mainWikiwyg setupWikiwyg wikiwyg']");

    $self->st_type_signal($signaltosend);

    if ($private) {
        # use click_ok - JS does not see check_ok
        $self->handle_command('click_ok', '//input[@class=' . "'toggle-private']");
        $self->handle_command('is_checked_ok', '//input[@class=' . "'toggle-private']");
    }
    $self->handle_command('set_Speed',0);
}

=head2 st_send_signal_in_activities_widget

Parameters: You pass in the signal text and optional private flag

=cut

sub st_send_signal_in_activities_widget {
    my ($self, $signaltosend, $private) = @_;
    $self->st_prepare_signal_within_activities_widget($signaltosend, $private);
    $self->handle_command('wait_for_element_visible_ok','//a[@class="btn post"]', 5000);
    $self->handle_command('click_ok', '//a[@class="btn post"]');
    $self->handle_command('pause',3000); 
}

=head2 st_send_signal_via_activities_widget 

Precondition: Open to page with a named activities widget.
Precondition: Frame focus should be the page.
Parameters: You pass in the activities widget name, signal text, private flag
PostCondition: Signal is sent, Frame focus is back to entire dashboard

Private flag only makes sense if the widget being used has a toggle-private element.

=cut

sub st_send_signal_via_activities_widget {
    my ($self, $widgetname, $signaltosend, $private) = @_;
    eval {
        $self->st_send_signal_in_activities_widget($signaltosend, $private);
    };
    ok(!$@, 'st_send_signal_via_activities_widget');
}


=head2 st_verify_text_within_activities_widget ($self, $texttofind)

Precondition: Activities widget is selected frame
PostCondition: Text is verfied (or not), frame focus remains on activities widget

=cut

sub st_verify_text_within_activities_widget {
    my ($self, $texttofind) = @_;
    $self->handle_command('pause', 3000);
    #If is regexp,
    if ($texttofind=~/^qr\//) {
        $self->handle_command('text_like','//body', $texttofind);
    } else {
        $self->handle_command('wait_for_text_present_ok', $texttofind);
    }
}   


=head2 st_verify_text_in_activities_widget ($self, $widgetname, $texttofind)

Precondition: Open to container with a named activities widget.
Precondition: Frame focus should be the entire page
Parameters: You pass in the activties widget name, text to look for
PostCondition: Text is verified (or not), Frame focus is back to entire page

=cut

sub st_verify_text_in_activities_widget {
    my ($self, $widgetname, $texttofind) = @_;
    eval {
        $self->st_verify_text_within_activities_widget($texttofind);
    };
    ok(!$@, 'st_verify_text_in_activities_widget');
}

=head2 st_text_unlike_in_activities_widget ($self, $widgetname, $betternotfindit)

Precondition: open to container with a named activities widget
Precondition: Frame focus should be entire page
Parameters: You pass in activities widget name, text to not find
Postcondition: Text is unverified (or not), Frame focus is back to entire page

=cut

sub st_text_unlike_in_activities_widget  {
    my ($self, $widgetname, $notpresent) = @_;
    eval {
        $self->handle_command('text_unlike','//body', $notpresent);
    };
    ok(!$@, 'st_text_unlike_in_activities_widget');
}


=head2 st_element_not_present_in_activities_widget

Precondition: open to container with a named activities widget
Precondition: Frame focus should be entire page
Parameters: You paass in the activties widget name, link to look for
PostCondition: link is found  (or not), Frame focus is back to entire page

=cut

sub st_element_not_present_in_activities_widget {
    my ($self, $widgetname, $linktofind) = @_;
    eval {
        $self->handle_command('st-select-widget-frame', $widgetname);
        $self->handle_command('pause', 3000);
        $self->handle_command('wait_for_element_not_present_ok', $linktofind);
        $self->handle_command('select-frame', 'relative=parent');
    };
    ok(!$@, 'st-element-not-present-in-activities-widget');
}


=head2 st_verify_link_in_activities_wdiget

Precondition: open to container with a named activities widget
Precondition: Frame focus should be entire page
Parameters: You paass in the activties widget name, link to look for
PostCondition: link is found  (or not), Frame focus is back to entire page

=cut

sub st_verify_link_in_activities_widget {
    my ($self, $widgetname, $linktofind) = @_;
    eval {
        $self->handle_command('st-select-widget-frame', $widgetname);
        $self->handle_command('pause', 3000);
        $self->handle_command('wait_for_element_visible_ok', $linktofind);
        $self->handle_command('select-frame', 'relative=parent');
    };
    ok(!$@, 'st-verify-link-in-activities-widget');
}
      

=head2 st_create_group ($groupname, $groupdesc, $radiotype)

Radiotype should be self-join-radio or private-radio

=cut

sub st_create_group {
    my ($self, $groupname, $groupdesc, $radiotype) = @_;
    $self->handle_command('comment',"st_create_group called with params '$groupname','$groupdesc','$radiotype'");
    $self->handle_command('set_Speed',4000);
    $self->handle_command('wait_for_element_present_ok','link=Create Group...',30000);
    $self->handle_command('click_ok','link=Create Group...');
    $self->handle_command('wait_for_element_visible_ok','st-create-group-next', 30000);
    $self->handle_command('wait_for_element_visible_ok', $radiotype);
    $self->handle_command('check_ok', $radiotype);
    $self->handle_command('click_ok','st-create-group-next');
    $self->handle_command('wait_for_element_not_present_ok','st-create-group-next', 30000);
    $self->handle_command('pause','8000');
    $self->handle_command('text_like','//body','Create a Group');
    $self->handle_command('st-name-widget', 1,'create_group');
    $self->handle_command('st-select-widget-frame','create_group');
    $self->handle_command('wait_for_element_visible_ok','name', 30000);
    $self->handle_command('wait_for_element_visible_ok','description', 30000);
    $self->handle_command('type_ok','name',$groupname);
    $self->handle_command('type_ok','description',$groupdesc);
    $self->handle_command('select-frame','relative=parent');
    $self->handle_command('set_Speed',0);
    $self->handle_command('comment','end of st_create_group.  Final create has not yet been clicked');
}

=head2 st_find_user ( $user_id, optional $label ) 

Pass in a unique value for the user before the at sign, and selenium will 
search for it and click on that user.

=cut

sub st_find_user {
    my ($self, $user_id, $label) = @_;
    eval {
        $self->handle_command('open_ok','/?action=people;tag=;sortby=best_full_name;limit=20;account_id=all');
        $self->handle_command('pause','10000');
        $self->handle_command('wait_for_element_visible_ok','st-search-action', 30000);
        $self->handle_command('wait_for_element_visible_ok', 'st-search-term', 30000);
        $self->handle_command('wait_for_element_visible_ok', 'st-search-submit', 30000);
        $self->handle_command('select_ok', 'st-search-action', 'Search People:');
        $self->handle_command('type_ok', 'st-search-term', $user_id);
        $self->handle_command('pause', '1000');
        $self->handle_command('click_and_wait', 'st-search-submit');

        $self->handle_command('wait-for-element-visible-ok', "link=$user_id", 30000);
        $self->handle_command('click_and_wait',"link=$user_id");
        $self->handle_command('wait-for-element-visible-ok','new_tag',30000);
    };
    ok(!$@, 'st-find-user');
}   


sub _getWidgetList {
    my ($self) = @_;
    my $widgetlist = $self->{selenium}->get_value("id=widgetList");
    return split(/,/, $widgetlist);
}

sub _containerID {
    my $self = shift;
    return $self->{_container_id} if $self->{_container_id};
    my $sel = $self->{selenium};
    return $self->{_container_id} = $sel->get_value("id=containerID");
}

sub _listDiff {
    my ($self, $a, $b) = @_;
    my @result=();
    #print join(",", @$a). "\n";
    foreach my $val (@$a) {
        push(@result, $val) unless (grep { $_ eq $val } @$b);
    }
    return @result;
}

=head1 AUTHOR

Gabe Wachob, C<< <gabe.wachob at socialtext.com> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-socialtext-editpage at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Socialtext-WikiTest>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Socialtext::WikiFixture::SocialWidgets

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

Copyright 2008 Socialtext, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
