package Socialtext::Lite;
# @COPYRIGHT@
use Moose;
use Readonly;
use Date::Parse qw/str2time/;
use Socialtext::Authen;
use Socialtext::String qw/uri_escape/;
use Socialtext::Permission 'ST_EDIT_PERM';
use Socialtext::Helpers;
use Socialtext::l10n;
use Socialtext::Timer;
use Socialtext::Session;
use Socialtext::Formatter::LiteLinkDictionary;
use Socialtext::Encode;
use Socialtext::Pages;
use Socialtext::l10n;
use Try::Tiny;

use namespace::clean -except => 'meta';

has 'link_dictionary' => (
    is => 'rw', isa => 'Socialtext::Formatter::LiteLinkDictionary',
    lazy_build => 1,
);

sub _build_link_dictionary { Socialtext::Formatter::LiteLinkDictionary->new }

=head1 NAME

Socialtext::Lite - A set of lightweight entry points to the NLW application

=head1 SYNOPSIS

    my $page_display = Socialtext::Lite->new( hub => $nlw->hub )->display($page);

=head1 DESCRIPTION

NLW can present a variety of views into the data in a workspace, but the entry
points to this activity are often obscured behind many layers of code.
Socialtext::Lite provides a way to perform some of these actions in a
straightforward manner. It assumes that a L<Socialtext::Hub> is already
available and fully initialized.

Socialtext::Lite is currently built as a class from which you create an object
on which to call methods. There's, as yet, not much reason for this but
it makes for a familiar calling convention.

See L<Socialtext::Handler::Page::Lite> for a mod perl Handler that implements
a simple interface to NLW using Socialtext::Lite.

Socialtext::Lite is not fully robust in the face of unexpected conditions.

Socialtext::Lite is trying to be a simple way to create or demonsrate alternate
interfaces to the workspaces, users and pages manages by NLW. In the
process it may suggest ways in which the rest of the system can be 
made more simple, or classes could be extracted into their component
parts.

Socialtext::Lite is limited in functionality by design. Before adding something
ask yourself if it is really necessary.

=head1 URIs in HTML output

Socialtext::Lite returns URIs that begin with /lite/. No index.cgi is used, as
with the traditional interface to NLW. L<Socialtext::Formatter> is tightly 
coupled with it's presentation level, traditional NLW, by default
generating URIs specific to that view. Because of this Socialtext::Lite
overrides some methods in the formatter. These overrides are done in
the _frame_page method.

=cut

# The templates we display with
Readonly my $LOGIN_TEMPLATE          => 'lite/login/login.html';
Readonly my $NOLOGIN_TEMPLATE        => 'lite/login/nologin.html';
Readonly my $DISPLAY_TEMPLATE        => 'lite/page/display.html';
Readonly my $EDIT_TEMPLATE           => 'lite/page/edit.html';
Readonly my $CONTENTION_TEMPLATE     => 'lite/page/contention.html';
Readonly my $CHANGES_TEMPLATE        => 'lite/changes/changes.html';
Readonly my $SEARCH_TEMPLATE         => 'lite/search/search.html';
Readonly my $TAG_TEMPLATE            => 'lite/tag/tag.html';
Readonly my $WORKSPACE_LIST_TEMPLATE => 'lite/workspace_list/workspace_list.html';
Readonly my $PAGE_LOCKED_TEMPLATE     => 'lite/page/page_locked.html';
Readonly my $FORGOT_PASSWORD_TEMPLATE => 'lite/forgot_password/forgot_password.html';

=head1 METHODS

=head2 new(hub => $hub)

Creates a new Socialtext::Lite object. If no hub is passed, the Socialtext::Lite
object will be unable to perform.

=head2 hub

Returns the hub that will be used to find classes and data. Currently
only an accessor.

=cut
has 'hub' => (is => 'rw', isa => 'Socialtext::Hub', required => 1);

=head2 login()

Shows a mobile version of the login page.

