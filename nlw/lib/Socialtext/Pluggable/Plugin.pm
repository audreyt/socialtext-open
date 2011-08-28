package Socialtext::Pluggable::Plugin;
# @COPYRIGHT@
use strict;
use warnings;

use Socialtext;
use Socialtext::HTTP ':codes';
use Socialtext::TT2::Renderer;
use Socialtext::AppConfig;
use Socialtext::Challenger;
use Class::Field qw(const field);
use Socialtext::URI;
use Socialtext::AppConfig;
use Socialtext::JSON qw(encode_json);
use Socialtext::User;
use URI::Escape qw(uri_escape);
use Socialtext::Formatter::Parser;
use Socialtext::Cache;
use Socialtext::Authz::SimpleChecker;
use Socialtext::String ();
use Socialtext::SQL qw(:txn :exec);
use Socialtext::Log qw/st_log/;
use Socialtext::Session;
use Socialtext::PrefsTable;
use Socialtext::UserSet qw/:const/;
use Try::Tiny;

my $prod_ver = Socialtext->product_version;

# Class Methods

my %hooks;
my %content_types;
my %rests;

field hub => -weak;
field 'rest';
field 'declined';
field 'last';
field 'scope_obj';
field 'session', -init => 'Socialtext::Session->new()';

const scope => 'account';
const hidden => 1; # hidden to admins
const paid => 0; # Only show the paid alert for certain plugins
const read_only => 0; # cannot be disabled/enabled in the control panel
const valid_account_prefs => (); # none by default, override in a child.

sub dependencies { } # Enable/Disable dependencies
sub enables {} # Enable only dependencies

sub reverse_dependencies {
    my $class = shift;
    my @rdeps;
    require Socialtext::Pluggable::Adapter;
    for my $pclass (Socialtext::Pluggable::Adapter->plugins) {
        for my $dep ($pclass->dependencies) {
            push @rdeps, $pclass->name if $dep eq $class->name;
        }
    }
    return @rdeps;
}

# perldoc Socialtext::URI for arguments
#    path = '' & query => {}

sub uri {
    my $self = shift;
    return $self->hub->current_workspace->uri . Socialtext::AppConfig->script_name;
}

sub default_workspace {
    my $self = shift;
    return $self->hub->helpers->default_workspace;
}

sub base_uri {
    my $self = shift;
    return $self->{_base_uri} if $self->{_base_uri};
    ($self->{_base_uri} = $self->make_uri) =~ s{/$}{};
    return $self->{_base_uri};
}

sub make_uri {
    my $self = shift;
    return Socialtext::URI::uri(@_);
}

sub current_page_rest_uri {
    my $self = shift;

    my $page = $self->current_page;
    my $ws = $self->current_workspace;
    return unless $page;

    my $type = ($page->is_spreadsheet) ? '/sheets/' : '/pages/';
    return '/data/workspaces/'.$ws->name.$type.$page->id;
}

sub code_base {
   return Socialtext::AppConfig->code_base;
}

sub query {
    my $self = shift;
    return $self->hub->rest->query;
}

sub query_string {
    my $self = shift;
    return $self->hub->cgi->query_string;
}

sub getContent {
    my $self = shift;
    return $self->hub->rest->getContent;
}

sub getContentPrefs {
    my $self = shift;
    return $self->hub->rest->getContentPrefs;
}

sub user {
    my $self = shift;
    return $self->hub->current_user;
}

sub viewer {
    my $self = shift;
    return $self->hub->viewer;
}

sub username {
    my $self = shift;
    return $self->user->username;
}

sub resolve_user {
    my ($self, $username) = @_;
    my $user = eval { Socialtext::User->Resolve($username) };
    $user->hub($self->hub) if $user and $self->hub and !$user->hub;
    return $user;
}

sub authz {
    my $self = shift;
    return $self->hub ? $self->hub->authz : undef;
}

sub best_full_name {
    my ($self,$username) = @_;
    my $person = eval { Socialtext::User->Resolve($username) };
    return $person
        ? $person->guess_real_name()
        : $username;
}

