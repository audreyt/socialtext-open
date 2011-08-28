# @COPYRIGHT@
package Socialtext::Helpers;
use strict;
use warnings;
use Encode;

# vaguely akin to RubyOnRails' "helpers"
use Socialtext;
use base 'Socialtext::Base';
use Socialtext::File;
use Socialtext::TT2::Renderer;
use Socialtext::l10n;
use Socialtext::Stax;
use Socialtext::Timer;
use Socialtext::String ();
use Apache::Cookie;
use Email::Address;
use Email::Valid;
use File::Path ();

our $ENABLE_FRAME_CACHE = 1;
my $PROD_VERSION = Socialtext->product_version;
my $CODE_BASE = Socialtext::AppConfig->code_base;

sub class_id { 'helpers' }

sub static_path { "/static/$PROD_VERSION" }

my $supported_format = {
    'en' => '%B %Y',
    'ja' => '%Y年 %m月',
};

sub _get_date_format {
    my $self = shift;
    my $locale = $self->hub->best_locale;
    my $locale_format = $supported_format->{$locale};
    if (!defined $locale_format) {
        $locale = 'en';
        $locale_format = $supported_format->{'en'};
    }

    return DateTime::Format::Strptime->new(
        pattern=> $locale_format,
        locale => $locale,
    );
}

sub format_date {
    my $self = shift;
    my $year = shift;
    my $month = shift;

    # Create DateTime object
    my $datetime = DateTime->new(
        time_zone => 'local',
        year => $year,
        month => $month,
        day => 1,
        hour => 0,
        minute => 0,
        second => 0
    );

    my $format = $self->_get_date_format;
    my $date_str = $format->format_datetime($datetime);
    Encode::_utf8_on($date_str);
    return $date_str;
}


# XXX most of this should become Socialtext::Links or something

sub full_script_path {
    my $self = shift;
    '/' . $self->hub->current_workspace->name . '/index.cgi'
}

sub script_path { 'index.cgi' }

sub query_string_from_hash {
    my $self = shift;
    my %query = @_;
    return %query
      ? join '', map { ";$_=$query{$_}" } keys %query
      : '';
}

# XXX need to refactor the other stuff in this file to use this
sub script_link {
    my $self = shift;
    my $label = shift;
    my %query = @_;
    my $url = $self->script_path . '?' . $self->query_string_from_hash(%query);
    return qq(<a href="$url">$label</a>);
}

sub page_display_link {
    my $self = shift;
    my $name = shift;
    my $page = $self->hub->pages->new_from_name($name);
    return $self->page_display_link_from_page($page);
}

sub page_display_link_from_page {
    my $self = shift;
    my $page = shift;
    my $path = $self->script_path . '?' . $page->uri;
    my $title = $self->html_escape($page->name);
    return qq(<a href="$path">$title</a>);
}

sub page_edit_link {
    my $self = shift;
    my $page_name = shift;
    my $link_text = shift;
    my $extra = $self->query_string_from_hash(@_);
    return
        '<a href="' . $self->page_edit_path($page_name) . $extra . '">'
        . $self->html_escape($link_text)
        . '</a>';
}

sub page_display_path {
    my $self = shift;
    my $page_name = shift;
    my $path = $self->script_path();
    return $path . '?' . $page_name;
}

sub page_edit_path {
    my $self = shift;
    my $page_name = shift;
    my $path = $self->script_path();
    return $path . '?' . $self->page_edit_params($page_name)
}

# ...aaand we need this one, too.
sub page_edit_params {
    my $self = shift;
    my $page_name = shift;
    return 'action=display;page_name='
        . $self->uri_escape($page_name)
        . ';js=show_edit_div'
}

sub preference_path {
    my $self = shift;
    my $pref = shift;
    $self->script_path
        . "?action=preferences_settings;preferences_class_id=$pref"
        . $self->query_string_from_hash(@_)
}

