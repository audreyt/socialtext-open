# @COPYRIGHT@
package Socialtext::RenamePagePlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

use Class::Field qw( const );
use Socialtext::AppConfig;
use Socialtext::Page;
use Socialtext::Pages;
use Socialtext::String ();
use Socialtext::Permission 'ST_EDIT_PERM';
use Socialtext::JSON;

# XXX funkity duplication throughout, trying to remove some
# but still plenty left

# XXX: We can remove the necessity of this plugin by implementing this in REST and JS

sub class_id { 'rename_page' }
const cgi_class => 'Socialtext::RenamePage::CGI';

sub register {
    my $self = shift;
    $self->hub->registry->add(action => 'rename_popup');
    $self->hub->registry->add(action => 'rename_page');
}

sub rename_popup {
    my $self = shift;
    my %p = @_;
    return encode_json(\%p) if $self->cgi->json;
    return $self->template_process(
        'popup/rename',
        %p,
        $self->hub->helpers->global_template_vars,
    );
}

sub rename_page {
    my $self = shift;

    my $new_title = $self->cgi->new_title;
    my $new_id = Socialtext::String::title_to_id($new_title);

    if ( $self->_page_title_bad($new_title)) {
        return $self->rename_popup(
            page_title_bad => 1,
        );
    }
    elsif ( Socialtext::String::MAX_PAGE_ID_LEN < length $new_id ) {
        return $self->rename_popup(
            page_title_too_long => 1,
        );
    }
    elsif ( $new_title eq $self->hub->pages->current->title ) {
        return $self->rename_popup( same_title => 1 );
    }
    elsif ( $self->_rename() ) {
        return encode_json({done=>1}) if $self->cgi->json;
        return $self->template_process('close_window.html',
            before_window_close => q{window.opener.location='} .
                Socialtext::AppConfig->script_name . '?' .
                $new_id . q{';},
        );
    }

    return $self->rename_popup(
        page_exists => 1,
    );
}

sub _rename {
    my $self = shift;
    my $page = $self->hub->pages->current;

    return 1
        unless $self->hub->authz->user_has_permission_for_workspace(
                   user       => $self->hub->current_user,
                   permission => ST_EDIT_PERM,
                   workspace  => $self->hub->current_workspace,
               );

    return 1 unless $self->hub->checker->can_modify_locked( $page );

    return $page->rename(
        $self->cgi->new_title,
        $self->cgi->keep_categories || '',
        $self->cgi->keep_attachments || '',
        $self->cgi->clobber,
    );
}

sub _page_title_bad {
    my ( $self, $title ) = @_;
    return Socialtext::Page->is_bad_page_title($title);
}

package Socialtext::RenamePage::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'keep_attachments';
cgi 'keep_categories';
cgi 'new_title';
cgi 'clobber';
cgi 'json';

1;