sub header_out {
    my $self = shift;
    my $rest = $self->rest || $self->hub->rest;
    return $rest->header(@_);
}

sub header_in {
    my $self = shift;
    my $rest = $self->rest || $self->hub->rest;
    if (@_) {
        return $rest->request->header_in(@_);
    }
    else {
        return $rest->request->headers_in;
    }
}

sub current_page {
  my $self = shift;

  return $self->hub->pages->current;
}

sub current_workspace { $_[0]->hub->current_workspace }
sub current_workspace_id { $_[0]->current_workspace->workspace_id }

sub add_hook {
    my ($self,$hook,$method,%opts) = @_;
    my $class = ref($self) || $self;
    push @{ $hooks{$class} }, {
        method   => $method,
        name     => $hook,
        class    => $class,
        priority => 50,
        %opts,
    };
}

sub add_content_type {
    my ($self,$name,$visible_name) = @_;
    my $class = ref($self) || $self;
    my $types = $content_types{$class};
    $visible_name ||= ucfirst $name;
    $content_types{$class}{$name} = $visible_name;
}

sub hooks {
    my $self = shift;
    my $class = ref($self) || $self;
    return $hooks{$class} ? @{$hooks{$class}} : ();
}

sub content_types {
    my $self = shift;
    my $class = ref($self) || $self;
    return $content_types{$class};
}

# Object Methods

sub new {
    my ($class, %args) = @_;
    # TODO: XXX: DPL, not sure what args are required but because the object
    # is actually instantiated deep inside nlw we can't just use that data
    my $self = {
#        %args,
    };
    bless $self, $class;
    $self->{Cache} = Socialtext::Cache->cache('ST::Pluggable::Plugin');
    return $self;
}

sub name {
    my $self = shift;

    return $self->{_name} if ref $self and $self->{_name};

    my $class = ref $self || $self;
    my $name = $class->_transform_classname(
        sub { lc( shift ) }
    );

    $self->{_name} = $name if ref $self;
    return $name;
}

sub title {
    my $self = shift;

    return $self->{_title} if ref $self and $self->{_title};

    my $class = ref $self || $self;
    my $title = 'Socialtext ' . $class->_transform_classname(
        sub { shift }
    );

    $self->{_title} = $title if ref $self;
    return $title;
}

sub _transform_classname {
    my $self     = shift;
    my $callback = shift;

    ( my $name = ref $self || $self ) =~ s{::}{/}g;

    # Pull off everything from the name up to and including 'Plugin/',
    # if we can't do that, we should just return everything after the last
    # '/'.
    $name =~ s{^.*/}{}
        unless $name =~ s{^.*?/Plugin/}{}; 

    return &$callback( $name );
}

sub plugins {
    my $self = shift;
    # XXX: should the list be limited like this?
    return grep { $self->user->can_use_plugin($_) } $self->all_plugins
}

sub all_plugins {
    return $_[0]->hub->pluggable->plugin_list;
}

sub plugin_dir {
    my $self = shift;
    my $name = shift || $self->name;
    return $self->code_base . "/plugin/$name";
}

sub cgi_vars {
    my $self = shift;
    return $self->hub->cgi->vars;
}

sub full_uri {
    my $self = shift;
    return $self->hub->cgi->full_uri_with_query;
}

sub challenge {
    my $self = shift;
    Socialtext::Challenger->Challenge(@_);
}

sub redirect_to_login {
    my $self = shift;
    my $uri = uri_escape($ENV{REQUEST_URI} || '');
    return $self->redirect("/challenge?$uri");
}

sub error {
    my $self = shift;
    my %opts = @_;
    my $status = delete $opts{status} || HTTP_500_Internal_Server_Error;
    my $error  = delete $opts{error} || 'An error has occured';

    $self->header_out(-status => $status);
    return $self->template_render(
        'view/error',
        error_string => $error,
    );
}