sub _get_workspace_list_for_template {
    my $self = shift;
    return $self->{_workspacelist} if $self->{_workspacelist};

    require Socialtext::Workspace;      # lazy-load, to reduce startup impact
    my $ws = Socialtext::Workspace->Default;

    my @workspaces = 
    return $self->{_workspacelist} = [
        lsort_by label => map {+{
            label => $_->title,
            name => $_->name,
            account => $_->account->name,
            id => $_->workspace_id,
            ($ws and $ws->name eq $_->name) ? (default => 1) : (),
        }} $self->hub->current_user->workspaces->all
    ];
}

sub default_workspace {
    my $self = shift;
    require Socialtext::Workspace;      # lazy-load, to reduce startup impact
    my $ws = Socialtext::Workspace->Default;

    return ( defined $ws && $ws->has_user( $self->hub->current_user ) )
        ? { label => $ws->title, link => "/" . $ws->name }
        : undef;
}

sub _get_appliance_config_value {
    my $self = shift;
    my $key = shift;

    # Appliance Code is probably not installed if there's an error.
    local $@;
    eval "require Socialtext::Appliance::Config";
    if ( my $e = $@ ) {
        st_log( 'info', "Could not load Socialtext::Appliance::Config: $e\n" );
        return 0;
    }

    return Socialtext::Appliance::Config->new->value($key);
}

sub signals_only {
    my $self = shift;
    return $self->_get_appliance_config_value('signals_only');
}

sub desktop_update_enabled {
    my $self = shift;
    $self->_get_appliance_config_value('desktop_update_enabled');
}

sub global_template_vars {
    my $self = shift;
    my $hub = $self->hub;
    my $cur_ws = $hub->current_workspace;
    my $cur_user = $hub->current_user;

    Socialtext::Timer->Continue('global_tt2_vars');

    # Thunk the hell out of as much as possible, so that we can avoid
    # doing the work until we know we need it (inside the templates).
    my %thunked;
    my $thunker = sub {
        my $name = shift;
        my $sub  = shift;
        return $name => sub { $thunked{$name} ||= $sub->() };
    };

    my $locale = $hub->best_locale;

    my $use_frame_cache
        = $ENABLE_FRAME_CACHE && $self->hub->skin->skin_name ne 's2';
    my $frame_name
        = $use_frame_cache ? $self->_render_user_frame : 'layout/html';
    my %result = (
        frame_name        => $frame_name,
        firebug           => $hub->rest->query->param('firebug') || 0,
        action            => $hub->cgi->action,
        pluggable         => $hub->pluggable,
        checker           => $hub->checker,
        acct_checker      => Socialtext::Authz::SimpleChecker->new(
            user => $cur_user, container => $cur_ws->account),
        loc               => \&loc,
        loc_lang          => $locale,
        current_workspace => $cur_ws,
        current_page      => $hub->pages->current,
        home_is_dashboard => $cur_ws->homepage_is_dashboard,
        homepage_weblog => $cur_ws->homepage_weblog,
        workspace_present  => $cur_ws->real,
        app_version        => Socialtext->product_version,
        'time'             => time,
        locking_enabled    => $hub->current_workspace->allows_page_locking,
        dev_mode           => $ENV{NLW_DEV_MODE},

        $thunker->(css       => sub { $hub->skin->css_info }),
        $thunker->(skin_info => sub { $hub->skin->skin_info }),
        $thunker->(user      => sub { $self->_get_user_info }),
        $thunker->(wiki      => sub { $self->_get_wiki_info }),
        $thunker->(customjs  => sub { $hub->skin->customjs }),
        $thunker->(skin_name => sub { $hub->skin->skin_name }),

        # possibly this is only used for s2 skin stuff?
        $thunker->('search_box_snippet', sub { 
            my $renderer = Socialtext::TT2::Renderer->instance();
            return $renderer->render(
                template => 'element/search_box_snippet',
                paths => $hub->skin->template_paths,
                vars => {
                    current_workspace => $cur_ws,
                }
            );
        }),

        $thunker->(miki_url => sub { $self->miki_path }),
        $thunker->(desktop_url => sub {
            return '' unless $self->desktop_update_enabled;
            return '/st/desktop/badge';
        }),
        $thunker->(stax_info => sub { $hub->stax->hacks_info }),
        $thunker->(workspaceslist => sub {
                $self->_get_workspace_list_for_template }),
        $thunker->(default_workspace => sub { $self->default_workspace }),
        $thunker->(ui_is_expanded => sub {
            my $cookies = eval { Apache::Cookie->fetch() } || {};
            return defined $cookies->{ui_is_expanded};
        }),
        $thunker->('plugins_enabled' => sub {
            return [
                map { $_->name }
                grep {
                    $cur_ws->is_plugin_enabled($_->name) ||
                    $cur_user->can_use_plugin($_->name)
                } Socialtext::Pluggable::Adapter->plugins
            ];
        }),
        $thunker->('plugins_enabled_for_current_workspace_account' => sub {
            return [
                map { $_->name }
                grep {
                    $cur_ws->account->is_plugin_enabled($_->name)
                } Socialtext::Pluggable::Adapter->plugins
            ]
        }),
        $thunker->(self_registration => sub {
                return Socialtext::AppConfig->self_registration
                    || $hub->current_workspace->permissions->current_set_name eq 'self-join';
        }),
        $thunker->(dynamic_logo_url => sub { $hub->skin->dynamic_logo }),
        $thunker->(can_lock => sub { $hub->checker->check_permission('lock') }),
        $thunker->(page_locked => sub { $hub->pages->current->locked }),
        $thunker->(page_locked_for_user => sub {
            $hub->pages->current->locked && 
            $cur_ws->allows_page_locking &&
            !$hub->checker->check_permission('lock')
        }),
        $thunker->(role_for_user => sub { 
                $cur_ws->role_for_user($cur_user) || undef }),
        $thunker->(signals_only => sub { $self->signals_only }),
        $thunker->(is_workspace_admin => sub {
                $hub->checker->check_permission('admin_workspace') ? 1 : 0 }),

        $hub->pluggable->hooked_template_vars,
    );

    Socialtext::Timer->Pause('global_tt2_vars');
    return %result;
}