=cut
sub login {
    my $self        = shift;
    my $redirect_to = shift || '/m/workspace_list';
    my $session     = Socialtext::Session->new();
    return $self->_process_template(
        $LOGIN_TEMPLATE,
        title             => loc('login.title'),
        redirect_to       => $redirect_to,
        errors            => [ $session->errors ],
        messages          => [ $session->messages ],
        username_label    => Socialtext::Authen->username_label,
        public_workspaces =>
            [ $self->hub->workspace_list->public_workspaces ],
    );
}

sub nologin {
    my $self = shift;

    my $messages;
    my $file = Socialtext::AppConfig->login_message_file();
    if ( $file and -r $file ) {
        try { $messages = Socialtext::File::get_contents_utf8($file) }
        catch { warn $_ };
    }
    $messages //= '<p>'. loc('info.login-disabled') .'</p>';

    return $self->_process_template(
        $NOLOGIN_TEMPLATE,
        title             => loc('login.disabled'),
        messages          => [ $messages ],
    );
}

=head2 forgot_password()

Shows a mobile version of the forgot_password page.

=cut

sub forgot_password {
    my $self = shift;
    my $session = Socialtext::Session->new();
    return $self->_process_template(
        $FORGOT_PASSWORD_TEMPLATE,
        errors            => [ $session->errors ],
        messages          => [ $session->messages ],
    );
}

=head2 display($page)

Given $page, a L<Socialtext::Page>, returns a string of HTML suitable for
output to a web browser.

=cut
sub display {
    my $self = shift;
    my $page = shift || $self->hub->pages->current;

    my $section = 'page';
    if ($self->hub->current_workspace->title eq $page->title) {
        $section = 'workspace';
    }

    return $self->_frame_page($page, section => $section);
}

=head2 edit_action($page)

Presents HTML including a form for editing $page, a L<Socialtext::Page>.

=cut
sub edit_action {
    my $self = shift;
    my $page = shift;
    return $self->_process_template(
        $EDIT_TEMPLATE,
        page => $page,
    );
}

=head2 edit_save($page)

Expects CGI data provided from the form in C<edit_action>. Updates
$page with content and other data provided by the CGI data.

If no revision_id, revision or subject are provided in the CGI
data, use the information in the provided page object.

=cut

sub edit_save {
    my ($self, %p) = @_;
    my $page = delete $p{page};
    my $is_comment = ($p{action} && $p{action} eq 'comment');

    return try {
        $is_comment ? $page->add_comment($p{comment})
                    : $page->update_from_remote(%p);
        return '';    # insure that we are returning no content
    }
    catch {
        if (/^Contention:/) {
            return $self->_handle_contention($page, $p{subject},
                $is_comment ? $p{comment} : $p{content});
        }
        elsif (/Page is locked/) {
            return $self->_handle_lock($page, $p{subject},
                $is_comment ? $p{comment} : $p{content});
        }
        die $_; 
    };
}

=head2 recent_changes

Returns HTML representing the list of the fifty (or less) most 
recently changed pages in the current workspace.

=cut


sub recent_changes {
    my $self     = shift;
    my $tag = shift || '';
    my $changes = $self->hub->recent_changes->get_recent_changes_in_category(
        count    => 50,
        category => $tag,
    );

    my $title = 'Recent Changes';
    $title .= " in $tag" if $tag;

    return $self->_process_template(
        $CHANGES_TEMPLATE,
        section   => 'recent_changes',
        title     => $title,
        tag       => $tag,
        load_row_times => sub {
            return Socialtext::Query::Plugin::load_row_times(@_);
        },
        %$changes,
    );
}

=head2 workspace_list()

Returns a list of the workspaces that the user has access to, including any
public workspaces.

=cut

sub workspace_list {
    my $self  = shift;
    return $self->_process_template(
        $WORKSPACE_LIST_TEMPLATE,
        title             => loc('wiki.list'),
        section           => 'workspaces',
        my_workspaces     => [ $self->hub->workspace_list->my_workspaces ],
        public_workspaces => [ $self->hub->workspace_list->public_workspaces ],
    );
}

=head2 search([search_term => $search_term, page_num => $page_num])

Returns a form for searching the current workspace. If $search_term 
is defined, the results of that search are provided as a list of links
to pages, with $page_num specifing the 0-based page index.

=cut