sub redirect {
    my ($self,$target) = @_;
    unless ($target =~ /^(https?:|\/)/i or $target =~ /\?/) {
        $target = $self->hub->cgi->full_uri . '?' . $target;
    }

    $self->header_out(
        -status => HTTP_302_Found,
        -Location => $target,
    );
    return;
}

sub is_workspace_admin {
    my $self = shift;
    return $self->hub->checker->check_permission('admin_workspace');
}

sub logged_in {
    my $self = shift;
    return 0 unless $self->hub;
    return !$self->hub->current_user->is_guest();
}

sub share {
    my ($self, $plugin) = @_;
    $plugin ||= $self->name;
    return "/nlw/plugin/$prod_ver/$plugin";
}

sub template_paths {
    my $self = shift;
    $self->{_template_paths} ||= [
        glob($self->code_base . "/plugin/*/template"),
    ];
    return $self->{_template_paths};
}

sub template_render {
    my ($self, $template, %args) = @_;

    $self->header_out('Content-Type' => 'text/html; charset=utf-8');

    my $name = $self->name;
    my $plugin_dir = $self->plugin_dir;

    my $renderer = Socialtext::TT2::Renderer->instance;
    return $renderer->render(
        template => $template,
        paths => [
            @{$self->hub->skin->template_paths},
            @{$self->template_paths},
        ],
        vars => {
            %{$self->template_vars},
            %args,
        },
    );
}

sub _get_pref_list {
    my $self = shift;
    my $pref_scope = shift || ($self->hub->current_workspace->real ? 'workspace' : 'global');
    my $prefs = $self->hub->preferences_object->objects_by_class;

    my @pref_list = map {
        $_->{title} =~ s/ /&nbsp;/g;
        $_;
        } grep { $prefs->{ $_->{id} } }
        grep { $_->{id} ne 'search' } # hide search prefs screen
        grep { $_->{pref_scope} eq $pref_scope or $_->{pref_scope} eq 'global' }
        @{ $self->hub->registry->lookup->plugins };
    return \@pref_list;
}

sub template_vars {
    my $self = shift;
    my %template_vars = $self->hub->helpers->global_template_vars;
    return {
        pref_list => sub {
            $self->_get_pref_list;
        },
        share => $self->share,
        workspaces => [$self->hub->current_user->workspaces->all],
        as_json => sub {
            my $json = encode_json(@_);

            # hack so that json can be included in other <script> 
            # sections without breaking stuff
            $json =~ s!</script>!</scr" + "ipt>!g;

            return $json;
        },
        %template_vars,
        $self->{_action_plugin} ?
            (action_plugin => $self->{_action_plugin}) : (),
    }
}

sub created_at {
    my $self = shift;
    my %p = (
        workspace_name => undef,
        page_name => undef,
        @_
    );

    my $page = $self->get_page(%p);
    return undef if (!defined($page));
    return $self->hub->timezone->get_date_user($page->create_time);
}

sub created_by {
    my $self = shift;
    my %p = (
        workspace_name => undef,
        page_name => undef,
        @_
    );

    my $page = $self->get_page(%p);
    return undef if (!defined($page));
    return $page->creator;
}

sub get_revision {
    my $self = shift;
    my %p = (
        workspace_name => undef,
        page_name => undef,
        revision_id => undef,
        @_
    );

    return undef if (!$p{workspace_name} || !$p{revision_id} || !$p{page_name});

    # does permission checks and normalizes the IDs:
    my $page = $self->get_page(map {$_=>$p{$_}} qw(workspace_name page_name));

    return try {
        Socialtext::PageRevision->Get(
            hub => $page->hub,
            page_id => $page->page_id,
            revision_id => $p{revision_id},
        );
    }
    catch {
        warn "unable to load revision $p{revision_id} for $p{workspace_name}/$p{page_name}: $_";
        undef;
    };
}

