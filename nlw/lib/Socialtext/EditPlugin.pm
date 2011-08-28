# @COPYRIGHT@
package Socialtext::EditPlugin;
use 5.12.0;
use warnings;

use base 'Socialtext::Plugin';

use Class::Field qw( const );
use Socialtext::Pages;
use Socialtext::Exceptions qw( data_validation_error );
use Socialtext::l10n qw(loc __);
use Socialtext::Events;
use Socialtext::Log qw(st_log);
use Socialtext::String ();
use Socialtext::JSON qw/decode_json encode_json/;
use Socialtext::PageRevision ();
use Try::Tiny;

const class_id => 'edit';
const class_title => __('class.edit');
const cgi_class => 'Socialtext::Edit::CGI';

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add(action => 'edit');
    $registry->add(action => 'edit_save');
    $registry->add(action => 'lock_page');
    $registry->add(action => 'unlock_page');
    $registry->add(action => 'edit_content');
    $registry->add(action => 'edit_start');
    $registry->add(action => 'edit_cancel');
    $registry->add(action => 'edit_check');
    $registry->add(action => 'edit_check_start');
    $registry->add(action => 'edit_contention_check');
}

sub _validate_pagename_length {
    my $self = shift;
    my $page_name = shift;

    my $id = Socialtext::String::title_to_id($page_name);

    if ( Socialtext::String::MAX_PAGE_ID_LEN < length $id ) {
        my $message = loc("error.page-title-too-long");
        data_validation_error errors => [$message];
    }
    if ( length $id == 0 ) {
        my $message = loc("error.page-title-required");
        data_validation_error errors => [$message];
    }
}

sub _set_page_lock {
    my $self  = shift;
    my $state = shift;

    my $page_name = $self->cgi->page_name;

    $self->_validate_pagename_length($page_name);

    my $page = $self->hub->pages->new_from_name($page_name);

    return $self->to_display($page)
        unless $self->hub->checker->check_permission('lock')
            && $self->hub->current_workspace->allows_page_locking;

    $page->update_lock_status( $state );
    return $self->to_display($page)
}

sub lock_page {
    my $self      = shift;
    return $self->_set_page_lock(1);
}

sub unlock_page {
    my $self      = shift;
    return $self->_set_page_lock(0);
}

sub edit_content {
    my $self = shift;
    my $page_name = $self->cgi->page_name;
    my $content   = $self->cgi->page_body;

    $self->_validate_pagename_length($page_name);

    my $page = $self->hub->pages->new_from_name($page_name);
    my $append_mode = $self->cgi->append_mode || '';

    return $self->to_display($page)
        unless $self->hub->checker->check_permission('edit');

    return $self->_page_locked_screen($page)
        unless $self->hub->checker->can_modify_locked($page);

    if ($self->_there_is_an_edit_contention($page, $self->cgi->revision_id)) {
        unless ($append_mode) {
            $self->_record_edit_contention($page);
            return $self->_edit_contention_screen($page);
        }
    }

    my $rev = $page->edit_rev();
    $rev->edit_summary($self->cgi->edit_summary||'');
    $rev->name($page_name);
    $rev->page_type($self->cgi->page_type||'wiki');

    given ($append_mode) {
        $page->append(\$content) when 'bottom';
        $page->prepend(\$content) when 'top';
        $page->body_ref(\$content);
    }

    if (my @tags = $self->cgi->add_tag) {
        $rev->add_tags(\@tags);
    }

    my $g = $self->hub->pages->ensure_current($page->id);

    my %event = (
        event_class => 'page',
        action => 'edit_save',
        page => $page,
    );

    my @attach = $self->cgi->attachment;
    for my $att_id (@attach) {
        my $att_page;
        if ($att_id =~ /^(.+?):(.+)$/) {
            $att_id = $1;
            $att_page = $2;
        }
        my $att = $self->hub->attachments->load(id => $att_id, page_id => $att_page);
        if ($att->is_temporary) {
            $att->make_permanent(
                page => $page,
                user => $self->hub->current_user
            );
        }
        else {
            $att->clone(page => $page);
        }
    }

    my $signal = $page->store(
        user => $self->hub->current_user,
        signal_edit_summary => scalar($self->cgi->signal_edit_summary),
        signal_edit_to_network => scalar($self->cgi->signal_edit_to_network),
    );

    if ($signal) {
        $event{signal} = $signal;
    }

    Socialtext::Events->Record(\%event);

    return $self->to_display($page);
}

sub edit {
    my $self = shift;

    my $page_name = $self->cgi->page_name;
    $self->_validate_pagename_length($page_name);

    return $self->hub->display->display(1);
}

*edit_save = *save; # grep: sub edit_save
sub save {
    my $self = shift;
    my $original_page_id = $self->cgi->original_page_id
        or
        Socialtext::Exception::DataValidation->throw("no original page id");

    my $subject = $self->cgi->subject || $self->cgi->page_title;
    unless ( defined $subject && length $subject ) {
        Socialtext::Exception::DataValidation->throw(
            errors => [loc('error.no-page-title')] );
    }
    my $page = $self->hub->pages->new_from_name($subject);

    return $self->to_display($page)
        unless $self->hub->checker->check_permission('edit');

    return $self->_page_locked_screen($page)
        unless $self->hub->checker->can_modify_locked($page);

    if ($self->_there_is_an_edit_contention($page, $self->cgi->revision_id)) {
        $self->_record_edit_contention($page);
        return $self->_edit_contention_screen($page);
    }

    my $rev = $page->edit_rev();
    $rev->name($subject); # isn't set by new_from_name($subject) if page exists

    {
        my $body = $self->cgi->page_body;
        unless ( defined $body && length $body ) {
            Socialtext::Exception::DataValidation->throw(
                errors => [loc('error.no-page-body')] );
        }
        $rev->body_ref(\$body);
    }



    my @categories =
      sort keys %{+{map {($_, 1)} split /[\n\r]+/, $self->cgi->header}};
    my @tags =  map { $_ =~ s/(?:^\s+|\s+$)//g; $_; } $self->cgi->add_tag;
    push @categories, @tags;

    $page->update(
        revision            => $self->cgi->revision || 0,
        signal_edit_summary => 1,
        categories => \@categories,
        edit_summary => Socialtext::String::trim($self->cgi->edit_summary||''),
    );
    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_save',
        page => $page,
    });
    return $self->to_display($page);
}