sub search {
    my ($self, %args) = @_;
    my $search_term = $self->_utf8_decode($args{search_term});
    my $search_results;
    my $title = 'Search';
    my $error = '';
    my $pagenum = $args{pagenum} ||  0;
    my $page_size = 20;

    if ( $search_term ) {
        try {
            my $search = $self->hub->search;
            $search->sortby($search->preferences->default_search_order->value);
            $search->_direction($search->preferences->direction->value);
            $search_results = $search->get_result_set(
                search_term => $search_term,
                offset => $pagenum * $page_size,
                limit => $page_size,
            );
            $title = $search_results->{display_title};
        }
        catch {
            $error = $_;
            $title = 'Search Error';
        };
    }

    my $more = 0;
    $search_results->{hits} //= 0;
    if ($search_results->{too_many}) {
        $error = loc('error.search-too-general=hits', $search_results->{hits});
    }
    elsif ($search_results->{hits} > (($pagenum+1) * $page_size)) {
        $more = 1;
    }

    return $self->_process_template(
        $SEARCH_TEMPLATE,
        section       => 'search',
        search_term   => $search_term,
        title         => $title,
        search_error  => $error,
        pagenum       => $pagenum,
        more          => $more,
        base_uri      => '/m/search/'.$self->hub->current_workspace->name.'?search_term='.uri_escape($search_term),
        load_row_times => sub {
            return Socialtext::Query::Plugin::load_row_times(@_);
        },
        %$search_results,
    );
}

=head2 tag([tag => $tag, pagenum => $pagenum])

If $tag is not defined, provide a list of links to all categories
in the current workspace. If $tag is defined, provide a list of
links to all the pages in the tag, with $page_num specifing the
0-based page index.

=cut

sub tag {
    my ($self, %args) = @_;
    my $tag = $self->_utf8_decode($args{tag});

    if ($tag) {
        return $self->_pages_for_tag(%args);
    }
    else {
        return $self->_all_tags(%args);
    }
}

sub _pages_for_tag {
    my ($self, %args) = @_;
    my $tag = $args{tag};
    my $pagenum = $args{pagenum} ||  0;
    my $page_size = 20;

    $tag = Socialtext::Encode::ensure_is_utf8($tag);
    my $rows = Socialtext::Pages->By_tag(
        hub          => $self->hub,
        workspace_id => $self->hub->current_workspace->workspace_id,
        tag          => $tag,
        order_by     => 'last_edit_time DESC',
        limit        => $page_size+1,
        offset       => $pagenum * $page_size,
        do_not_need_tags => 1,
    );
    my $more = pop @$rows if @$rows > $page_size;

    return $self->_process_template(
        $TAG_TEMPLATE,
        title     => loc("nav.tag=tag", $tag),
        section   => 'tag',
        base_uri  => '/m/tag/'.$self->hub->current_workspace->name.'/'.$tag,
        rows      => $rows,
        tag       => $tag,
        pagenum   => $pagenum,
        more      => $more ? 1 : 0,
        load_row_times => sub {
            return Socialtext::Query::Plugin::load_row_times(@_);
        },
    );
}

sub _all_tags {
    my ($self, %args) = @_;

    my %weighted = $self->hub->category->weight_categories;
    my $tags = $weighted{tags};

    my @rows = lsort_by name => grep {
        $_->{page_count} > 0
    } @$tags;

    my $page_size = 20;
    my $pagenum = $args{pagenum} ||  0;
    @rows = @rows[($pagenum*$page_size) .. (($pagenum+1)*$page_size)];
    my $more = pop @rows if @rows > $page_size;
    pop @rows while @rows and !$rows[-1];

    return $self->_process_template(
        $TAG_TEMPLATE,
        base_uri => '/m/tag/'.$self->hub->current_workspace->name,
        title    => loc('nav.tags'),
        section  => 'tags',
        tags     => \@rows,
        pagenum  => $pagenum,
        more     => $more ? 1 : 0,
    );
}


# XXX utf8_decode should be on Socialtext::String not Socialtext::Base
sub _utf8_decode {
    my $self = shift;
    my $text = shift;
    return $self->hub->utf8_decode($text);
}