# REVIEW this should be relying on a Page cache instead of a custom Pluggable
# cache
sub get_page {
    my $self = shift;
    my %p = (
        workspace_name => undef,
        page_name => undef,
        @_
    );

    return undef if (!$p{workspace_name} || !$p{page_name});

    my $page_id = Socialtext::String::title_to_id($p{page_name});
    my $cache_key = "page $p{workspace_name} $page_id";
    my $page = $self->value_from_cache($cache_key);
    return $page if ($page);

    my $workspace = Socialtext::Workspace->new( name => $p{workspace_name} );
    return undef if (!defined($workspace));
    my $auth_check = Socialtext::Authz::SimpleChecker->new(
        user => $self->hub->current_user,
        container => $workspace,
    );
    my $hub = $self->_hub_for_workspace($workspace);
    return undef unless defined($hub);
    return undef unless $auth_check->check_permission('read');

    $page = $hub->pages->new_from_name($p{page_name});
    $self->cache_value(
        key => $cache_key,
        value => $page,
    );
    return $page;
}

sub name_to_id {
    my $self = shift;
    return Socialtext::String::title_to_id(shift);
}

sub _hub_for_workspace {
    my ( $self, $workspace ) = @_;

    my $hub = $self->hub;
    if ( $workspace->name ne $self->hub->current_workspace->name ) {
        $hub = $self->value_from_cache('hub ' . $workspace->name);
        if (!$hub) {
            my $main = Socialtext->new();
            $main->load_hub(
                current_user      => $self->hub->current_user,
                current_workspace => $workspace
            );
            $main->hub->registry->load;

            $hub = $main->hub;
            $self->cache_value(
                key => 'hub ' . $workspace->name,
                value => $hub,
            );
        }
    }

    return $hub;
}

sub cache_value {
    my $self = shift;
    my %p = (
        key => undef,
        value => undef,
        @_
    );

    $self->{Cache}->set($p{key}, $p{value});
}

sub value_from_cache {
    my $self = shift;
    my $key = shift;

    return $self->{Cache}->get($key);
}

sub tags_for_page {
    my $self = shift;
    my %p = (
        page_name => undef,
        workspace_name => undef,
        @_
    );

    my @tags = ();
    my $page = $self->get_page(%p);
    if (defined($page)) {
        push @tags, @{$page->tags};
    }
    return ( grep { lc($_) ne 'recent changes' } @tags );
}

sub search {
    my $self = shift;
    my %p = (
        search_term => undef,
        sortby => 'Relevance',
        limit => 20,
        @_
    );

    $p{sortby} ||= 'Relevance';
    $self->hub->search->dont_use_cached_result_set;
    $self->hub->search->sortby( $p{sortby} );
    # load the search result which may or may not be cached.
    my $set =  $self->hub->search->get_result_set(
       search_term => $p{search_term},
       scope       => '_',
       limit => $p{limit},
    );
    my $rset = $self->hub->search->result_set($set);
    return $rset;
}

sub is_hook_enabled {
    my ($self, $hook_name, $config) = @_;
    
    # Allow us to bypass user scoping by passing a scope object which is
    # something like an account. This is mainly for control panel stuff
    if (my $scope = $config->{scope}) {
        $self->scope_obj($scope);
        return $scope->is_plugin_enabled($self->name);
    }
    $self->scope_obj(undef);

    if ($self->scope eq 'always') {
        return 1;
    }
    elsif ($self->scope eq 'workspace') {
        my $ws = $self->hub ? $self->hub->current_workspace : undef;
        return 1 if $ws and  $ws->real and $ws->is_plugin_enabled($self->name);
    }
    elsif ($self->scope eq 'account') {
        my $user;
        eval {
            $user = $self->hub ? $self->hub->current_user : $self->rest->user;
        };
        return $user->can_use_plugin($self->name) if $user;
    }
    else {
        die 'Unknown scope: ' . $self->scope;
    }
}

sub format_link {
    my ($self, $link, %args) = @_;
    return $self->hub->viewer->link_dictionary->format_link(
        link => $link,
        url_prefix => $self->base_uri,
        %args,
    );
}

