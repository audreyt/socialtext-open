# @COPYRIGHT@
package Socialtext::Plugin;
use strict;
use warnings;

use base 'Socialtext::Base';

use Class::Field qw( const field );
use File::Path ();
use Socialtext::Challenger;
use Socialtext::Indexes;
use Socialtext::File;
use Socialtext::Paths;
use Socialtext::User;
use Socialtext::String ();
use Socialtext::TT2::Renderer;

# Look for plugins by namespace.  This exposes the ->plugins() method
use Module::Pluggable search_path => ['Socialtext::Plugin'];

const cgi_class       => '';
const pref_scope => 'workspace';

field cgi         => -init => '$self->hub->cgi';
field display_title => '';
field screen_template => '';
field message       => '';
field errors        => [];
field warnings      => [];

sub class_id {
    my $class = ref $_[0] || $_[0];
    die "You must define a class_id method in $class\n";
}

sub preferences { $_[0]->hub->preferences_object }

sub class_title {
    my $self = shift;
    my $title = ref $self;
    $title =~ s/.*:://;
    return $title;
}

sub new {
    my $class = shift;
    return $class if ref $class;
    return $class->SUPER::new(@_);
}

sub init {
    my $self = shift;
    $self->init_cgi;
}

sub failure_message {
    my $self = shift;
    my $message = shift;
    my $error   = shift;
    my $page    = shift;

    $self->hub->main->status_message( $message . "<!-- $error -->" );
    $self->hub->pages->current($page);
    $self->hub->action('display');
    return $self->hub->display->display();
}

sub redirect {
    my $self = shift;
    # This uses Socialtext::WebHelpers::redirect
    $self->hub->headers->redirect( $self->_redirect_url(@_) );
    return '';
}

sub reject_guest {
    my $self = shift;
    if ($self->hub->current_user->is_guest) {
        Socialtext::Challenger->Challenge(@_);
    }
}

sub box_on {
    my $self = shift;1}

sub box_title {
    my $self = shift;
    return $self->class_title;
}

sub box {
    my $self = shift;
    return '' unless $self->box_on;
    my $box = eval { $self->_render_box };
    return "<pre>\n$@\n</pre>" if $@;
    return $box;
}

sub new_preference {
    my $self = shift;
    $self->hub->preferences->new_preference( scalar(caller), @_ );
}

sub new_dynamic_preference {
    my $self = shift;
    $self->hub->preferences->new_dynamic_preference( scalar(caller), @_ );
}

sub preference {
    my $self = shift;
    my $preference = shift;
    $self->preferences->$preference()->value;
}

sub check_required {
    my $self = shift;
    my $param = shift;
    my $value = $self->$param;
    return 1 if length $value;
    return $self->add_error( _humanify($param) . ' is a required field.' );
}

sub add_error {
    my $self = shift;
    my $error_message = shift;
    $error_message =~ s/</&lt;/g;
    push @{ $self->errors }, $error_message;
    return 0;
}

sub add_warning {
    my $self = shift;
    my $warning_message = shift;
    $warning_message =~ s/</&lt;/g;
    push @{ $self->warnings }, $warning_message;
    return 0;
}

sub input_errors_found {
    my $self = shift;
    return @{ $self->errors } ? 1 : 0;
}

sub status_messages_for_template {
    my $self = shift;
    return (
        message  => $self->message,
        warnings => $self->warnings,
        errors   => $self->errors,
    );
}

sub render_screen {
    my $self = shift;

    $self->template_process(
        $self->screen_template,
        $self->hub->helpers->global_template_vars,
        view => $self->class_id,
        style => 'st-'.$self->class_id,
        'class_id' => $self->class_id,
        content_pane => $self->class_id . '_content.html',
        @_,
    );
}

sub screen_wrap {
    my $self = shift;
    my $display_title = shift;
    my $pane_content  = shift;

    $self->template_process(
        'view/screen_wrap',
        display_title     => $display_title,
        content_pane_html => $pane_content,
        @_,
    );
}

sub _create_dummy_current_for_data_validation_error {
    my $self = shift;
    my $page_name = 
      $self->hub->cgi->page_name ||
      $self->hub->current_workspace->title;
    my $page_id = substr(Socialtext::String::title_to_id($page_name), 0, Socialtext::String::MAX_PAGE_ID_LEN);
    return $self->hub->pages->new_page($page_id); 
}

# template_render and template_process are similar but different.  
# template_render() is a refactoring of many calls to $renderer->render()
sub template_render {
    my $self = shift;
    my %args = @_;
    my $paths = $self->hub->skin->template_paths;
    push @$paths, @{$args{paths}} if ref $args{paths} eq 'ARRAY';
    $args{paths} = $paths;
    my $renderer = Socialtext::TT2::Renderer->instance;
    return $renderer->render(%args);
}

sub template_process {
    my $self = shift;
    my $template = shift;

    my $current = $self->hub->pages->current;
    if(!defined $self->hub->pages->current) {
        $current = $self->_create_dummy_current_for_data_validation_error();
    }

    $self->hub->template->process(
        $template,
        self => $self,
        (
              $current->id
            ? $current->all
            : ()
        ),
        $self->cgi->all,
        @_,
    );
}

sub _render_box {
    my $self = shift;
    my $title = $self->box_title;
    $self->template_process('side_box.html');
}

sub _redirect_url {
    my $self = shift;
    my $target = shift;
    return $target
        if $target =~ /^(https?:|\/)/i
        or $target =~ /\?/;
    return $self->hub->cgi->full_uri . '?' . $target;
}

sub _get_pref_list {
    my $self = shift;
    my $pref_scope = shift || 'workspace';
    my $prefs = $self->preferences->objects_by_class;
    my @pref_list = map { $_->{title} =~ s/ /&nbsp;/g; $_; }
        grep { $prefs->{ $_->{id} } }
        grep { $_->{pref_scope} eq $pref_scope }
        @{ $self->hub->registry->lookup->plugins };

    return \@pref_list;
}

sub _feeds {
    my $self      = shift;
    my $workspace = shift;
    my $page      = shift;

    my $root = $self->hub->syndicate->feed_uri_root(
        $self->hub->current_workspace );
    my %feeds = (
        rss => {
            changes => {
                title => $workspace->title . ' - Recent Changes RSS',
                url   => $root . '?category=Recent%20Changes'
            },
            watchlist => {
                title => $workspace->title . ' - Watchlist RSS',
                url   => $root . '?watchlist=default'
            },
        },
        atom => {
            changes => {
                title => $workspace->title . ' - Recent Changes Atom',
                url   => $root . '?category=Recent%20Changes;type=Atom'
            },
            watchlist => {
                title => $workspace->title . ' - Watchlist Atom',
                url   => $root . '?watchlist=default;type=Atom'
            },
        },
    );

    if ( defined($page) ) {
        $feeds{rss}->{page} = {
            title => $page->title . ' - ' . $workspace->title . ' RSS',
            url   => $root . '?page=' . $page->id
        };
        $feeds{atom}->{page} = {
            title => $page->title . ' - ' . $workspace->title . ' Atom',
            url   => $root . '?page=' . $page->id . ';type=Atom'
        };
    }

    return \%feeds;
}

sub _humanify {
    join ' ', map { ucfirst($_) } split /_/, shift;
}

1;

