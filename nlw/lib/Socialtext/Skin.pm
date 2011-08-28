# @COPYRIGHT@
package Socialtext::Skin;
# @COPYRIGHT@

use strict;
use warnings;
use base 'Socialtext::Plugin';
use Apache::Cookie;
use Socialtext::SystemSettings qw(get_system_setting);
use File::Basename qw(dirname);
use Socialtext::URI;
use Socialtext::AppConfig;
use Socialtext;
use File::Spec;
use YAML;
use List::MoreUtils qw/any/;

our $CODE_BASE = Socialtext::AppConfig->code_base;
our $PROD_VER = Socialtext->product_version();
our $DEFAULT_PARENT = 's2';
my %css_files = (
    standard => [qw(bubble.css screen.css screen.ie.css screen.ie6.css screen.ie7.css print.css print.ie.css)],
    popup    => [qw(popup.css popup.ie.css)],
    wikiwyg  => [qw(wikiwyg.css)],
    mobile   => [qw(bubble.css miki.css)],
    widget   => [qw(widget.css)],
);

sub class_id { 'skin' }

# Returns an array of full paths to the preloaded templates, unless the skin
# is a symlink
sub PreloadTemplateDirs {
    my $class = shift;
    return grep { !-l $_ } glob($class->_path('skin', '*', 'template'));
}

sub new {
    my $class = shift;
    my %args = @_ % 2 ? () : (@_);
    my $self = $class->SUPER::new(@_);

    require Socialtext::Workspace;      # lazy-load, to reduce startup impact

    $self->{_no_workspace} = Socialtext::NoWorkspace->new;
    $self->{_skin_name} = $args{name};
    return $self;
}

sub exists {
    my $self = shift;
    return -d $self->skin_path;
}

sub workspace {
    my ($self) = @_;
    return $self->hub
        ? $self->hub->current_workspace
        : $self->{_no_workspace};
}

sub user_account_skin {
    my ($self) = @_;
    return $self->{_user_account_skin} if $self->{_user_account_skin};
    return $self->{_user_account_skin} = $self->hub
        ? $self->hub->current_user->primary_account->skin_name
        : undef;
}

sub workspace_account_skin {
    my ($self) = @_;
    return $self->hub
        ? $self->hub->current_workspace->account->skin_name
        : undef;
}

sub parent {
    my $self = shift;
    my $parent_skin = $self->skin_info->{parent};
    return Socialtext::Skin->new(name => $parent_skin) if $parent_skin;
}