# grants access to the low-level Apache::Request
sub request {
    my $self = shift;
    my $rest = $self->rest || $self->hub->rest;
    return $rest->request;
}

# Account Plugin Prefs

sub DefaultAccountPluginPrefs { +{} }
sub CheckAccountPluginPrefs { +{} }
sub LimitAccountPluginPrefs { +{} }

sub GetAccountPluginPrefTable {
    my $class = shift;
    my $acct = shift;
    my $userset_id= $acct + ACCT_OFFSET;
    return Socialtext::PrefsTable->new(
        table    => 'user_set_plugin_pref',
        identity => {
            plugin      => $class->name,
            user_set_id => $userset_id
        },
        defaults => $class->DefaultAccountPluginPrefs,
    );
}

sub _account_plugin_pt {
    my $self = shift;
    my $acct = shift;
    return Socialtext::PrefsTable->new(
        table    => 'user_set_plugin_pref',
        identity => {
            plugin      => $self->name,
            user_set_id => $acct->user_set_id,
        },
        defaults => $self->DefaultAccountPluginPrefs,
    );
}

sub set_account_prefs {
    my $self = shift;
    my %opts = @_;
    my $acct = delete $opts{account};
    return unless %opts;
    $self->_account_plugin_pt($acct)->set(%opts);
    my $acct_name = $acct->name;
    my $username  = $self->hub->current_user->username;
    st_log()->info("$username changed ".$self->name." preferences for $acct_name");
}

sub get_account_prefs {
    my $self = shift;
    my %opts = @_;
    my $acct = $opts{account};
    return $self->_account_plugin_pt($acct)->get();
}

sub clear_account_prefs {
    my $self = shift;
    my %opts = @_;
    my $acct = $opts{account};
    $self->_account_plugin_pt($acct)->clear();
    my $acct_name = $acct->name;
    my $username  = $self->hub->current_user->username;
    st_log()->info("$username cleared ".$self->name." preferences for $acct_name");
}

# Workspace Plugin Prefs

sub _workspace_plugin_pt {
    my $self = shift;
    return Socialtext::PrefsTable->new(
        table    => 'user_set_plugin_pref',
        identity => {
            plugin      => $self->name,
            user_set_id => $self->current_workspace->user_set_id,
        }
    );
}

sub set_workspace_prefs {
    my $self = shift;
    return unless @_;
    $self->_workspace_plugin_pt->set(@_);
    my $username  = $self->hub->current_user->username;
    my $wksp_name = $self->hub->current_workspace->name;
    st_log()->info("$username changed ".$self->name." preferences for $wksp_name");
}

sub get_workspace_prefs {
    my $self = shift;
    return $self->_workspace_plugin_pt->get();
}

sub clear_workspace_prefs {
    my $self = shift;
    $self->_workspace_plugin_pt->clear();

    my $username  = $self->hub->current_user->username;
    my $wksp_name = $self->hub->current_workspace->name;
    st_log()->info("$username cleared ".$self->name." preferences for $wksp_name");
}

# User Plugin Prefs

sub _user_plugin_pt {
    my $self = shift;
    my $user_id = shift || $self->hub->current_user->user_id || die "No user";
    return Socialtext::PrefsTable->new(
        table    => 'user_plugin_pref',
        identity => {
            plugin  => $self->name,
            user_id => $user_id,
        }
    );
}

sub set_user_prefs {
    my $self = shift;
    return unless @_;
    $self->_user_plugin_pt->set(@_);

    my $username  = $self->hub->current_user->username;
    st_log()->info(
        "$username changed their ".$self->name." user plugin preferences");
}

sub get_user_prefs {
    my $self = shift;
    $self->_user_plugin_pt->get(@_);
}

sub clear_user_prefs {
    my $self = shift;
    $self->_user_plugin_pt->clear();

    my $username  = $self->hub->current_user->username;
    st_log()->info(
        "cleared ".$self->name." plugin preferences for user $username");
}

sub export_user_prefs {
    my ($self,$hash) = @_;
    $hash->{$self->name} = $self->get_user_prefs();
}