sub _handle_contention {
    my $self    = shift;
    my $page    = shift;
    my $subject = shift;
    my $content = shift;

    return $self->_process_template(
        $CONTENTION_TEMPLATE,
        title     => "$subject Editing Error",
        content   => $content,
        page      => $page,
    );
}

sub _handle_lock {
    my $self    = shift;
    my $page    = shift;
    my $subject = shift;
    my $content = shift;

    return $self->_process_template(
        $PAGE_LOCKED_TEMPLATE,
        title   => "$subject Editing Error",
        content => $content,
        page    => $page,
    );
}

sub _frame_page {
    my ($self, $page, %args) = @_;

    my $attachments = $self->_get_attachments($page);

    $self->hub->viewer->link_dictionary($self->link_dictionary);

    Socialtext::Timer->Continue('lite_page_html');
    $self->hub->pages->current($page);
    my $html = $page->to_html_or_default;
    Socialtext::Timer->Pause('lite_page_html');
    return $self->_process_template(
        $DISPLAY_TEMPLATE,
        page_html        => $html,
        title            => $page->title,
        attachments      => $attachments,
        # XXX next two for attachments, because we are using legacy urls
        # for now
        page             => $page,
        user_can_edit_page => (
            $self->hub->checker->check_permission('edit') &&
            $self->hub->checker->can_modify_locked($page)
        ),
        user_can_comment_on_page => (
            $self->hub->checker->check_permission('comment') &&
            $self->hub->checker->can_modify_locked($page) &&
            ($page->is_wiki or $page->is_xhtml)
        ),
        user_can_join_to_edit_page => $self->user_can_join_to_edit_page($page),
        %args,
    );
}

sub user_can_join_to_edit_page {
    my ($self, $page) = @_;

    return (
        $self->hub->current_user->is_authenticated &&
        $self->hub->checker->check_permission('self_join') &&
        $self->hub->checker->can_modify_locked($page)
    );
}

sub _process_template {
    my $self     = shift;
    my $template = shift;
    my %vars     = @_;

    my %ws_vars;
    if ($self->hub->current_workspace->real) {
        %ws_vars = (
            ws => $self->hub->current_workspace,
        );
    }

    my $template_vars = $self->template_vars;

    my $user = $self->hub->current_user;
    return $self->hub->template->process(
        $template, %$template_vars, %ws_vars, %vars,
        app_version => Socialtext->product_version,
    );
}

sub template_vars {
    my $self = shift;

    my $warning;
    # XXX ACK ACK! THIS WON'T WORK WITH PLACK:
    my $ua = $ENV{HTTP_USER_AGENT} || '';
    if (my ($version) = $ua =~ m{^BlackBerry[^/]+/(\d+\.\d+)}) {
        if ($version < 4.5) {
            $warning = loc("error.blackberry-version-too-low");
        }
    }

    my $skin_info = $self->hub->skin->skin_info;
    my $s3 = Socialtext::Skin->new(name => 's3');

    my $user = $self->hub->current_user;
    return {
        warning     => $warning,
        miki        => 1,
        css         => $self->hub->skin->css_info,
        skin_info   => $skin_info,
        user        => $self->hub->current_user,
        brand_stamp => $self->hub->main ? $self->hub->main->version_tag: '',
        static_path => Socialtext::Helpers::static_path,
        s3_uri    => sub { $s3->skin_uri . "/$_[0]" },
        skin_uri    => sub { 
            if ("$_[0]" =~ m{/images/asset-icons/}) {
                return $s3->skin_uri . "/$_[0]";
            }
            return $self->hub->skin->skin_uri . "/$_[0]"
        },
        pluggable   => $self->hub->pluggable,
        user        => $user,
        minutes_ago => sub { int((time - str2time(shift, 'UTC')) / 60) },
        enable_jquery_mobile => ($ua =~ /Gecko/) || 0,
    };
}

sub _get_attachments {
    my $self = shift;
    my $page = shift;

    my @attachments = lsort_by filename =>
        @{ $self->hub->attachments->all( page_id => $page->id ) };

    return \@attachments;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;
__END__

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
