# @COPYRIGHT@
package Socialtext::Helpers;
use Moose;
use methods-invoker;
use Encode;

# vaguely akin to RubyOnRails' "helpers"
use Socialtext;
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

use namespace::clean -except => 'meta';

extends 'Socialtext::Base';

our $ENABLE_FRAME_CACHE = 0;

use constant class_id => 'helpers';
use constant static_path => "/static/" .  Socialtext->product_version;
use constant script_path => 'index.cgi';

my $supported_format = {
    'en' => '%B %Y',
    'ja' => '%Y年 %m月',
};

method _get_date_format {
    my $locale = $->hub->best_locale;
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

method format_date ($year, $month) {
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

    my $format = $->_get_date_format;
    my $date_str = $format->format_datetime($datetime);
    Encode::_utf8_on($date_str);
    return $date_str;
}


# XXX most of this should become Socialtext::Links or something

method full_script_path {
    '/' . $->hub->current_workspace->name . '/index.cgi'
}

method query_string_from_hash {
    my %query = @_;
    return %query
      ? join '', map { ";$_=$query{$_}" } keys %query
      : '';
}

# XXX need to refactor the other stuff in this file to use this
method script_link($label, %query) {
    my $url = $->script_path . '?' . $->query_string_from_hash(%query);
    return qq(<a href="$url">$label</a>);
}

method page_display_link($name) {
    my $page = $->hub->pages->new_from_name($name);
    return $->page_display_link_from_page($page);
}

method page_display_link_from_page($page) {
    my $path = $->script_path . '?' . $page->uri;
    my $title = $->html_escape($page->name);
    return qq(<a href="$path">$title</a>);
}

method page_display_path($page_name) {
    return $->script_path() . "?$page_name";
}

method page_edit_path($page_name) {
    return $->script_path() . '?' . $->page_edit_params($page_name)
}

# ...aaand we need this one, too.
method page_edit_params($page_name) {
    return 'action=display;page_name='
        . $->uri_escape($page_name)
        . ';js=show_edit_div'
}

has 'default_workspace' => (
    is => 'ro', isa => 'Maybe[HashRef]', lazy_build => 1
);
method _build_default_workspace {
    require Socialtext::Workspace;
    my $ws = Socialtext::Workspace->Default;

    return ( defined $ws && $ws->has_user( $->hub->current_user ) )
        ? { label => $ws->title, link => "/" . $ws->name }
        : undef;
}

method appliance_conf_val($key) {
    # Appliance Code is probably not installed if there's an error.
    local $@;
    eval "require Socialtext::Appliance::Config";
    if ( my $e = $@ ) {
        st_log( 'info', "Could not load Socialtext::Appliance::Config: $e\n" );
        return 0;
    }

    return Socialtext::Appliance::Config->new->value($key);
}

has 'signals_only' => (is => 'ro', isa => 'Bool', lazy_build => 1);
method _build_signals_only {
    $->appliance_conf_val('signals_only');
}

has 'desktop_update_enabled' => (is => 'ro', isa => 'Bool', lazy_build => 1);
method _build_desktop_update_enabled {
    $->appliance_conf_val('desktop_update_enabled');
}

has 'plugins_enabled' => (is => 'ro', isa => 'ArrayRef', lazy_build => 1);
method _build_plugins_enabled {
    return [
        map { $_->name }
        grep {
            $->hub->current_workspace->is_plugin_enabled($_->name) ||
            $->hub->current_user->can_use_plugin($_->name)
        } Socialtext::Pluggable::Adapter->plugins
    ];
}

has 'plugins_enabled_for_ws_account' => (
    is => 'ro', isa => 'ArrayRef', lazy_build => 1
);
method _build_plugins_enabled_for_ws_account {
    return [
        map { $_->name }
        grep {
            $->hub->current_workspace->account->is_plugin_enabled($_->name)
        } Socialtext::Pluggable::Adapter->plugins
    ]
}

has 'ui_is_expanded' => (
    is => 'ro', isa => 'Bool', lazy_build => 1
);
method _build_ui_is_expanded {
    my $cookies = eval { Apache::Cookie->fetch() } || {};
    return defined $cookies->{ui_is_expanded};
}

method global_template_vars {
    my $hub = $->hub;
    my $cur_ws = $->hub->current_workspace;
    my $cur_user = $->hub->current_user;

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
        = $ENABLE_FRAME_CACHE && $->hub->skin->skin_name ne 's2';
    my $frame_name
        = $use_frame_cache ? $->_render_user_frame : 'layout/html';
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
        $thunker->(user      => sub { $->legacy_user_info }),
        $thunker->(wiki      => sub { $->workspace_info }),
        $thunker->(customjs  => sub { $hub->skin->customjs }),
        $thunker->(skin_name => sub { $hub->skin->skin_name }),

        # System stuff
        static_path   => $->static_path,
        system_status => $->hub->main ?
            $->hub->main->status_message() : undef,

        # Themes
        theme => $->theme_info,

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

        $thunker->(miki_url => sub { $->miki_path }),
        $thunker->(desktop_url => sub {
            return '' unless $->desktop_update_enabled;
            return '/st/desktop/badge';
        }),
        $thunker->(stax_info => sub { $hub->stax->hacks_info }),
        $thunker->(workspaceslist => sub {
                $->user_info->{workspaces}
        }),
        $thunker->(default_workspace => sub { $->default_workspace }),
        $thunker->(ui_is_expanded => sub { $->ui_is_expanded }),
        $thunker->('plugins_enabled' => sub { $->plugins_enabled }),
        $thunker->('plugins_enabled_for_current_workspace_account' => sub {
            return $->plugins_enabled_for_ws_account
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
        $thunker->(signals_only => sub { $->signals_only }),
        $thunker->(is_workspace_admin => sub {
                $hub->checker->check_permission('admin_workspace') ? 1 : 0 }),
        $thunker->(js_bootstrap => sub { $->js_bootstrap }),
        $thunker->(can_create_groups => sub {
            !$->user_info->{is_guest} &&
                Socialtext::Group->User_can_create_group(
                    $->hub->current_user
                ) ? 1 : 0
        }),

        $hub->pluggable->hooked_template_vars,
    );

    Socialtext::Timer->Pause('global_tt2_vars');
    return %result;
}

has 'js_bootstrap' => (is => 'rw', isa => 'HashRef', lazy_build => 1);
method _build_js_bootstrap {
    return {
        version => Socialtext->product_version,
        # Socialtext.new_page = [% IF is_new %]true;[% ELSE %]false;[% END %]
        # Socialtext.accept_encoding = [% accept_encoding.json || '""' %];
        loc_lang => $self->hub->best_locale,
        viewer => $->user_info,
        workspace => $->workspace_info,
        dev_mode => $ENV{NLW_DEV_MODE},
        static_path => $->static_path,
        miki_url => $->miki_path,

        invite_url => $->invite_url,

        content_types => $->hub->pluggable->content_types,

        # wikiwyg
        ui_is_expanded => $self->ui_is_expanded,

        Socialtext::AppConfig->debug_selenium
            ? ( UA_is_Selenium => 1 ) : (),

        perms => {
            edit => $->hub->checker->check_permission('edit')
        },
        action => $->hub->cgi->action,

        plugins_enabled => $self->plugins_enabled,
        plugins_enabled_for_current_workspace_account =>
            $self->plugins_enabled_for_ws_account,
    };
}

method add_js_bootstrap ($vars) {
    $->js_bootstrap({ %{$->js_bootstrap}, %$vars });
}

sub clean_user_frame_cache {
    if (-d user_frame_path()) {
        system("find " . user_frame_path() . " -mindepth 1 -print0 | xargs -0 rm -rf");
    }
}

sub user_frame_path {
    return Socialtext::Paths::cache_directory('user_frame');
}

has 'invite_url' => (is => 'ro', isa => 'Maybe[Str]', lazy_build => 1);
method _build_invite_url { $->hub->pluggable->hook('template_var.invite_url') }

method _render_user_frame {
    local $ENABLE_FRAME_CACHE = 0;

    my $frame_path = $->user_frame_path;
    my $user_id = $->hub->current_user->user_id;
    $user_id =~ m/^(\d\d?)/;
    my $user_prefix = $1;

    my $loc_lang = $->hub->best_locale;
    my $is_guest = $->hub->current_user->is_guest ? 1 : 0;

    my $can_invite = $self->invite_url ? 1 : 0;

    my $can_create_group = (
        (!$is_guest
            && Socialtext::Group->User_can_create_group($->hub->current_user)
        ) ? 1 : 0
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
        paths    => $->hub->skin->template_paths,
        vars     => {
            $->hub->helpers->global_template_vars,
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

method theme_info {
    my $account = $->hub->current_user->primary_account;
    my $theme = $account->prefs->all_prefs()->{theme};

    return +{
         st_logo_shade => $theme->{foreground_shade},
         account_logo => $theme->{logo_image_id}
             ? "/data/accounts/".$account->account_id."/theme/images/logo"
             : undef,
         account_favicon => $theme->{favicon_image_id}
             ? "/data/accounts/".$account->account_id."/theme/images/favicon"
             : undef,
    };
}

method miki_path($link) {
    require Socialtext::Formatter::LiteLinkDictionary;

    my $miki_path      = '/m';
    my $page_name      = $->hub->pages->current->name;
    my $workspace_name = $->hub->current_workspace->name;

    if ($workspace_name) {
        $miki_path = Socialtext::Formatter::LiteLinkDictionary->new->format_link(
            link => $link || 'interwiki',
            workspace => $workspace_name,
            page_uri  => $page_name,
        );
    }
    return $miki_path;
}

has legacy_user_info => (is => 'ro', isa => 'HashRef', lazy_build => 1);
method _build_legacy_user_info {
    my $info = $->user_info;
    return {
        %{$->user_info},
        username => $info->{guess_real_name},
        userid => $info->{username},
        id => $info->{user_id},
        can_use_plugin     => sub {
            $->hub->current_user->can_use_plugin(@_);
        },
    }
}

has user_info => (is => 'ro', isa => 'HashRef', lazy_build => 1);
method _build_user_info {
    require Socialtext::Workspace;
    my $user = $->hub->current_user;
    my $ws = Socialtext::Workspace->Default;
    return {
        guess_real_name    => $user->guess_real_name,
        first_name         => $user->first_name,
        middle_name        => $user->middle_name,
        last_name          => $user->last_name,
        username           => $user->username,
        user_id            => $user->user_id,
        email_address      => $user->email_address,
        is_guest           => $user->is_guest,
        is_business_admin  => $user->is_business_admin,
        is_technical_admin => $user->is_technical_admin,
        primary_account_id => $user->primary_account_id,
        accounts           => [
            map {+{
                account_id => $_->account_id,
                name => $_->name,
                plugins => [$_->plugins_enabled],
            }} $user->accounts
        ],
        workspaces         => [
            lsort_by label => map {+{
                label => $_->title,
                name => $_->name,
                account => $_->account->name,
                id => $_->workspace_id,
                ($ws and $ws->name eq $_->name) ? (default => 1) : (),
            }} $->hub->current_user->workspaces->all
        ],
    };
}

# This function is called in the ControlPanel
sub skin_uri { 
    my $skin_name  = shift;
    my $skin = Socialtext::Skin->new(name => $skin_name);
    return $skin->skin_uri();
}

has 'workspace_info' => ( is => 'ro', isa => 'HashRef', lazy_build => 1 );
method _build_workspace_info {
    my $ws = $->hub->current_workspace;
    my $skin = $->hub->skin->skin_name;

    return {
        title         => $ws->title,
        central_page  => Socialtext::String::title_to_id( $ws->title ),
        logo          => $ws->logo_uri_or_default,
        name          => $ws->name,
        has_dashboard => $ws->homepage_is_dashboard,
        is_public     => $ws->permissions->is_public,
        web_uri       => $ws->uri,
        email_address => $ws->email_in_address,
        comment_form_window_height => $ws->comment_form_window_height,
        comment_by_email           => $ws->comment_by_email,
        email_in_address           => $ws->email_in_address,

        allows_html_wafl => $ws->allows_html_wafl,
        enable_spreadsheet => $ws->enable_spreadsheet,
        enable_xhtml => $ws->enable_xhtml,
        account_id => $ws->account_id,
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

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
