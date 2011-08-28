# @COPYRIGHT@
package Socialtext::CommentUIPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

use Class::Field qw( const field );
use Socialtext::AppConfig;

sub class_id { 'comment_ui' }
const cgi_class => 'Socialtext::CommentUI::CGI';
field 'current_page';

sub register {
    my $self = shift;
    my $registry = shift;
    $self->hub->registry->add(action => 'enter_comment');
    $self->hub->registry->add(action => 'submit_comment');
    $registry->add(wafl => user => 'Socialtext::User::Wafl');
    $registry->add(wafl => date => 'Socialtext::Date::Wafl');
}

sub enter_comment {
    my $self = shift;
    $self->template_process(
        'comment_popup.html',
        $self->hub->helpers->global_template_vars,
    );
}

# XXX this method has no test coverage
sub submit_comment {
    my $self = shift;
    $self->current_page($self->hub->pages->current);
    $self->current_page->add_comment($self->cgi->comment, $self->cgi->signal_comment_to_network)
        if ($self->hub->checker->check_permission('comment')
            && $self->hub->checker->can_modify_locked($self->hub->pages->current));

    $self->template_process('close_window.html',
        before_window_close => q{window.opener.location='} .
            $self->back_to_page .
            q{';},
    );
}

# XXX this method has no test coverage
sub back_to_page {
    my $self = shift;

    my $caller_action = $self->cgi->caller_action;
    $caller_action and $caller_action ne 'display'
        ? Socialtext::AppConfig->script_name . '?action=' .
          $self->cgi->caller_action . ';page_name=' . $self->cgi->page_name . ';r=' . time .
          '#' . $self->current_page->uri
        : Socialtext::AppConfig->script_name . '?'
          . $self->current_page->uri;
}

package Socialtext::CommentUI::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'comment';
cgi 'caller_action';
cgi 'page_name';
cgi 'signal_comment_to_network';

package Socialtext::User::Wafl;

use base 'Socialtext::Formatter::WaflPhrase';

sub html {
    my $self = shift;
    my $email = $self->arguments;

    my $workspace = $self->current_workspace;

    # We might have crufty old wikitext where there's no associated db
    # user in which case we just set it to the email given in the wafl.
    my $user = Socialtext::User->new( email_address => $email );
    my $full_name = $user
        ? $user->best_full_name( workspace => $workspace )
        : $email;

    # XXX the adjustments to the formatter make this call
    # rather messed up
    my $html = eval {
        Socialtext::Formatter::FreeLink->new(
            title   => $full_name,
            hub     => $self->hub,
        )->html;
    } || $self->html_escape($full_name);
    return $html;
}

package Socialtext::Date::Wafl;

use base 'Socialtext::Formatter::WaflPhrase';

sub html {
    my $self = shift;
    my $raw_date = $self->arguments;
    my $date = eval {
        # XXX make more robust with Date::Manip::ParseDate() later.
        $self->hub->timezone->date_local($raw_date);
    };
    $date = $raw_date if $@;
    return $date;
}

1;