{                                                                               
    # Avoid recursing into skins multiple times
    my %seen_skin;
    sub template_paths {
        my ($self,$skin) = @_;
        my $info = $self->skin_info;                                            
        my $name = $self->skin_name;                                            
    
        return [] if $seen_skin{$name}++;
        my $dirs = $self->parent ? $self->parent->template_paths : [];          
        delete $seen_skin{$name};                                               
        push @$dirs, grep { -d $_ } $self->skin_path('template');               
    
        unless (any { m#/user_frame$# } @$dirs) {                         
            push @$dirs, Socialtext::Paths::cache_directory('user_frame');      
        }   
            
        return $dirs;
    }       
} 

sub skin_info {
    my $self = shift;
    my $skin = $self->skin_name;

    return $self->{_skin_info} if $self->{_skin_info};

    my $skin_path = $self->skin_path;

    my $info_path = File::Spec->catfile( $skin_path, 'info.yaml' );
    my $info = -f $info_path ? YAML::LoadFile($info_path) : {
        parent      => 's3',
        depends     => ['s3'],
        cascade_css => 1,
    };
    unless (exists $info->{parent}) {
        $info->{parent} = $DEFAULT_PARENT if $DEFAULT_PARENT ne $skin;
    }
    $info->{skin_name} = $skin;
    $info->{skin_path} = $skin_path;
    $info->{cascade_css} = defined $info->{cascade_css}
        ? $info->{cascade_css}
        : $self->workspace->cascade_css;

    return $self->{_skin_info} = $info;
}

sub info_param {
    my ($self, $name) = @_;
    my $info = $self->skin_info;
    if ($info->{$name}) {
        return $info->{$name};
    }
    elsif ($name =~ /^desktop_(.+)/ and $info->{desktop}{$1}) {
        return $info->{desktop}{$1};
    }
    elsif ($self->parent) {
        return $self->parent->info_param($name);
    }
}

sub css_info {
    my $self = shift;
    my $skin_info = $self->skin_info;

    my $css_info = ($self->parent && $skin_info->{cascade_css})
        ? $self->parent->css_info
        : {};

    if ($self->skin_name eq $skin_info->{skin_name}) {
        while (my ($sec,$files) = each %css_files) {
            push @{$css_info->{$sec}}, map  { $self->skin_uri('css',$_) }
                                       grep { -f $self->skin_path('css',$_) }
                                       @$files;
        }
    }
    else {
        # {bz: 5366}: During a global search, the search result affects
        # hub->workspace_name and so we can end up with an inconsistent
        # result-ws-specific $self->skin_name vs global $skin_info->{skin_name}.
        # In that case, simply choose the latter.
        while (my ($sec,$files) = each %css_files) {
            push @{$css_info->{$sec}}, map  { $self->_uri('skin', $skin_info->{skin_name}, 'css',$_) }
                                       grep { -f $self->_path('skin', $skin_info->{skin_name}, 'css',$_) }
                                       @$files;
        }
    }

    # Common CSS
    unless ($self->info_param('no_common')) {
        $css_info->{common} ||= [
             $self->_uri('skin/common/css/common.css')
        ];
    }

    return $css_info;
}

sub css_files {
    my $self = shift;

    my $info = $self->css_info;

    my @files;
    for my $paths (values %$info) {
        for my $path (@$paths) {
            if (my ($skin, $file) = $path =~ m{skin/([^/]+)/css/(.*)}) {
                push @files, $self->_path("skin/$skin/css/$file");
            }
        }
    }

    return @files;
}

sub skin_upload_path {
    my $self = shift;
    my $workspace_name = $self->workspace->name;
    return $self->_path("uploaded-skin/$workspace_name");
}

sub skin_path {
    my $self = shift;
    my $skin = $self->skin_name;
    if ($skin =~ m{^(?:skin|uploaded-skin)/}) {
        return $self->_path($skin, @_);
    }
    return $self->_path('skin', $skin, @_);
}

sub skin_uri {
    my $self = shift;
    my $skin = $self->skin_name;

    my $skin_uri;
    if ($skin =~ m{^(?:skin|uploaded-skin)/}) {
        return $self->_uri($skin, @_);
    }
    return $self->_uri('skin', $skin, @_);
}

sub customjs {
    my $self = shift;
    my ($uri, $name);

    # Ignore customjs_name and customjs_uri if we're using an uploaded skin
    unless ($self->workspace->uploaded_skin) {
        $uri = $self->workspace->customjs_uri;
        $name = $self->customjs_name;
    }

    unless ($uri) {
        my $path = $self->skin_path($name);
        if (-f "$path/javascript/custom.js") {
            $uri = $self->skin_uri($name, 'javascript/custom.js');
        }
    }

    return $uri;
}

sub skin_name {
    my $self = shift;
    return $self->{_skin_name} if defined $self->{_skin_name};

    my $workspace_name = $self->workspace->name;

    my $skin_name;
    my $self_uri = Socialtext::URI::uri();
    if ( Apache::Cookie->can('fetch') ) {
        $skin_name = Apache::Cookie->fetch('socialtext-skin');
    }

    return $skin_name if $skin_name;
    if ($self->workspace->uploaded_skin) {
        $skin_name = "uploaded-skin/$workspace_name";
        my $full_path = $self->_path($skin_name);
        return $skin_name if -d $full_path;

        # uploaded_skin must have been set incorrectly!
        $self->workspace->update(uploaded_skin => 0);
    }

    # if the workspace has a skin, just return it
    return $self->workspace->skin_name
        if $self->workspace->skin_name;

    # If workspace_name is set use the workspace's skin.
    # If it isn't (ie it's a NoWorkspace environment), use the user's
    # account's skin.
    $skin_name = $workspace_name
        ? $self->workspace_account_skin
        : $self->user_account_skin;
    return $skin_name || get_system_setting('default-skin');
}

sub cascade_css {
    my $self = shift;
    my $cascade = $self->skin_info->{cascade_css};
    return defined $cascade ? $cascade : $self->workspace->cascade_css;
}

sub customjs_name {
    my $self = shift;
    return $self->skin_info->{customjs_name} || $self->workspace->customjs_name;
}

sub dynamic_logo {
    my $self = shift;
    # uploaded logos only apply to the default skin
    return unless ($self->skin_name eq 's3');

    my $logo_acct_id = 0;
    my $cur_ws = $self->workspace;
    if ($cur_ws->real) {
        $logo_acct_id = $cur_ws->account_id;
    }
    else {
        my $cur_user = $self->hub->current_user;
        $logo_acct_id = $cur_user->primary_account_id
            if ($cur_user->is_authenticated);
    }
    return "/data/accounts/$logo_acct_id/logo";
}

sub make_dirs {
    my $self = shift;
    my @dirs;
    push @dirs, $self->parent->make_dirs if $self->parent;
    my $makefile = $self->skin_path("javascript/Makefile");
    push @dirs, dirname($makefile) if -f $makefile;
    return @dirs;
}

sub _path {
    my $self = shift;
    return File::Spec->catdir( $CODE_BASE, grep { defined $_ } @_ );
}

sub _uri {
    my $self = shift;
    return join('/', '', 'static', $PROD_VER, grep { defined $_ } @_);
}

1;