sub clean_user_frame_cache {
    if (-d user_frame_path()) {
        system("find " . user_frame_path() . " -mindepth 1 -print0 | xargs -0 rm -rf");
    }
}

sub user_frame_path {
    return Socialtext::Paths::cache_directory('user_frame');
}

sub _render_user_frame {
    local $ENABLE_FRAME_CACHE = 0;
    my $self = shift;

    my $frame_path = $self->user_frame_path;
    my $user_id = $self->hub->current_user->user_id;
    $user_id =~ m/^(\d\d?)/;
    my $user_prefix = $1;

    my $loc_lang = $self->hub->best_locale;
    my $is_guest = $self->hub->current_user->is_guest ? 1 : 0;

    my $can_invite = $self->hub->pluggable->hook('template_var.invite_url');
    $can_invite = ($can_invite ? 1 : 0);

    my $can_create_group = (
        (!$is_guest && Socialtext::Group->User_can_create_group($self->hub->current_user))
            ? 1 : 0
    );

    my $frame_dir = "$frame_path/$user_prefix/$user_id";
    my $tmpl_name = "user_frame.$loc_lang.$is_guest.$can_invite.$can_create_group";
    my $frame_tmpl = "$user_prefix/$user_id/$tmpl_name";
    my $frame_file = "$frame_dir/$tmpl_name";

    return $frame_tmpl if -f $frame_file;

    Socialtext::Timer->Continue('render_user_frame');
    my $renderer = Socialtext::TT2::Renderer->instance();
    my $frame_content = $renderer->render(
        template => 'layout/user_frame',
        paths    => $self->hub->skin->template_paths,
        vars     => {
            $self->hub->helpers->global_template_vars,
            generate_user_frame => 1,
        }
    );

    unless (-d $frame_dir) {
        File::Path::mkpath($frame_dir);
    }

    Socialtext::File::set_contents_utf8($frame_file, $frame_content);
    Socialtext::Timer->Pause('render_user_frame');
    return $frame_tmpl;
}