sub import_user_prefs {
    my ($self,$hash) = @_;

    if (my $prefs = $hash->{$self->name}) {
        if (ref($prefs) eq 'HASH' and keys %$prefs) {
            $self->set_user_prefs(%$prefs);
        }
    }
}

# Plugin Prefs

sub _plugin_pt {
    my $class = shift;
    return Socialtext::PrefsTable->new(
        table    => 'plugin_pref',
        identity => {
            plugin  => $class->name,
        }
    );
}

sub set_plugin_prefs {
    my $class = shift;
    return unless @_;
    $class->_plugin_pt->set(@_);
    st_log()->info("Preferences for ".$class->name." have been changed.");
}

sub get_plugin_prefs {
    my $class = shift;
    return $class->_plugin_pt->get();
}

sub clear_plugin_prefs {
    my $class = shift;
    return $class->_plugin_pt->clear();

    st_log()->info("Preferences for ".$class->name." have been cleared.");
}


sub sheet_renderer {
    my $self = shift;
    my $page_or_ref = shift;

    my $hub;
    my $content_ref;
    if (ref($page_or_ref) eq 'SCALAR') {
        $content_ref = $page_or_ref;
        $hub         = $self->hub;
    }
    else {
        $content_ref = $page_or_ref->body_ref;
        $hub         = $page_or_ref->hub;
    }

    require Socialtext::Sheet;
    my $sheet = Socialtext::Sheet->new(sheet_source => $content_ref);
    return Socialtext::Sheet::Renderer->new(
        sheet => $sheet,
        hub   => $hub,
    );
}

sub date_local {
    return $_[0]->hub->timezone->date_local($_[1]);
}

# Page Plugin Prefs

sub _page_plugin_pt {
    my $self = shift;
    my $workspace_id = shift;
    my $page_name = shift;

    return Socialtext::PrefsTable->new(
        table    => 'page_plugin_pref',
        identity => {
            workspace_id => $workspace_id,
            page_name => $page_name,
            plugin      => $self->name,
        }
    );
}

sub _ws_and_hub_for_page_prefs {
    my $self = shift;
    my %p = (
        workspace_name => undef,
        @_,
    );

    my $user_id = $self->hub->current_user->user_id || die "No user";
    my $ws = Socialtext::Workspace->new(name => $p{workspace_name}) or return (undef, undef);
    my $ws_id = $ws->workspace_id;
    my $auth_check = Socialtext::Authz::SimpleChecker->new(
        user => $self->hub->current_user,
        container => $ws,
    );

    my $hub = $self->_hub_for_workspace($ws);
    return (undef, undef) unless defined($hub);
    return (undef, undef) unless $auth_check->check_permission('read');

    return ($ws, $hub);
}

sub set_page_prefs {
    my $self = shift;
    my %p = (
        workspace_name => undef,
        page_id => undef,
        @_,
    );

    my ($ws, $hub) = $self->_ws_and_hub_for_page_prefs(%p);
    return unless ($ws and $hub);
    my $workspace_name = delete $p{workspace_name};
    my $page_id = delete $p{page_id};
    
    $self->_page_plugin_pt($ws->workspace_id, $page_id)->set(%p);
}

sub get_page_prefs {
    my $self = shift;
    my %p = (
        workspace_name => undef,
        page_id => undef,
        @_,
    );

    my ($ws, $hub) = $self->_ws_and_hub_for_page_prefs(%p);
    return unless ($ws and $hub);
    my $workspace_name = delete $p{workspace_name};
    my $page_id = delete $p{page_id};

    return $self->_page_plugin_pt($ws->workspace_id, $page_id)->get();
}

sub clear_page_prefs {
    my $self = shift;
    my %p = (
        workspace_name => undef,
        page_id => undef,
        @_,
    );

    my ($ws, $hub) = $self->_ws_and_hub_for_page_prefs(%p);
    return unless ($ws and $hub);

    $self->_page_plugin_pt($ws->workspace_id, $p{page_id})->clear();
}

1;
