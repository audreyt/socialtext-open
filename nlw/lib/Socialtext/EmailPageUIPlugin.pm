# @COPYRIGHT@
package Socialtext::EmailPageUIPlugin;
use strict;
use warnings;
use Socialtext::JobCreator;
use Class::Field qw( const );
use Readonly;
use Socialtext::l10n '__';

use base 'Socialtext::Plugin';

const class_id => 'email_page_ui';
const class_title => __('class.email_page_ui');
const cgi_class => 'Socialtext::EmailPageUI::CGI';

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add(action => 'email_page_popup');
    $registry->add(action => 'email_page');
}

Readonly my $MAX_USERS_IN_SELECT => 500;
sub email_page_popup {
    my $self = shift;
    my $page = $self->hub->pages->current;
    my $user_count = $self->hub->current_workspace->user_count;
    my $users;
    $users = $self->hub->current_workspace->users
        unless $user_count > $MAX_USERS_IN_SELECT;
    my $sender = $self->hub->current_user;
    $self->send_email_popup($page, $users, $user_count, $sender);
}

# separated out and parameterized from action so it can
# be called when there are error conditions
# XXX croak without page, addresses and sender
sub send_email_popup {
    my $self = shift;
    my ($page, $users, $user_count, $sender, $address_choices, $error, $note) = @_;
    $error ||= '';

    die "Can't email spreadsheets yet" if $page->is_spreadsheet;

    $self->template_process('popup/email_page',
        error        => $error,
        page         => $page,
        user_count   => $user_count,
        users        => $users,
        choices      => $address_choices,
        sending_user => $sender,
        note         => $note,
        $self->hub->helpers->global_template_vars,
    );
}

sub email_page {
    my $self = shift;

    unless ( $self->hub->checker->check_permission('email_out') ) {
        return $self->template_process('close_window.html');
    }

    my $subject = $self->cgi->email_page_subject;
    my $user_source = [$self->cgi->email_page_user_source];
    my $user_destination = [$self->cgi->email_page_user_choices];
    my $note = $self->cgi->email_page_add_note;
    my $use_intro = $self->cgi->email_page_add_note_check;
    my $attachments_p = $self->cgi->email_page_keep_attachments;
    my $page_name = $self->cgi->page_name;
    my $send_copy = $self->cgi->email_page_send_copy;

    my $page = $self->hub->pages->new_from_name($page_name);
    $note = '' unless $use_intro;

    Socialtext::JobCreator->send_page_email(
        page_id => $page->id,
        workspace_id => $self->hub->current_workspace->workspace_id,
        email_args => {
            from => $self->hub->current_user->email_address,
            to => $user_destination,
            subject => $subject,
            body_intro => $note . "\n\n",
            include_attachments => $attachments_p,
            send_copy => $send_copy
        }
    );
    $self->template_process('close_window.html');
}

package Socialtext::EmailPageUI::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'email_page_subject';
cgi 'email_page_user_choices';
cgi 'email_page_user_source';
cgi 'email_page_cc';
cgi 'email_page_add_note';
cgi 'email_page_keep_attachments';
cgi 'page_name';
cgi 'email_page_add_note_check';
cgi 'email_page_send_copy';

1;