sub miki_path {
    my ($self, $link) = @_;
    require Socialtext::Formatter::LiteLinkDictionary;

    my $miki_path      = '/m';
    my $page_name      = $self->hub->pages->current->name;
    my $workspace_name = $self->hub->current_workspace->name;

    if ($workspace_name) {
        $miki_path = Socialtext::Formatter::LiteLinkDictionary->new->format_link(
            link => $link || 'interwiki',
            workspace => $workspace_name,
            page_uri  => $page_name,
        );
    }
    return $miki_path;
}

sub _get_user_info {
    my ($self) = @_;
    my $user = $self->hub->current_user;
    return {
        username           => $user->guess_real_name,
        userid             => $user->username,
        id                 => $user->user_id,
        email_address      => $user->email_address,
        is_guest           => $user->is_guest,
        is_business_admin  => $user->is_business_admin,
        is_technical_admin  => $user->is_technical_admin,
        primary_account_id => $user->primary_account_id,
        accounts           => sub {
            return [
                map {+{
                    account_id => $_->account_id,
                    name => $_->name,
                    plugins => [$_->plugins_enabled],
                }} $user->accounts
            ],
        },
        can_use_plugin     => sub {
            $user->can_use_plugin(@_);
        },
    };
}

# This function is called in the ControlPanel
sub skin_uri { 
    my $skin_name  = shift;
    my $skin = Socialtext::Skin->new(name => $skin_name);
    return $skin->skin_uri();
}

sub _get_wiki_info {
    my ($self) = @_;
    my $wiki = $self->hub->current_workspace;
    my $skin = $self->hub->skin->skin_name;

    return {
        title         => $wiki->title,
        central_page  => Socialtext::String::title_to_id( $wiki->title ),
        logo          => $wiki->logo_uri_or_default,
        name          => $wiki->name,
        has_dashboard => $wiki->homepage_is_dashboard,
        is_public     => $wiki->permissions->is_public,
        uri           => $wiki->uri,
        skin          => $skin,
        email_address => $wiki->email_in_address,
        static_path   => $self->static_path,
        skin_uri      => \&skin_uri,
        comment_form_window_height => $wiki->comment_form_window_height,
        system_status              => $self->hub->main ?
            $self->hub->main->status_message() : undef,
        comment_by_email           => $wiki->comment_by_email,
        email_in_address           => $wiki->email_in_address,
    };
}

# This is a little stupid, but in order to validate the email domain
# we're mocking up an email address and validating that.
# Regexp::Common's $RE{net}{domain} didn't do the trick and I couldn't think
# of a better way.
sub valid_email_domain {
    my $self_or_class = shift;
    my $domain = shift;

    my $validator =  Email::Valid->new();
    return $validator->address( 'user@' . $domain ) ? 1 : 0;
}

sub validate_email_addresses {
    my $self = shift;
    my @emails;
    my @invalid;
    if ( my $ids = shift ) {
        my @lines = $self->_split_email_addresses( $ids );

        unless (@lines) {
            $self->add_error(loc("error.email-adress-required"));
            return;
        }

        for my $line (@lines) {
            my ( $email, $first_name, $last_name )
              = $self->_parse_email_address($line);
            unless ($email) {
                push @invalid, $line;
                next;
            }

            push @emails, {
                email_address => $email,
                first_name => $first_name,
                last_name => $last_name,
            }
        }
    }
    else
    {
        push @invalid, loc("error.email-adress-required");
    }

    return(\@emails, \@invalid);
}

sub _split_email_addresses {
    my $self = shift;
    return grep /\S/, split(/[,\r\n]+\s*/, $_[0]);
}

sub _parse_email_address {
    my $self = shift;
    my $email = shift;

    $email =~ s/^mailto://;
    $email =~ s/^<(.+)>$/$1/;
    return unless defined $email and Email::Valid->address($email);

    my ($address) = Email::Address->parse($email);
    return unless $address;

    my ( $first, $last );
    if ( grep { defined && length } $address->name ) {
        my $name = $address->name;
        $name =~ s/^\s+|\s+$//g;

        ( $first, $last ) = split /\s+/, $name, 2;
    }

    return lc $address->address, $first, $last;
}

1;
