# @COPYRIGHT@
package Socialtext::DuplicatePagePlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

use Class::Field qw( const );
use Socialtext::AppConfig;
use Socialtext::Page;
use Socialtext::Pages;
use Socialtext::Permission qw/ST_EDIT_PERM ST_LOCK_PERM/;
use Socialtext::JSON;
use Socialtext::String ();

# XXX funkity duplication throughout, trying to remove some
# but still plenty left

# XXX: We can remove the necessity of this plugin by implementing this in REST and JS

sub class_id { 'duplicate_page' }
const cgi_class => 'Socialtext::DuplicatePage::CGI';

sub register {
    my $self = shift;
    $self->hub->registry->add(action => 'duplicate_popup');
    $self->hub->registry->add(action => 'duplicate_page');
    $self->hub->registry->add(action => 'copy_to_workspace');
    $self->hub->registry->add(action => 'copy_to_workspace_popup');
}

sub duplicate_popup {
    my $self = shift;
    my %p = @_;
    return encode_json(\%p) if $self->cgi->json;
    return $self->template_process(
        'popup/duplicate',
        %p,
        $self->hub->helpers->global_template_vars,
    );
}

sub copy_to_workspace_popup {
    my $self = shift;
    my %p = @_;

    if ($self->cgi->json) {
        delete $p{target_workspace};
        return encode_json(\%p);
    }

    my $current_workspace = $self->hub->current_workspace;
    my $workspaces = $self->hub->current_user->workspaces(
        exclude => [ $self->hub->current_workspace->workspace_id ],
    );

    $self->template_process(
        'popup/copy_to_workspace',
        workspaces => $workspaces,
        %p,
        $self->hub->helpers->global_template_vars,
    );
}

sub duplicate_page {
    my $self = shift;
    my $new_title = $self->cgi->new_title;
    my $new_id = Socialtext::String::title_to_id($new_title);

    if ( $self->_page_title_bad($new_title) ) {
        return $self->duplicate_popup(
            page_title_bad => 1,
        );
    }
    elsif ( Socialtext::String::MAX_PAGE_ID_LEN < length $new_id ) {
        return $self->duplicate_popup(
            page_title_too_long => 1,
        );
    }
    elsif ( $self->_duplicate( $self->hub->current_workspace ) ) {
        return encode_json({done=>1}) if $self->cgi->json;
        return $self->template_process('close_window.html',
            before_window_close => q{window.opener.location='} .
                Socialtext::AppConfig->script_name . '?' .
                $new_id . q{';},
        );
    }

    return $self->duplicate_popup(
        page_exists => 1,
    );
}

sub copy_to_workspace {
    my $self = shift;
    unless ( $self->cgi->target_workspace_id ) {
        return $self->template_process('close_window.html');
    }

    my $new_title = $self->cgi->new_title;
    my $new_id = Socialtext::String::title_to_id($new_title);

    my $target_ws = Socialtext::Workspace->new( workspace_id => $self->cgi->target_workspace_id );
    if ( $self->_page_title_bad( $new_title ) ) {
        return $self->copy_to_workspace_popup(
            page_title_bad => 1,
        );
    }
    elsif ( Socialtext::String::MAX_PAGE_ID_LEN < length $new_id ) {
        return $self->copy_to_workspace_popup(
            page_title_too_long => 1,
        );
    }
    elsif ( $self->_duplicate($target_ws) ) {
        return encode_json({done=>1}) if $self->cgi->json;
        return $self->template_process('close_window.html');
    }

    return $self->copy_to_workspace_popup(
        page_exists => 1,
        target_workspace => $target_ws,
    );
}

sub mass_copy_to {
    my $self = shift;
    my $destination_name = shift;
    my $prefix = shift;
    my $user = shift;

    my $dest_ws = Socialtext::Workspace->new( name => $destination_name );
    my $dest_main = Socialtext->new;
    $dest_main->load_hub(
        current_workspace => $dest_ws,
        current_user      => $self->hub->current_user,
    );
    my $dest_hub = $dest_main->hub;
    $dest_hub->registry->load;

    my $log_title = 'Mass Copy';
    my $log_page = $dest_hub->pages->new_from_name($log_title);
    my $log = $log_page->content;
    for my $page ($self->hub->pages->all) {
        $page->edit_rev();
        $page->doctor_links_with_prefix($prefix);
        my $old_id = $page->id;
        my $old_name = $page->name;
        my $new_name =
          $old_name =~ /^\Q$prefix\E/ ? $old_name : $prefix . $old_name;
        $page->duplicate(
            $dest_ws,
            $new_name,
            1, # keep categories
            1, # keep attachments
            0, # clobber (hopefully this won't happen if prefixes are used)
        );
        $log .= qq{* "$old_name"<http:/admin/index.cgi?;page_name=$old_id;action=revision_list> became [$new_name]\n};
    }
    $log .= "----\n";
    $log_page->name($log_title);
    $log_page->content($log);
    $log_page->store( user => $user );
}

sub _duplicate {
    my $self      = shift;
    my $target_ws = shift;
    my $pages     = $self->hub->pages;

    return 1
        unless $self->hub->authz->user_has_permission_for_workspace(
                   user       => $self->hub->current_user,
                   permission => ST_EDIT_PERM,
                   workspace  => $target_ws,
               );

    # user cannot duplicate a locked page if they don't have locked perms.
    return 1 unless $self->hub->checker->can_modify_locked( $pages->current );

    my $page_title = $self->cgi->new_title;
    my $new_page = $pages->page_in_workspace($page_title, $target_ws->name);

    if (defined $new_page) {
        # user cannot overwrite a locked ( target ) page if they don't have 
        # perms to do so.
        return 1 if $target_ws->allows_page_locking
            && $new_page->locked
            && ! $self->hub->authz->user_has_permission_for_workspace(
                user       => $self->hub->current_user,
                permission => ST_LOCK_PERM,
                workspace  => $target_ws,
            );

        return 0 if $self->cgi->clobber ne $page_title;
    }

    return $pages->current->duplicate(
        $target_ws,
        $page_title,
        $self->cgi->keep_categories || '',
        $self->cgi->keep_attachments || '',
        $self->cgi->clobber,
    );
}

sub _page_title_bad {
    my ( $class_or_self, $title ) = @_;
    return Socialtext::Page->is_bad_page_title($title);
}

package Socialtext::DuplicatePage::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'keep_attachments';
cgi 'keep_categories';
cgi 'new_title';
cgi 'target_workspace_id';
cgi 'clobber';
cgi 'json';

1;