sub _record_edit_contention {
    my $self = shift;
    my $page = shift;

    # record the event.
    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_contention',
        page => $page,
    });

    # log it.
    my $user = $self->hub->current_user;
    my $ws   = $self->hub->current_workspace;
    st_log->info(
        'EDIT_CONTENTION,PAGE,edit_contention,'
        . 'workspace:' . $ws->name . '(' . $ws->workspace_id . '),'
        . 'user:' . $user->email_address . '(' . $user->user_id . '),'
        . 'page:' . $page->id
    );
}

sub _page_locked_screen {
    my $self = shift;
    my $page = shift;

    $self->screen_template('view/page_locked');
    return $self->render_screen(
        page => $page,
        page_body => $self->html_escape($self->cgi->page_body),
        display_title => $page->title,
        header_display_title => $page->title,
    );
}

# Build the edit contention screen
# .RETURN. The HTML for the screen
sub _edit_contention_screen {
    my $self = shift;
    my $page = shift;

    $self->screen_template('view/edit_contention');
    return $self->render_screen(
        page => $page,
        page_body => $self->html_escape($self->cgi->page_body),
        display_title => $page->title,
        header_display_title => $page->title,
        attachment_count => $self->hub->attachments->count,
        revision_count => $page->revision_num,
    );
}

sub _there_is_an_edit_contention {
    my $self = shift;
    my $page = shift;
    my $original_revision = shift;

    return 0 unless defined $original_revision;
    return 0 unless $page->exists;
    return 0 if $page->deleted;
    return 0 if ($page->revision_id eq $original_revision);

    # If the revision ID we got wasn't a valid page revision,
    # there's contention.
    my $orig_rev = try {
        Socialtext::PageRevision->Get(
            hub => $self->hub,
            page_id => $page->page_id,
            revision_id => $original_revision,
        );
    };
    return 1 unless $orig_rev;

    # Do a body_length check first since blobs are lazy-loaded (and relatively
    # expensive).  Revs may entail just a tag change, so checking the body is
    # important.
    my $cur_rev = $page->rev;
    return ($orig_rev->body_length ne $cur_rev->body_length or
            ${$orig_rev->body_ref} ne ${$cur_rev->body_ref});
}

sub to_display {
    my ($self, $page, $edit_mode) = @_;
    my $path = Socialtext::WeblogPlugin->compute_redirection_destination(
        page          => $page,
        caller_action => scalar $self->cgi->caller_action,
    );
    $path .= '#edit' if $edit_mode;
    $self->redirect($path);
}

sub edit_start  { _add_edit_event(shift, 'edit_start' ) }
sub edit_cancel { _add_edit_event(shift, 'edit_cancel') }

sub _add_edit_event {
    my $self        = shift;
    my $action_name = shift;
    my $page_name   = $self->cgi->page_name;

    my $page = $self->hub->pages->new_from_name($page_name);
    return '' unless $self->hub->checker->check_permission('edit');
    return '' unless $self->hub->checker->can_modify_locked($page);
    return unless $page->active;

    eval {
        Socialtext::Events->Record({
            event_class => 'page',
            action => $action_name,
            page => $page,
        });
    };
    warn $@ if $@;
    return '';
}

sub edit_check_start {
    my $self = shift;
    my $page_name   = $self->cgi->page_name;
    my $page = $self->hub->pages->new_from_name($page_name);

    if (my $edit_in_progress = $page->edit_in_progress) {
        # We have a contention; let the client handle it
        return encode_json($edit_in_progress);
    }

    # We have no contention; start editing right away
    $self->edit_start;

    return encode_json({});
}

sub edit_check {
    my $self        = shift;
    my $page_name   = $self->cgi->page_name;

    my $page = $self->hub->pages->new_from_name($page_name);

    return encode_json(
        $page->edit_in_progress || {}
    );
}

# Accepts: Page name and the Revision ID we based our edit on.
# Returns: JSON representation if there has been another save since we edited.
sub edit_contention_check {
    my $self        = shift;
    my $page_name   = $self->cgi->page_name;
    my $page = $self->hub->pages->new_from_name($page_name);

    if ($self->_there_is_an_edit_contention($page, $self->cgi->revision_id)) {
        return encode_json( {
            last_editor => $page->last_editor->to_hash(minimal => 1),
            revision_id => $page->revision_id,
        } );
    }
    else {
        return '{}';
    }
}

package Socialtext::Edit::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'Button';
cgi 'append_mode';
cgi 'caller_action';
cgi 'category';
cgi 'header';
cgi 'revision_id';
cgi 'page_type';
cgi 'original_page_id';
cgi 'page_body';
cgi 'revision';
cgi 'subject';
cgi 'summary';
cgi 'type';
cgi 'page_title';
cgi 'add_tag';
cgi 'attachment';
cgi 'edit_summary';
cgi 'signal_edit_summary';
cgi 'signal_edit_to_network';

1;
