package Socialtext::Workspace;
# @COPYRIGHT@
use Moose;
no warnings 'redefine';

use Carp qw(croak);
use Cwd ();
use DateTime;
use DateTime::Format::Pg;
use Digest::MD5;
use Email::Address;
use File::Copy ();
use File::Find ();
use File::Path ();
use File::Temp ();
use IPC::Run qw/run/;
use List::MoreUtils ();
use Socialtext;
use Socialtext::AppConfig;
use Socialtext::EmailAlias;
use Socialtext::Events;
use Socialtext::File;
use Socialtext::Helpers;
use Socialtext::Image;
use Socialtext::l10n qw(loc system_locale);
use Socialtext::Log qw( st_log );
use Socialtext::SQL qw(:exec :txn);
use Socialtext::SQL::Builder qw(sql_nextval);
use Socialtext::String;
use Readonly;
use Socialtext::Account;
use Socialtext::Cache;
use Socialtext::Permission qw( ST_EMAIL_IN_PERM ST_READ_PERM ST_IMPERSONATE_PERM );
use Socialtext::Role;
use Socialtext::URI;
use Socialtext::MIME::Types;
use Socialtext::MultiCursor;
use Socialtext::User;
use Socialtext::UserSet qw/:const/;
use Socialtext::WorkspaceBreadcrumb;
use Socialtext::Page;
use Socialtext::Workspace::Permissions;
use Socialtext::Workspace::Roles;
use Socialtext::Timer qw/time_scope/;
use Socialtext::Pluggable::Adapter;
use Socialtext::JSON qw(decode_json);
use Socialtext::JSON::Proxy::Helper;
use URI;
use YAML;
use Encode qw(decode_utf8);
use Socialtext::Exceptions
    qw( rethrow_exception param_error data_validation_error );
use Socialtext::Validate qw(
    validate validate_pos SCALAR_TYPE BOOLEAN_TYPE ARRAYREF_TYPE
    HANDLE_TYPE URI_TYPE USER_TYPE ROLE_TYPE PERMISSION_TYPE FILE_TYPE
    DIR_TYPE UNDEF_TYPE
);

use namespace::clean -except => 'meta';

our $VERSION = '0.01';
# for workspace exports:
Readonly my $EXPORT_VERSION => 1;

Readonly our @COLUMNS => (
    'workspace_id',
    'name',
    'title',
    'logo_uri',
    'homepage_weblog',
    'email_addresses_are_hidden',
    'unmasked_email_domain',
    'prefers_incoming_html_email',
    'incoming_email_placement',
    'allows_html_wafl',
    'email_notify_is_enabled',
    'sort_weblogs_by_create',
    'external_links_open_new_window',
    'basic_search_only',
    'skin_name',
    'custom_title_label',
    'header_logo_link_uri',
    'show_welcome_message_below_logo',
    'show_title_below_logo',
    'comment_form_note_top',
    'comment_form_note_bottom',
    'comment_form_window_height',
    'page_title_prefix',
    'email_notification_from_address',
    'email_weblog_dot_address',
    'comment_by_email',
    'homepage_is_dashboard',
    'creation_datetime',
    'account_id',
    'created_by_user_id',
    'restrict_invitation_to_search',
    'invitation_filter',
    'invitation_template',
    'customjs_uri',
    'customjs_name',
    'no_max_image_size',
    'cascade_css',
    'uploaded_skin',
    'allows_skin_upload',
    'allows_page_locking',
    'user_set_id',
);

use constant real => 1;

# Hash for quick lookup of columns
my %COLUMNS = map { $_ => 1 } @COLUMNS;

foreach my $column ( grep !/^skin_name$/, @COLUMNS ) {
    has $column => (is => 'rw', isa => 'Any');
}
has 'skin_name' => (is => 'rw', isa => 'Str', default => '');

has 'permissions' => (
    is => 'rw', isa => 'Socialtext::Workspace::Permissions',
    lazy_build => 1,
    handles => [qw(
        user_can
    )],
);

with 'Socialtext::UserSetContainer',
     'Socialtext::UserSetContained' => {
        # Moose 0.89 renamed to -excludes and -alias
        ($Moose::VERSION >= 0.89 ? '-excludes' : 'excludes')
            => [qw(sorted_workspace_roles)]
     };


# XXX: This is here to support the non-plugin method of checking whether
# socialcalc is enabled or not.
sub enable_spreadsheet {
    my ($self, $option) = @_;
    return $self->is_plugin_enabled('socialcalc');
}

sub enable_xhtml {
    my ($self, $option) = @_;
    return $self->is_plugin_enabled('ckeditor');
}

# Special case the "help" workspace.  Since existing Wikitext (and rarely used
# code) still refer to the "help" workspace, we need to capture that here and
# call help_workspace(), which should automagically load up the right
# workspace.
sub new {
    my ( $class, %args ) = @_;
    if ( $args{name} and $args{name} eq 'help' ) {
        delete $args{name};
        return $class->help_workspace(%args);
    }

    return $class->_new(%args);
}

# This is in _new() b/c of now migration 13 works.  Please read that migration
# before you move this code.
sub _new {
    my ( $class, %args ) = @_;

    my $sth;
    if ($args{name}) {
        my $name = lc $args{name};
        if (my $ws = $class->cache->get("name:$name")) {
            return $ws;
        }
        $sth = sql_execute(
            qq{SELECT * FROM "Workspace" WHERE LOWER(name) = ?}, $name,
        );
    }
    elsif (my $id = $args{workspace_id}) {
        if (my $ws = $class->cache->get("id:$id")) {
            return $ws;
        }
        $sth = sql_execute(
            qq{SELECT * FROM "Workspace" WHERE workspace_id = ?}, $id,
        );
    }
    else {
        return;
    }

    # Sure there's a better way to make use of the row we're getting back.
    my $row = $sth->fetchrow_hashref();
    my $new_obj = $class->new_from_hash_ref($row);

    if ($new_obj) {
        $class->cache->set("name:" . $new_obj->name => $new_obj);
        $class->cache->set("id:" . $new_obj->workspace_id => $new_obj);
    }

    return $new_obj;
}

sub guest_has_email_in {
    my $self = shift;

    return $self->permissions->role_can(
        role       => Socialtext::Role->Guest(),
        permission => ST_EMAIL_IN_PERM,
    );
}

sub new_from_hash_ref {
    my ( $class, $row ) = @_;
    return $row unless $row;
    return Socialtext::NoWorkspace->new if $row->{workspace_id} == 0;

    # Make sure that workspaces with UTF-8 titles display properly.
    # Keep an eye out for other places that we may need to do this.
    $row->{title} = decode_utf8( $row->{title} );

    return bless $row, $class;
}

sub create {
    my $class = shift;
    my %p = @_;
    my $timer = Socialtext::Timer->new;

    my $skip_pages       = delete $p{skip_default_pages};
    my $clone_pages_from = delete $p{clone_pages_from};
    my $dont_add_creator = delete $p{dont_add_creator} || 0;

    my $self;
    sql_txn {
        $class->_validate_and_clean_data(\%p);
        delete $p{workspace_id};
        delete $p{user_set_id};
        my $keys = join(',', sort keys %p);
        my $vals = join(',', map {'?'} keys %p);

        my $ws_id = sql_nextval('"Workspace___workspace_id"');
        my $user_set_id = $ws_id + WKSP_OFFSET;

        my $sql = <<EOSQL;
INSERT INTO "Workspace" ( workspace_id, user_set_id, $keys )
    VALUES (?, ?, $vals)
EOSQL
        sql_execute($sql, $ws_id, $user_set_id, map { $p{$_} } sort keys %p);

        $self = $class->new(workspace_id => $ws_id);

        my $creator = $self->creator;
        if (!$creator->is_system_created && !$dont_add_creator) {
                 $self->add_user(
                user => $creator,
                role => Socialtext::Role->Admin(),
            );
        }

        $self->permissions->set( set_name => 'member-only' );
    };

    if ( $clone_pages_from ) {
        $self->clone_workspace_pages( $clone_pages_from );
    }
    else {
        $self->_copy_default_pages
            unless $skip_pages;
    }

    $self->_update_aliases_file();
    $self->_enable_default_plugins();

    $self->account->user_set->add_object_role($self, 'member');

    my $msg = 'CREATE,WORKSPACE,workspace:' . $self->name
              . '(' . $self->workspace_id . '),'
              . '[' . $timer->elapsed . ']';
    st_log()->info($msg);

    return $self;
}

# Load the right help workspace for the current system locale.
sub help_workspace {
    my ( $class, %args ) = @_;
    my $ws;
    delete $args{name};
    for my $locale ( system_locale(), "en" ) {
        $ws ||= $class->new( name => "help-$locale", %args );
    }
    return $ws;
}

# Return the list of help workspaces on this appliances
sub Help_workspaces {
    my $class = shift;

    my $share_dir = Socialtext::AppConfig->new->code_base();
    my $help_dir = "$share_dir/l10n/help";
    return
        map { s#.+/(help-.+)\.tar\.gz$#$1#; $_ }
        glob("$help_dir/help-*.tar.gz");
}

sub clone_workspace_pages {
    my $self    = shift;
    my $ws_name = shift;

    my $ws = Socialtext::Workspace->new( name => $ws_name ) || return;
    my $clone_hub = $self->_hub_for_workspace( $ws_name );
    my @pages =  
        grep { !$_->deleted }
        grep { $_->page_id !~ /_workspace_usage_.+_past_week$/ }
        $clone_hub->pages->all();

    my ( $main, $hub ) = $self->_main_and_hub();
    my $homepage_id = $hub->pages->new_from_name( $ws->title )->id;

    $self->_add_workspace_pages(
        homepage_id              => $homepage_id,
        keep_homepage_categories => 1,
        pages                    => \@pages
    );
}

sub _copy_default_pages {
    my $self = shift;
    my ( $main, $hub ) = $self->_main_and_hub();

    # Load up the help workspace, and a corresponding hub.
    my $help     = (Socialtext::Workspace->help_workspace() || return)->name || return;
    my $help_hub = $self->_hub_for_workspace( $help );

    # Get all the default pages from the help workspace
    my @pages = $help_hub->category->get_pages_for_category( loc("wiki.welcome") );
    push @pages, $help_hub->category->get_pages_for_category( loc("wiki.top-page") );

    my $homepage_id = ( system_locale() eq 'ja' )
        ? '%E3%83%88%E3%83%83%E3%83%97%E3%83%9A%E3%83%BC%E3%82%B8'
        : 'top_page';

    $self->_add_workspace_pages(
        homepage_id => $homepage_id,
        pages       => \@pages
    );
}

sub _hub_for_workspace {
    my $self      = shift;
    my $ws_name   = shift;

    my $ws = Socialtext::Workspace->new( name => $ws_name );
    my $hub = Socialtext->new->load_hub(
        current_workspace => $ws,
        current_user      => Socialtext::User->SystemUser,
    );

    $hub->registry->load;

    return $hub;
}

# Top Page is special.  We need to name the page after the current
# workspace, not "Top Page", and we need to add the current workspace
# title to the page content (there's some TT2 in the wikitext).
sub _add_workspace_pages {
    my $self            = shift;
    my %params          = @_;
    my $top_page_id     = $params{homepage_id};
    my $keep_categories = $params{keep_homepage_categories};
    my @pages           = @{ $params{pages} };

    # Duplicate the pages
    for my $page (@pages) {
        $page->edit_rev();
        my $title = $page->name;

        if ($page->id eq $top_page_id) {
            my ($main, $hub) = $self->_main_and_hub();
            $title = $self->title;  # name it after this workspace
            # don't assign process() output to a var for speed/space
            $page->content($hub->template->process(
                $page->body_ref,
                workspace_title => $self->title
            ));
            $page->tags([]) unless $keep_categories;
        }
        else {
            $page->delete_tag("Top Page");
        }

        $page->duplicate(
            $self,        # Destination workspace
            $title,
            "keep tags",
            "keep attachments",
            $title,      # Ok to overwrite existing pages named $title
        );
    }
}

# used by Socialtext::Pages too
sub _main_and_hub {
    my $self = shift;
    my $user = shift || Socialtext::User->SystemUser();

    my $main = Socialtext->new;
    my $hub = $main->load_hub(
        current_workspace => $self,
        current_user      => $user,
    );
    $hub->registry->load;

    return ( $main, $hub );
}

sub _update_aliases_file {
    my $self = shift;

    Socialtext::EmailAlias::create_alias( $self->name );
}

sub _enable_default_plugins {
    my $self = shift;
    require Socialtext::SystemSettings;
    require Socialtext::Pluggable::Adapter;
    for my $p (Socialtext::Pluggable::Adapter->plugins) {
        next if $p->scope ne 'workspace';
        my $plugin = $p->name;
        next if $plugin eq 'socialcalc'
            and $self->account->account_type eq 'Free 50';
        $self->enable_plugin($plugin)
            if Socialtext::SystemSettings::get_system_setting(
                "$plugin-enabled-all"
            );
    }
}

sub update {
    my $self = shift;
    my %args = @_;

    delete $self->{skin_info}{$_} for keys %args;

    my $old_title = $self->title();

    $self->_update(@_);
    $self->cache->clear();

    if ( $self->title() ne $old_title ) {
        my ( $main, $hub ) = $self->_main_and_hub();

        # Re-index all the pages, so Solr knows about the new title
        $self->reindex_async($hub, 'live');

        my $page = $hub->pages->new_from_name($old_title);

        return unless $page->active();

        $page->rename(
            $self->title(),
            'keep categories',
            'keep attachments',

            # forces the rename to replace an existing page
            $self->title(),
        );
    }
}

sub _update {
    my ( $self, %p ) = @_;

    $self->_validate_and_clean_data(\%p);
    my $old_account = $self->account;

    my ( @updates, @bindings );
    while (my ($column, $value) = each %p) {
        push @updates, "$column=?";
        push @bindings, $value;
    }

    return unless @updates;

    my $set_clause = join ', ', @updates;
    sql_execute(
        'UPDATE "Workspace"'
        . " SET $set_clause WHERE workspace_id=?",
        @bindings, $self->workspace_id);

    while (my ($column, $value) = each %p) {
        $self->$column($value);
    }

    my $new_account = $self->account;
    if ( $old_account->account_id != $new_account->account_id ) {
        $old_account->user_set->remove_object_role($self);
        $new_account->user_set->add_object_role($self => 'member');
        my $users = $self->users;
        while ( my $user = $users->next ) {
            require Socialtext::JobCreator;
            Socialtext::JobCreator->index_person($user);
        }
    }

    return $self;
}

# turn a workspace into a hash suitable for JSON and such things.
sub to_hash {
    my $self = shift;
    my %opts = @_;
    my $t = time_scope 'wksp_to_hash';

    my $hash = { map { $_ => $self->$_ } @COLUMNS };
    return $hash if $opts{minimal};

    $hash->{account_name} = $self->account->name;
    $hash->{is_all_users_workspace}
        = $self->is_all_users_workspace ? 1 : 0;

    return $hash;
}

sub delete_search_index {
    my $self = shift;
    my $ws_name = $self->name;

    my @indexers = Socialtext::Search::AbstractFactory->GetIndexers($ws_name);
    for my $indexer (@indexers) {
        $indexer->delete_workspace( $ws_name );
    }
}

around assign_role_to_user => sub {
    my $orig = shift;
    my $self = shift;
    my %p = (
        user => undef, role => undef, actor => undef, reckless => 0, @_);

    my $currentRole = $self->role_for_user($p{user}, direct => 1);
    if ($currentRole and !$p{reckless}) {
        my $admin = Socialtext::Role->Admin();
        if ($currentRole->role_id == $admin->role_id
             and $p{role}->role_id != $admin->role_id) {
            my $count = $self->role_count(
                role   => Socialtext::Role->Admin(),
                direct => 1,
            );
            Socialtext::Exception::User->throw(
                error => 'ADMIN_REQUIRED',
                user => $p{user},
                username => $p{user}->username,
            ) if $count < 2;
        }
    }

    $orig->($self, %p);
};

around assign_role_to_group => sub {
    my $orig = shift;
    my $self = shift;
    my %p = @_;

   $p{role} ||= $self->role_default($p{group});

    my $current_role = $self->role_for_group($p{group}, direct => 1);
    return if $current_role && $current_role->role_id == $p{role}->role_id;

    my $admin = Socialtext::Role->Admin();
    my $new_is_admin = $p{role}->role_id == $admin->role_id;
    my $is_admin = $current_role && $current_role->role_id == $admin->role_id;

    if ($is_admin && !$new_is_admin && !$p{reckless}) {
        my $admin_count = $self->role_count(role => $admin, direct => 1);

        Socialtext::Exception::Conflict->throw(error => 'ADMIN_REQUIRED')
            unless $admin_count > 1;
    }

    $orig->($self, %p);
};

around remove_user => sub {
    my $orig = shift;
    my $self = shift;
    my %p = (
        user => undef,
        reckless => 0,
        @_
    );

    unless ($p{reckless}) {
        my $userRole = $self->role_for_user($p{user}, direct => 1);
        my $admin = Socialtext::Role->Admin();
        if ($userRole->name eq $admin->name) {
            my $count = $self->role_count(
                role => Socialtext::Role->Admin(),
                direct => 1,
            );
            Socialtext::Exception::User->throw(
                error => 'ADMIN_REQUIRED',
                user => $p{user},
                username => $p{user}->username,
            ) if $count < 2;
        }
    }

    $orig->($self, %p);
};

around remove_group => sub {
    my $orig = shift;
    my $self = shift;
    my %p = @_;

    unless ($p{reckless}) {
        my $current_role = $self->role_for_group($p{group}, direct => 1);
        Socialtext::Exception::Conflict->throw(error => 'NO_ROLE')
            unless $current_role;

        my $admin = Socialtext::Role->Admin();

        if ($current_role->role_id == $admin->role_id) {
            my $admin_count = $self->role_count(role => $admin, direct => 1);

            Socialtext::Exception::Conflict->throw(error => 'ADMIN_REQUIRED')
                unless $admin_count > 1;
        }
    }

    $orig->($self, %p);
};

sub delete {
    my $self = shift;
    my $timer = Socialtext::Timer->new;
    my $ws_name = $self->name;

    $self->delete_search_index();

    my $mc = $self->users();
    while ( my $user = $mc->next() ) {
        $self->remove_user(user => $user, reckless => 1);
    }

    Socialtext::EmailAlias::delete_alias( $self->name );

    sql_execute( 'DELETE FROM "Workspace" WHERE workspace_id=?',
        $self->workspace_id );

    $self->cache->clear();

    # clean up any un-referenced uploads (which won't cascade from
    # page_attchment when the workspace is nuked)
    Socialtext::JobCreator->tidy_uploads();

    st_log()
        ->info( 'DELETE,WORKSPACE,workspace:'
            . $self->name . '('
            . $self->workspace_id
            . '),[' . $timer->elapsed . ']' );
}

my %ReservedNames = map { $_ => 1 } qw(
    account
    administrate
    administrator
    atom
    attachment
    attachments
    category
    control
    console
    data
    feed
    nlw
    noauth
    page
    recent-changes
    rss
    search
    soap
    static
    st-archive
    superuser
    test-selenium
    workspace
    user
);

sub _validate_and_clean_data {
    my $self = shift;
    my $p = shift;

    my $is_create = ref $self ? 0 : 1;

    # XXX - this is really gross - I want to force people to use the
    # set_logo_* API to set the logo, but then set_logo_* eventually
    # calls this method.
    if ( $p->{logo_uri} and ( $is_create or not $self->{allow_logo_uri_update_HACK} ) ) {
        my $meth = $is_create ? 'create()' : 'update()';
        die 'Cannot set logo_uri via ' . $meth . '.'
            . ' Use set_logo_from_file() or set_logo_from_uri().';
    }

    if ( defined $p->{name} and not $is_create and not $self->{allow_rename_HACK} ) {
        die "Cannot rename workspace via update(). Use rename() instead.";
    }

    my @errors;
    {
        $p->{name} = Socialtext::String::scrub( $p->{name} )
            if defined $p->{name};

        if ( ( exists $p->{name} or $is_create )
             and not
             ( defined $p->{name} and length $p->{name} ) ) {
            push @errors, loc("error.wiki-name-required");
        }
    }

    {
        $p->{title} = Socialtext::String::scrub( $p->{title} )
            if defined $p->{title};

        if ( ( exists $p->{title} or $is_create )
             and not
             ( defined $p->{title} and length $p->{title} ) ) {
            push @errors, loc("error.wiki-title-required");
        }
    }

    if ( defined $p->{name} ) {
        $p->{name} = lc $p->{name};

        Socialtext::Workspace->NameIsValid( name => $p->{name},
                                            errors => \@errors );

        if ( Socialtext::EmailAlias::find_alias( $p->{name} ) ) {
            push @errors, loc("error.wiki-email-alias-exists=name", $p->{name});
        }

        if ( Socialtext::Workspace->new( name => $p->{name} ) ) {
            push @errors, loc("error.wiki-exists=name", $p->{name});
        }
    }

    if ( defined $p->{title} ) {
        Socialtext::Workspace->TitleIsValid( title => $p->{title},
                                            errors => \@errors );
    }

    if ( $p->{incoming_email_placement}
         and $p->{incoming_email_placement} !~ /^(?:top|bottom|replace)$/ ) {
        push @errors, loc('error.invalid-email-placement');
    }

    if ($p->{skin_name}) {
        my $skin = Socialtext::Skin->new(name => $p->{skin_name});
        delete $p->{skin_name} unless ($skin->exists);
    }

    if ( $is_create and not $p->{account_id} ) {
        push @errors, loc("error.account-for-new-wiki-required");
    }

    if ($p->{account_id}) {
        my $account = Socialtext::Account->new(account_id => $p->{account_id});

        if ( $account ) {
            if ( ! $is_create and $self->is_all_users_workspace ) {
                push @errors, loc("error.delete-auw-workspace", $self->account->name);
            }
        }
        else {
            push @errors,
                loc("error.no-account=id",
                    $p->{account_id});
        }
    }

    data_validation_error errors => \@errors if @errors;

    if ( $p->{logo_uri} ) {
        $p->{logo_uri} = URI->new( $p->{logo_uri} )->canonical . '';
    }

    if ($is_create) {
        $p->{created_by_user_id} ||= $p->{creator}->user_id
            if (exists $p->{creator});
        $p->{created_by_user_id} ||= Socialtext::User->SystemUser()->user_id();
    }

    # Remove keys that aren't columns, or are undef
    for my $k (keys %$p) {
        delete $p->{$k} unless $COLUMNS{$k};
        delete $p->{$k} unless defined $p->{$k};
    }

    # You should never update the user_set_id
    delete $p->{user_set_id};

    # Make uploaded_skin into a boolean
    if (exists $p->{uploaded_skin}) {
        $p->{uploaded_skin} = ($p->{uploaded_skin} ? 1 : 0);
    }
}


sub TitleIsValid {
    my $class = shift;

    my %p = Params::Validate::validate( @_, {
        title    => SCALAR_TYPE,
        errors  => ARRAYREF_TYPE( default => [] ),
    } );

    my $title    = $p{title};
    my $errors  = $p{errors};

    unless (    defined $title
        and ( length $title >= 2 )
        and ( length $title <= 64 )
        and ( $title !~ /^-/ ) ) {
        push @{$errors},
            loc(
            "error.invalid-wiki-title"
            );
    }

    if ( defined $title
         and ( length Socialtext::String::title_to_id($title) > Socialtext::String::MAX_PAGE_ID_LEN )
       ) {
        push @{$errors}, loc('error.wiki-title-too-long');
    }

    return @{$errors} > 0 ? 0 : 1;
}

sub NameIsIllegal {
    my $class = shift;
    my $name = shift;
    return $name !~ /^[a-z0-9_\-]{3,30}$/;
}

sub NameIsValid {
    my $class = shift;

    # The validation spec is specified here, instead of outside
    # the sub, so that any default 'errors' arrayref will be different on
    # each call. If the spec is defined outside this scope, then the same
    # arrayref will be used for every call with a defaulted 'errors'
    # parameter, mistakenly preserving the error list between calls.
    #
    my %p = Params::Validate::validate( @_, {
        name    => SCALAR_TYPE,
        errors  => ARRAYREF_TYPE( default => [] ),
    } );

    my $name    = $p{name};
    my $errors  = $p{errors};

    if ( $class->NameIsIllegal($name) ) {
        push @{$errors},
            loc("error.invalid-wiki-name");
    }

    if ( $name =~ /^-/ ) {
        push @{$errors},
            loc('error.invalid-wiki-name-begins-with-dash');
    }

    if ( $ReservedNames{$name} || ($name =~ /^st_/i) ) {
        push @{$errors},
            loc("error.reserved-name=wiki", $name);
    }

    return @{$errors} > 0 ? 0 : 1;
}


{
    Readonly my $spec => { name => SCALAR_TYPE };
    sub rename {
        my $self = shift;
        my %p    = validate( @_, $spec );
        my $timer = Socialtext::Timer->new;

        my $old_name  = $self->name();

        local $self->{allow_rename_HACK} = 1;
        $self->update( name => $p{name} );

        Socialtext::EmailAlias::delete_alias($old_name);
        $self->_update_aliases_file();

        $self->cache->clear();

        st_log()
            ->info( 'RENAME,WORKSPACE,old_workspace:'
                . $old_name . '(' . $self->workspace_id . '),'
                . 'new_workspace:' . $p{name} . '('
                . $self->workspace_id
                . '),[' . $timer->elapsed . ']' );
    }
}

sub reindex_async {
    my $self = shift;
    my $hub  = shift;
    my $search_config = shift;

    require Socialtext::JobCreator;
    for my $page_id ( $hub->pages->all_ids() ) {
        my $page = $hub->pages->new_page($page_id);
        next if $page->deleted;
        Socialtext::JobCreator->index_page(
            $page, $search_config,
            priority => 62,
        );
    }
}

sub uri {
    my $self = shift;

    return Socialtext::URI::uri(
        path   => $self->name . '/',
    );
}

sub email_in_address {
    my $self = shift;

    return $self->name . '@' . Socialtext::AppConfig->email_hostname;
}

sub formatted_email_notification_from_address {
    my $self = shift;

    return Email::Address->new( $self->title(),
        $self->email_notification_from_address() )->format();
}

sub logo_uri_or_default {
    my $self = shift;
    my ( $main, $hub ) = $self->_main_and_hub();

    return $self->logo_uri if $self->logo_uri;

    return Socialtext::Skin->new(name => 's2')->skin_uri(
        qw(images st logo socialtext-logo-152x26.gif)
    );
}

sub logo_filename {
    my $self = shift;

    my $uri = $self->logo_uri;
    return unless $uri and $uri =~ m{^/logos/};

    my ($filename) = $uri =~ m{([^/]+)$};
    my $file = Socialtext::File::catfile( $self->_logo_path, $filename );

    return unless -f $file;
    return $file;
}

{
    Readonly my %ValidTypes => (
        'image/jpeg' => 'jpg',
        'image/gif'  => 'gif',
        'image/png'  => 'png',
    );

    sub set_logo_from_file {
        my $self = shift;
        my %p = @_;

        my $mime_type = Socialtext::MIME::Types::mimeTypeOf($p{filename});
        unless ( $mime_type and $ValidTypes{$mime_type} ) {
            data_validation_error errors => [ loc("error.invalid-logo-image-type") ];
        }

        my $new_file = $self->_new_logo_filename( $ValidTypes{$mime_type} );
        # 0775 is intentional on the theory that the directory
        # owner:group will be something like root:www-data
        File::Path::mkpath( File::Basename::dirname($new_file), 0, 0775 );

        # This can fail in a variety of ways, mostly related to
        # the file not being what it says it is.
        File::Copy::copy($p{filename}, $new_file)
            or die "Could not copy $p{filename} to $new_file $!\n";
        eval {
            Socialtext::Image::resize(
                max_width  => 200,
                max_height => 60,
                filename   => $new_file,
            );
        };
        if ($@) {
            data_validation_error errors =>
                [loc('error.invalid-wiki-logo?')];
        }

        my $old_logo_file = $self->logo_filename();

        my $logo_uri = join '/', '/logos', $self->name, File::Basename::basename($new_file);

        local $self->{allow_logo_uri_update_HACK} = 1;
        $self->update( logo_uri => $logo_uri  );

        if ( $old_logo_file and $old_logo_file ne $self->logo_filename() ) {
            unlink $old_logo_file or die "Cannot unlink $old_logo_file: $!";
        }
    }
}

{
    # The uri can be either an external URI or just a path
    Readonly my $spec => { uri => SCALAR_TYPE };
    sub set_logo_from_uri {
        my $self = shift;
        my %p = validate( @_, $spec );

        return if $self->logo_uri and $self->logo_uri eq $p{uri};

        $self->_delete_existing_logo();

        local $self->{allow_logo_uri_update_HACK} = 1;
        $self->update( logo_uri => $p{uri} );
    }
}

sub _delete_existing_logo {
    my $self = shift;

    my $file = $self->logo_filename
        or return;

    unlink $file or die "Cannot unlink $file: $!";
}

#
# This particular file name scheme is designed so that by looking at
# the filename, we can know what workspace a logo belongs to, but it
# is not possible to snoop for logos by simply guessing workspace
# names and fishing for that URI. This means that we can (reasonably)
# safely serve the logos without checking authorization
#
sub _new_logo_filename {
    my $self = shift;
    my $type = shift;

    my $path = $self->_logo_path;
    my $filename = $self->name;
    $filename .= '-' . Digest::MD5::md5_hex( $self->name, Socialtext::AppConfig->MAC_secret );
    $filename .= ".$type";

    return Socialtext::File::catfile( $path, $filename );
}

sub LogoRoot {
    return Socialtext::File::catdir( Socialtext::AppConfig->data_root_dir, 'logos' );
}

sub _logo_path {
    my $self = shift;

    return Socialtext::File::catdir( $self->LogoRoot, $self->name );
}

sub title_label {
    my $self = shift;

    return
        $self->custom_title_label
        ? $self->custom_title_label
        : $self->permissions->is_public
        ? 'Eventspace'
        : 'Workspace';
}

sub creation_datetime_object {
    my $self = shift;

    # XXX This should be cached in the object?
    return DateTime::Format::Pg->parse_timestamptz( $self->creation_datetime );
}

sub creator {
    my $self = shift;

    # XXX This should be cached in the object?
    return Socialtext::User->new( user_id => $self->created_by_user_id );
}

sub account {
    my $self = shift;

    # XXX This should be cached in the object?
    return Socialtext::Account->new( account_id => $self->account_id );
}

sub is_all_users_workspace {
    my $self        = shift;

    # XXX This should be cached in the object?
    return $self->role_for_account( $self->account, direct => 1 );
}

{
    Readonly my $spec => { uris => ARRAYREF_TYPE };
    sub set_ping_uris {
        my $self = shift;
        my %p = validate( @_, $spec );

        my @errors;
        my @uris;
        for my $uri ( grep { defined && length } @{ $p{uris} } ) {
            $uri = URI->new($uri)->canonical;
            unless ( $uri =~ m{^https?://} ) {
                push @errors, $uri . ' is not a valid blog ping URI';
                next;
            }

            push @uris, $uri;
        }

        data_validation_error errors => \@errors if @errors;

        sql_txn {
            sql_execute(
                'DELETE FROM "WorkspacePingURI" WHERE workspace_id = ?',
               $self->workspace_id,
            );

            for my $uri ( List::MoreUtils::uniq(@uris) ) {
                sql_execute(
                    'INSERT INTO "WorkspacePingURI" VALUES(?,?)',
                    $self->workspace_id,
                    $uri
                );
            }
        };
    }
}

sub ping_uris {
    my $self = shift;

    my $sth = sql_execute(
        'SELECT uri FROM "WorkspacePingURI" WHERE workspace_id = ?',
        $self->workspace_id,
    );
    my $uris = $sth->fetchall_arrayref;
    return map { $_->[0] } @$uris;
}

{
    Readonly my $spec => { fields => ARRAYREF_TYPE };
    sub set_comment_form_custom_fields {
        my $self = shift;
        my %p = validate( @_, $spec );

        my @fields = grep { defined && length } @{ $p{fields} };

        sql_txn {
            sql_execute(
                'DELETE FROM "WorkspaceCommentFormCustomField" '
                . 'WHERE workspace_id = ?',
                $self->workspace_id,
            );

            my $i = 1;
            for my $field ( List::MoreUtils::uniq(@fields) ) {
                sql_execute(
                    'INSERT INTO "WorkspaceCommentFormCustomField"
                        VALUES(?,?,?)',
                    $self->workspace_id, $field, $i++,
                );
            }
        };
    }
}

# Wrap methods in UserSetContainer.
# Note that we need to say that we're enabling plugins at the workspace scope.
around 'enable_plugin','disable_plugin' => sub {
    my $code = shift;
    my ($self,$plugin) = @_;
    return unless $self->real;
    return $self->$code($plugin, 'workspace');
};

after 'enable_plugin','disable_plugin' => sub {
    Socialtext::Helpers->clean_user_frame_cache();
};

sub comment_form_custom_fields {
    my $self = shift;

    my $sth = sql_execute(
        'SELECT field_name FROM "WorkspaceCommentFormCustomField"
            WHERE workspace_id = ?
            ORDER BY field_order',
        $self->workspace_id,
    );
    my $fields = $sth->fetchall_arrayref;
    return map { $_->[0] } @$fields;
}

sub _build_permissions {
    my $self = shift;
    return Socialtext::Workspace::Permissions->new(wksp => $self);
}

sub email_passes_invitation_filter {
    my $self   = shift;
    my $email  = shift;
    my $filter = $self->invitation_filter or return 1;
    return($email and $email =~ qr/$filter/i);
}

after 'role_change_event' => sub {
    my ($self,$actor,$change,$object,$role) = @_;

    if ($object->isa('Socialtext::User')) {
        $self->_user_role_changed($actor,$change,$object,$role);
    }
    elsif ($object->isa('Socialtext::Group')) {
        $self->_group_role_changed($actor,$change,$object,$role);
    }
};

sub _user_role_changed {
    my ($self,$actor,$change,$user,$role) = @_;

    require Socialtext::Pluggable::Adapter;

    if ($change eq 'add') {
        # This is needed because of older appliances where users were put in
        # one of three accounts that are not optimal:
        #
        #  * Ambiguous: They should be in an account, but more than one
        #    account seems like a good candidate.
        #  * General: There was not a good candidate account.
        #  * Unknown: This was an old default, move them if possible.
        #
        # We assume that's not where we want them to be, so assigning a
        # user to thier first workspace is a show of intent for which
        # account they should be in.
        $user->primary_account($self->account)
            if List::MoreUtils::any { $user->primary_account->name eq $_ }
            qw/Ambiguous General Unknown/;

        # XXX: may have been added to more than just this account
        my $adapter = Socialtext::Pluggable::Adapter->new;
        $adapter->make_hub($actor, $self);
        $adapter->hook(
            'nlw.add_user_account_role',
            [$self->account, $user, Socialtext::Role->Affiliate()]
        );
    }
    elsif ($change eq 'remove') {

        # XXX: may have been added to more than just this account
        my $adapter = Socialtext::Pluggable::Adapter->new;
        $adapter->make_hub($actor, $self);
        $adapter->hook(
            'nlw.remove_user_account_role',
            [$self->account, $user, Socialtext::Role->Affiliate()]
        );
    }
}

sub _group_role_changed {
    my ($self,$actor,$change,$group,$role) = @_;

    if ($change eq 'add' || $change eq 'remove') {
        my $action = $change eq 'add'
                ? 'add_to_workspace'
                : 'remove_from_workspace';
        Socialtext::Events->Record({
            event_class => 'group',
            action => $action,
            actor => $actor,
            group => $group,
            context => {
                workspace_id => $self->workspace_id,
            },
        });
    }
}

{
    Readonly my $spec => {
        dir  => DIR_TYPE( default     => undef ),
        name => SCALAR_TYPE( optional => 1 )
    };
    sub export_to_tarball {
        my $self = shift;
        my %p = validate(@_,$spec);
        $p{name} //= $self->name;

        die loc("error.no-export-directory=path", $p{dir})."\n"
            if defined $p{dir} && ! -d $p{dir};

        die loc("error.export-directory-not-writable=path", $p{dir})."\n"
            unless defined $p{dir} && -w $p{dir};

        my $tarball_dir = defined $p{dir}
            ? Cwd::abs_path( $p{dir} )
            : $ENV{ST_TMP};
        $tarball_dir ||= '/tmp';

        my $tarball = Socialtext::File::catfile( $tarball_dir,
            $p{name}.".$EXPORT_VERSION.tar" );

        for my $file ( ($tarball, "$tarball.gz") ) {
            die loc("error.export=file", $file)."\n"
                if -f $file && ! -w $file;
        }

        require Socialtext::Workspace::Exporter;
        my $wx = Socialtext::Workspace::Exporter->new(
            workspace => $self,
            name => $p{name} ? $p{name} : $self->name,
        );
        $wx->to_tarball("$tarball.gz");
        return "$tarball.gz";
    }
}

sub Any {
    my $class = shift;
    return $class->All( limit => 1 )->next;
}

sub ImportFromTarball {
    my $self = shift;

    require Socialtext::Workspace::Importer;

    my ( $main, $hub ) = $self->_main_and_hub();
    Socialtext::Workspace::Importer->new(hub => $hub, @_)->import_workspace();
}

sub AllWorkspaceIdsAndNames {
    my $sth = sql_execute('SELECT workspace_id, name FROM "Workspace" where workspace_id <> 0 ORDER BY name');
    return $sth->fetchall_arrayref() || [];
}

my %LimitAndSortSpec = (
    limit      => SCALAR_TYPE( default => undef ),
    offset     => SCALAR_TYPE( default => 0 ),
    order_by   => SCALAR_TYPE(
        regex   => qr/^(?:name|user_count|account_name|creation_datetime|creator)$/,
        default => 'name',
    ),
    sort_order => SCALAR_TYPE(
        regex   => qr/^(?:ASC|DESC|)$/i,
        default => undef,
    ),
);
{
    Readonly my $spec => { %LimitAndSortSpec };
    sub All {
        my $class = shift;
        my %p = validate( @_, $spec );

        # We're supposed to default to DESCending if we're creation_datetime.
        $p{sort_order} ||= $p{order_by} eq 'creation_datetime' ? 'DESC' : 'ASC';

        Readonly my %SQL => (
            name => 'SELECT *'
                . ' FROM "Workspace"'
                . ' WHERE workspace_id <> 0'
                . " ORDER BY name $p{sort_order}"
                . ' LIMIT ? OFFSET ?',
            creation_datetime => 'SELECT *'
                . ' FROM "Workspace"'
                . ' WHERE workspace_id <> 0'
                . " ORDER BY creation_datetime $p{sort_order},"
                . ' name ASC'
                . ' LIMIT ? OFFSET ?',
            account_name => 'SELECT "Workspace".*'
                . ' FROM "Workspace", "Account"'
                . ' WHERE "Workspace".account_id = "Account".account_id'
                . '   AND workspace_id <> 0'
                . " ORDER BY \"Account\".name $p{sort_order},"
                . ' "Workspace".name ASC'
                . ' LIMIT ? OFFSET ?',
            creator => 'SELECT *'
                . ' FROM "Workspace", users'
                . ' WHERE created_by_user_id=user_id'
                . '   AND workspace_id <> 0'
                . " ORDER BY driver_username $p{sort_order}, name ASC"
                . ' LIMIT ? OFFSET ?',
            user_count => qq{
SELECT "Workspace".*
    FROM "Workspace",
    (
        SELECT into_set_id,
               COUNT(DISTINCT(from_set_id)) AS user_count
            FROM user_set_path
            WHERE from_set_id } . PG_USER_FILTER . qq{
            GROUP BY into_set_id
    ) AS temp1
    WHERE temp1.into_set_id = "Workspace".user_set_id
      AND workspace_id <> 0
    ORDER BY user_count $p{sort_order},
    "Workspace".name ASC
    LIMIT ? OFFSET ?
    }
        );

        return $class->_WorkspaceCursor(
            $SQL{ $p{order_by} },
            [qw( limit offset)], %p
        );
    }
}

sub _WorkspaceCursor {
    my ( $class, $sql, $interpolations, %p ) = @_;

    my $sth = sql_execute( $sql, @p{@$interpolations} );

    return Socialtext::MultiCursor->new(
        iterables => [ $sth->fetchall_arrayref( {} ) ],
        apply => sub {
            my $row = shift;
            return Socialtext::Workspace->new_from_hash_ref( $row );
        }
    );
}

{
    Readonly my $spec => {
        %LimitAndSortSpec,
        order_by   => SCALAR_TYPE(
            regex   => qr/^(?:name|user_count|creation_datetime|creator|account_name)$/,
            default => 'name',
        ),
        account_id => SCALAR_TYPE,
    };
    sub ByAccountId {
        my $class = shift;
        my %p = validate( @_, $spec );

        # We're supposed to default to DESCending if we're creation_datetime.
        $p{sort_order} ||= $p{order_by} eq 'creation_datetime' ? 'DESC' : 'ASC';

        Readonly my %SQL => (
            name => 'SELECT *'
                . ' FROM "Workspace"'
                . ' WHERE account_id=?'
                . '   AND workspace_id <> 0'
                . " ORDER BY name $p{sort_order}"
                . ' LIMIT ? OFFSET ?',
            creation_datetime => 'SELECT *'
                . ' FROM "Workspace"'
                . ' WHERE account_id=?'
                . '   AND workspace_id <> 0'
                . " ORDER BY creation_datetime $p{sort_order},"
                . ' name ASC'
                . ' LIMIT ? OFFSET ?',
            account_name => 'SELECT "Workspace".*'
                . ' FROM "Workspace", "Account"'
                . ' WHERE "Workspace".account_id = "Account".account_id'
                . ' AND "Workspace".account_id=?'
                . ' AND workspace_id <> 0'
                . " ORDER BY \"Account\".name $p{sort_order},"
                . ' "Workspace".name ASC'
                . ' LIMIT ? OFFSET ?',
            creator => 'SELECT *'
                . ' FROM "Workspace", users'
                . ' WHERE created_by_user_id=user_id'
                . ' AND "Workspace".account_id=?'
                . ' AND workspace_id <> 0'
                . " ORDER BY driver_username $p{sort_order}, name ASC"
                . ' LIMIT ? OFFSET ?',
            user_count => qq{
            SELECT "Workspace".*
                    FROM "Workspace",
                    (SELECT into_set_id,
                        COUNT(DISTINCT(from_set_id)) AS user_count
                     FROM user_set_include
                     WHERE from_set_id } . PG_USER_FILTER . qq{
                     GROUP BY into_set_id)
                    AS temp1
                    WHERE temp1.into_set_id = "Workspace".user_set_id
                    AND "Workspace".account_id=?
                    AND workspace_id <> 0
                    ORDER BY user_count $p{sort_order},
                    "Workspace".name ASC
                    LIMIT ? OFFSET ?
            }
        );

        return $class->_WorkspaceCursor(
            $SQL{ $p{order_by} },
            [qw( account_id limit offset )], %p
        );
    }
}

{
    Readonly my $spec => {
        %LimitAndSortSpec,
        name => SCALAR_TYPE,
        case_insensitive => SCALAR_TYPE( default => 0),
    };
    sub ByName {
        my $class = shift;
        my %p = validate( @_, $spec );

        # We're supposed to default to DESCending if we're creation_datetime.
        $p{sort_order} ||= $p{order_by} eq 'creation_datetime' ? 'DESC' : 'ASC';

        my $op = $p{case_insensitive} ? 'ILIKE' : 'LIKE';
        Readonly my %SQL => (
            name => 'SELECT *'
                . ' FROM "Workspace"'
                . " WHERE name $op ?"
                . " ORDER BY name $p{sort_order}"
                . ' LIMIT ? OFFSET ?',
            creation_datetime => 'SELECT *'
                . ' FROM "Workspace"'
                . " WHERE name $op ?"
                . " ORDER BY creation_datetime $p{sort_order},"
                . ' name ASC'
                . ' LIMIT ? OFFSET ?',
            account_name => 'SELECT "Workspace".*'
                . ' FROM "Workspace", "Account"'
                . ' WHERE "Workspace".account_id = "Account".account_id'
                . " AND \"Workspace\".name $op ?"
                . " ORDER BY \"Account\".name $p{sort_order},"
                . ' "Workspace".name ASC'
                . ' LIMIT ? OFFSET ?',
            creator => 'SELECT *'
                . ' FROM "Workspace", users'
                . ' WHERE created_by_user_id=user_id'
                . " AND \"Workspace\".name $op ?"
                . " ORDER BY driver_username $p{sort_order}, name ASC"
                . ' LIMIT ? OFFSET ?',
            user_count => qq{
SELECT *
    FROM "Workspace"
    LEFT OUTER JOIN (
        SELECT into_set_id, COUNT(DISTINCT(from_set_id))
            AS user_count
            FROM user_set_path 
            WHERE from_set_id } . PG_USER_FILTER . qq{
            GROUP BY into_set_id
        ) AS X ON (user_set_id = into_set_id)
    WHERE name $op ?
    ORDER BY user_count $p{sort_order}, "Workspace".name ASC
    LIMIT ? OFFSET ?
},
        );

        if ($p{name} =~ /^\\b(.+)/) {
            # Match from the beginning.
            $p{name} = "$1%";
        }
        else {
            # Turn our substring into a SQL pattern.
            $p{name} = '%' . $p{name} . '%';
        }

        return $class->_WorkspaceCursor(
            $SQL{ $p{order_by} },
            [qw( name limit offset )], %p
        );
    }
}

sub Count {
    my $class = shift;
    my $sth = sql_execute('SELECT COUNT(*) FROM "Workspace" where workspace_id <> 0');
    return $sth->fetchrow_arrayref->[0];
}

sub CountByName {
    my $class = shift;
    my %p = @_;
    my $op = $p{case_insensitive} ? 'ILIKE' : 'LIKE';
    my $sth = sql_execute('SELECT COUNT(*) FROM "Workspace" WHERE name ' . $op . ' \'%' . $p{name} . '%\'');
    return $sth->fetchrow_arrayref->[0];
}

sub MostOftenAccessedLastWeek {
    my $self = shift;
    my $limit = shift || 10;
    my $sth = sql_execute(q{
        SELECT "Workspace".title AS workspace_title,
               "Workspace".name AS workspace_name
        FROM (
            SELECT distinct page_workspace_id,
                   COUNT(*) AS views
              FROM event
             WHERE event_class = 'page'
               AND action = 'view'
               AND at > 'now'::timestamptz - '1 week'::interval
             GROUP BY page_workspace_id
             ORDER BY views DESC
             LIMIT ?
        ) AS X
        JOIN "Workspace"
          ON workspace_id = page_workspace_id
        JOIN "WorkspaceRolePermission"
          USING(workspace_id)
        JOIN "Permission"
          USING(permission_id)
        JOIN "Role"
          USING(role_id)
        WHERE "Permission".name = 'read'
          AND "Role".name = 'guest'
        ORDER BY views DESC;
    }, $limit);

    my @viewed;
    while (my $row = $sth->fetchrow_hashref) {
        push @viewed, [$row->{workspace_name}, $row->{workspace_title}];
    }
    return @viewed;
}

sub EnablePluginForAll {
    my $class = shift;
    my $plugin = shift;
    my $workspaces = $class->All();
    my $is_socialcalc = $plugin eq 'socialcalc';
    while ( my $ws = $workspaces->next() ) {
        next if $is_socialcalc and $ws->account->account_type eq 'Free 50';
        $ws->enable_plugin( $plugin );
    }
    require Socialtext::SystemSettings;
    Socialtext::SystemSettings::set_system_setting( "$plugin-enabled-all", 1 );
}

sub DisablePluginForAll {
    my $class = shift;
    my $plugin = shift;
    my $workspaces = $class->All();
    while ( my $ws = $workspaces->next() ) {
        $ws->disable_plugin( $plugin );
    }
    require Socialtext::SystemSettings;
    Socialtext::SystemSettings::set_system_setting( "$plugin-enabled-all", 0 );
}

around 'PluginsEnabledForAll' => sub {
    my $orig = shift;
    return $orig->($_[0], 'Workspace');
};

around 'plugins_enabled' => sub {
    my $orig = shift;
    return $orig->(@_, direct => 1);
};

use constant RECENT_WORKSPACES => 10;
sub read_breadcrumbs {
    my ( $self, $user ) = @_;

    # Get the crumbs
    my @list = Socialtext::WorkspaceBreadcrumb->List(
        user_id => $user->user_id,
        limit   => RECENT_WORKSPACES,
    );

    # Seed the list if we didn't get much.  We'll always at least get the
    # workspace we're on now.
    unless (@list > 1) {
        @list = $self->prepopulate_breadcrumbs($user);
        @list = @list[ 0 .. ( RECENT_WORKSPACES - 1 ) ]
            if @list > RECENT_WORKSPACES;
    }

    return @list;
}

sub prepopulate_breadcrumbs {
    my ( $self, $user ) = @_;
    my @workspaces = $user->workspaces->all();

    for my $ws ( reverse @workspaces ) {
        Socialtext::WorkspaceBreadcrumb->Save(
            user_id      => $user->user_id,
            workspace_id => $ws->workspace_id,
        );
    }

    return @workspaces;
}

sub drop_breadcrumb {
    my $self = shift;
    my $user = shift;

    Socialtext::WorkspaceBreadcrumb->Save(
        user_id      => $user->user_id,
        workspace_id => $self->workspace_id,
    );
}

sub is_default {
    my $self = shift;
    my $default_name = Socialtext::AppConfig->default_workspace;
    return unless $default_name;

    return $self->name eq $default_name;
}

sub Default {
    my $class = shift;
    my $default_name = Socialtext::AppConfig->default_workspace;
    return unless $default_name;

    local $@;
    return eval {
        Socialtext::Workspace->new(name => $default_name);
    };
}

{
    my $cache;
    sub cache {
        return $cache ||= Socialtext::Cache->cache('workspace');
    }
}

after role_change_check => sub {
    my ($self,$actor,$change,$thing,$role) = @_;
    if ($thing->isa(ref($self))) {
        die "Workspace user_sets cannot contain other workspaces.";
    }
    elsif ($thing->isa('Socialtext::Account')) {
        if ($thing->account_id != $self->account_id) {
            die "Only a workspace's primary account can be a member.\n";
        }
    }
    elsif ($thing->isa('Socialtext::Group')) {
        croak "group and workspace do not have compatible permission sets"
            unless $self->permissions->current_set_name
                eq $thing->workspace_compat_perm_set;
    }
};

after qw(assign_role_to_account add_account) => \&_de_dupe_users;
sub _de_dupe_users {
    my ($self, %opts) = @_;
    my $new_role = $opts{role};
    $new_role = Socialtext::Role->new(name => $new_role) unless ref $new_role;

    my $acct_users = $opts{account}->users(primary_only => 1);
    while (my $u = $acct_users->next) {
        my $r = $self->role_for_user($u, direct => 1);
        next unless defined $r;
        next unless $r->role_id == $new_role->role_id;
        $self->remove_user(user => $u, role => $new_role);
    }
}

after qw(add_account remove_account) => sub {
    my ($self, %opts) = @_;
    if ($opts{account}) {
        Socialtext::JSON::Proxy::Helper->ClearForAccount(
            $opts{account}->account_id
        );
    }
};

sub impersonation_ok {
    my ($self, $actor, $user) = @_;

    return unless $self->has_user($actor);
    return unless $self->has_user($user);
    return $self->permissions->user_can(
        user => $actor, permission => ST_IMPERSONATE_PERM);
}

sub load_pages_from_disk {
    my ($self, %opts) = @_;
    my $dir = $opts{dir} || die "dir is required";
    die "dir does not exist" unless -d $dir;

    my $replaces = $opts{replace} || [];

    my ( $main, $hub ) = $self->_main_and_hub();

    my @files = glob("$dir/*.json");
    for my $f (@files) {
        my $data = decode_json(Socialtext::File::get_contents_utf8($f));
        (my $content_file = $f) =~ s/\.json$//;
        my $content = Socialtext::File::get_contents_utf8($content_file);

        my $page_name = $data->{name};

        for my $r (keys %$replaces) {
            $page_name =~ s{\Q$r\E}{$replaces->{$r}};
        }

        # Don't clobber existing pages
        next unless $opts{clobber}
            or !$hub->pages->new_from_name($page_name)->exists;

        if ($data->{attachments}) {
            my $attachments = $hub->attachments;
            my $page_id = Socialtext::String::title_to_id($page_name);
            for my $name (@{$data->{attachments}}) {
                open my $fh, "$dir/attachments/$data->{page_id}/$name"
                    or die "Can't open $name: $!";
                $attachments->create(
                    page_id => $page_id,
                    creator => Socialtext::User->SystemUser,
                    filename => $name,
                    fh => $fh,
                );
            }
        }

        Socialtext::Page->new(hub => $hub)->create(
            title => $page_name,
            content => $content,
            creator => Socialtext::User->SystemUser,
            categories => $data->{tags},
        );
    }
}

sub last_edit_for_user {
    my $self = shift;
    my $user_id = shift;

    my $sql = "
        SELECT
          page_id,
          edit_time,
          page_type,
          name
        FROM
          page_revision 
        WHERE
          workspace_id = ?
        AND edit_time = (
          SELECT
            MAX(edit_time)
          FROM
            page_revision
          WHERE
            workspace_id = ?
          AND
            editor_id = ?
          AND
            deleted = false)
    ";

    my $sth = sql_execute($sql,
        $self->workspace_id,
        $self->workspace_id,
        $user_id,
    );
    return $sth->fetchrow_hashref();
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

package Socialtext::NoWorkspace;
use Moose;
use Socialtext::User;

extends 'Socialtext::Workspace';

use constant name                       => '';
use constant skin_name                  => '';
use constant title                      => 'The NoWorkspace Workspace';
use constant account_id                 => 1;
use constant workspace_id               => 0;
use constant email_addresses_are_hidden => 0;
use constant real                       => 0;
use constant is_plugin_enabled          => 0;
use constant drop_breadcrumb            => undef;

override 'new' => sub { return bless {}, __PACKAGE__ };

sub created_by_user_id { Socialtext::User->SystemUser->user_id }

sub impersonation_ok { return } # false

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

__END__

=head1 NAME

Socialtext::Workspace - A Socialtext workspace object

=head1 SYNOPSIS

  use Socialtext::Workspace;

  my $workspace = Socialtext::Workspace->new( workspace_id => $workspace_id );

  my $workspace = Socialtext::Workspace->new( name => $name );

=head1 DESCRIPTION

This class provides methods for dealing with data from the Workspace
table. Each object represents a single row from the table.

A workspace has the following attributes:

=head2 name

This is used when generating URIs and when sending email to a
workspace. It must be 3 to 30 characters long, and must match
C</^[A-Za-z0-9_\-]+$/>. Also, it cannot conflict with an existing
email alias.

=head2 title

This is used as the title of the home page for the workspace, and is
also used in various contexts when referring to the workspace, for
example in recent changes email notifications. The title must be 2-64
characters in length.

=head2 email_addresses_are_hidden

If this is true, then user's email addresses are always masked when
they're displayed. The domain name is replaced by "@hidden".

=head2 email_weblog_dot_address

If this is true, then the workspace will accept email for blogs
using the 'workspace.CAT.category@server.domain.com' format - this
is to support Lotus Notes, Exchange and other non-standard email
clients.

=head2 comment_by_email

If this is true, the 'Add comment' links on pages and blog entries will
contain C<mailto:> links pointing at the email-in address for the current
workspace.

=head2 unmasked_email_domain

If this is set to a domain name, then email addresses in this domain
are never hidden.

=head2 prefers_incoming_html_email

When this is true, if an incoming email has both text and HTML
versions, the HTML version is saved as the page's body.

=head2 incoming_email_placement

This specifies how an incoming email that matches an existing page
name is saved. This can be one of "top", "bottom", or "replace". The
"top" and "bottom" options cause the email to be added to the existing
page at the specified location, while "replace" replaces existing
pages.

=head2 allows_html_wafl

Specifies whether the ".html" WAFL block is allowed in a workspace.

=head2 email_notify_is_enabled

Specifies whether email notifications are turned on for this
workspace.

=head2 sort_weblogs_by_create

If true, blogs are sorted by page creation time. Otherwise they are
sorted by the last updated time of each page's most recent revision.

=head2 external_links_open_new_window

If this is true, links outside of NLW open a new browser window.

=head2 basic_search_only

If this is true, then the workspace is not indexed using a search factory, and
searching uses the "basic" mechanism.

=head2 show_welcome_message_below_logo

If this is true, the welcome message ("Welcome, Faye Wong") is shown
below the workspace logo in the side pane. Otherwise it is shown in
the fixed bar at the top of the page.

=head2 custom_title_label

By default, a workspace's title is prefixed with either "Workspace:"
or "Eventspace:". Setting this changes this to a custom value. A
trailing colon is always added to this value in the display code, so
do not include it in the value of this attribute.

=head2 show_title_below_logo

if this is true, then the workspace title is shown below the logo in
the side pane.

=head2 comment_form_note_bottom

When set, the text will be displayed at the bottom of the comment for textarea in the UI.

=head2 comment_form_note_top

When set, the text will be displayed at the top of the comment for textarea in the UI.

=head2 comment_form_window_height

The comment form window will popup to this hieght.

=head2 email_notification_from_address

When set, this value is used as the "From" header when sending email
notifications. Otherwise, the default value of
"noreply@socialtext.net" is used.

=head2 skin_name

The skin defines a set of CSS files, and possibly javascript and
templates. The default skin is "st". For now, the skin_name is just
used to generate filesystem and URI paths to the various files.

In the future, this will be replaced with something more
sophisticated, when skins become first class entities in the system.

=head2 logo_uri

The URI to the workspace's logo.

This cannot be set via C<create()> or C<update()>. Use
C<set_logo_from_file()> or C<set_logo_from_uri()> instead.

=head2 creation_datetime

The datetime at which the workspace was created.

=head2 account_id

The account_id of the Account to which this workspace belongs.

=head2 created_by_user_id

The user_id of the user who created this workspace.

=head2

=head1 METHODS

=head2 Socialtext::Workspace->new(PARAMS)

Looks for an existing workspace matching PARAMS and returns a
C<Socialtext::Workspace> object representing that workspace if it
exists.

PARAMS can be I<one> of:

=over 4

=item * workspace_id => $workspace_id

=item * name => $name

=back

=head2 Socialtext::Workspace->NameIsValid(PARAMS)

Validates whether a workspace name is valid according to syntax rules.
It also checks the name against a list of reserved names.  The method
returns 1 if the name is valid, 0 if it is not.

If the name is invalid and an arrayref is passed as errors, a
description of each violated rule will be stored in the arrayref.

It DOES NOT check to see if a workspace exists.

PARAMS can include:

=over 4

=item * name => $name - required

=item * errors => \@errors - optional, an arrayref where violated constraints will be put

=back

=head2 Socialtext::Workspace->TitleIsValid(PARAMS)

Validates whether a workspace title is valid according to syntax rules.
It also checks the title against a list of reserved titles.  The method
returns 1 if the title is valid, 0 if it is not.

If the title is invalid and an arrayref is passed as errors, a
description of each violated rule will be stored in the arrayref.

It DOES NOT check to see if a workspace exists.

PARAMS can include:

=over 4

=item * title => $title - required

=item * errors => \@errors - optional, an arrayref where violated constraints will be put

=back

=head2 Socialtext::Workspace->create(PARAMS)

Attempts to create a workspace with the given information and returns
a new C<Socialtext::Workspace> object representing the new workspace.

PARAMS can include:

=over 4

=item * name - required

=item * title - required

=item * email_addresses_are_hidden - defaults to 0

=item * unmasked_email_domain - optional

=item * prefers_incoming_html_email - defaults to 0

=item * incoming_email_placement - defaults to "bottom"

=item * allows_html_wafl - defaults to 1

=item * email_notify_is_enabled - defaults to 1

=item * sort_weblogs_by_create - defaults to 0

=item * external_links_open_new_window - defaults to 1

=item * basic_search_only - defaults to 0

=item * email_weblog_dot_address - defaults to 0

=item * show_welcome_message_below_logo - defaults to 0

=item * custom_title_label - defaults to ""

=item * show_title_below_logo - defaults to 1

=item * email_notification_from_address - defaults to ""

=item * skin_name - defaults to "st"

=item * creation_datetime - defaults to CURRENT_TIMESTAMP

=item * account_id - defaults to Socialtext::Account->Unknown()->account_id()

=item * created_by_user_id - defaults to Socialtext::User->SystemUser()->user_id()

=item * skip_default_pages - defaults to false

=item * clone_pages_from - clone pages from another workspace, defaults to false

=back

Creating a workspace creates the necessary paths on the filesystem,
and copies the tutorial pages and workspace home page into the new
workwspace. It also calls C<< Socialtext::EmailAlias::create_alias() >> to
add its name to the aliases file.

If "skip_default_pages" is true, then the usual tutorial and default
home page for the workspace will not be created. This option is
primarily intended for one-time use when importing existing workspaces
into the DBMS.

=head2 Socialtext::Workspace->help_workspace( ARGS )

Return the help workspace for the current system-wide locale().  This method
takes the same arguments as new(), sans the name argument, which will be
ignored.

=head2 Socialtext::Workspace->help_workspaces()

Returns the list of installed help workspaces.

=head2 $workspace->update(PARAMS)

Updates the workspace's information with the new key/val pairs passed
in.

Note that to rename a workspace you should call the C<rename()>
method.

=head2 $workspace->rename( name => $new_name )

This renames a workspace in the DBMS, as well as on the filesystem and
in the email aliases file.

=head2 $workspace->reindex_async( $hub, $search_config )

Asyncronously index the workspace content.

=head2 $workspace->workspace_id()

=head2 $workspace->name()

=head2 $workspace->title()

=head2 $workspace->logo_uri()

=head2 $workspace->email_addresses_are_hidden()

=head2 $workspace->unmasked_email_domain()

=head2 $workspace->prefers_incoming_html_email()

=head2 $workspace->incoming_email_placement()

=head2 $workspace->allows_html_wafl()

=head2 $workspace->email_notify_is_enabled()

=head2 $workspace->sort_weblogs_by_create()

=head2 $workspace->external_links_open_new_window()

=head2 $workspace->basic_search_only()

=head2 $workspace->email_weblog_dot_address()

=head2 $workspace->show_welcome_message_below_logo()

=head2 $workspace->custom_title_label()

Call C<< $workspace->title_label() >> instead to get either the
default or custom label, as appropriate.

=head2 $workspace->show_title_below_logo()

=head2 $workspace->email_notification_from_address()

Defaults to 'noreply@socialtext.com' via ST::Schema.

=head2 $workspace->formatted_email_notification_from_address()

Returns a formatted address comprising the title of the Workspace and
the address set via email_notification_from_address.

=head2 $workspace->skin_name()

=head2 $workspace->creation_datetime()

=head2 $workspace->account_id()

=head2 $workspace->created_by_user_id()

Returns the given attribute for the workspace.

=head2 $workspace->title_label()

If the workspace has a custom title label, this is returned. Otherwise
this returns either "Workspace" or "Eventspace", depending on
the workspace's ACLs.

=head2 $workspace->delete()

Deleting a workspace also deletes any workspace data on the
filesystem, as well as its email alias.

=head2 $workspace->uri()

Returns the full URI for the workspace, using the "http" scheme. The
hostname is taken from C<< Socialtext::AppConfig->web_hostname >>.

=head2 $workspace->email_in_address()

Returns the email address for mailing pages into the workspace. The
email hostname comes from C<< Socialtext::AppConfig->email_hostname >>.

=head2 $workspace->header_logo_image_uri()

Returns a URI for the header logo. This is based on the value of the
"header_logo_image_filename" attribute.

=head2 $workspace->logo_uri_or_default()

Returns a valid logo URI for the workspace, using a default of
F</static/images/socialtext-logo-30.gif> if the workspace does not
have its own custom logo.

=head2 $workspace->logo_filename()

If the workspace has a custom logo on the filesystem, then this
methods returns that file's absolute path, otherwise it returns false.

=head2 $workspace->set_logo_from_file(PARAMS)

This method expects one parameter, a "filename". The specified file
should contain the image data, and will be used for determining the
file's type, which must be a GIF, JPEG or PNG.

The image is resized to a maximum size of 200px wide by 60px high, and
saved on the filesystem in a location accessible from the web. The
workspace's logo_uri will be set to match the URI of this file.

The URI will contain a portion based on an MD5 digest in order to make
snooping for logos much more difficult.

If the workspace has an existing logo on the filesystem,
this will be deleted.

=head2 $workspace->set_logo_from_uri( uri => $uri )

This simply sets the workspace's logo_uri to the given "uri"
parameter. If the workspace has an existing logo on the filesystem,
this will be deleted.

=head2 $workspace->ping_uris()

Returns a list of the ping URIs for the workspace.

=head2 $workspace->set_ping_uris( uris => [ $uri1, $uri2 ] )

This method sets the ping URIs for the workspace (used by the
C<Socialtext::WeblogUpdates> module.

=head2 $workspace->comment_form_custom_fields()

Returns a list of the comment form fustom fields for the workspace.

=head2 $workspace->set_comment_form_custom_fields( fields => [ $field1, $field2 ] )

This method sets comment form custom fields for the workspace.

=head2 Socialtext::Workspace->LogoRoot()

Returns the path under which logos are stored.

=head2 $workspace->creation_datetime_object()

Returns a new C<DateTime.pm> object for the workspace's creation
datetime.

=head2 $workspace->creator()

Returns the C<Socialtext::User> object for the user which created this
workspace.

=head2 $workspace->account()

Returns the C<Socialtext::Account> object for the account to which the
workspace belongs.

=head2 $workspace->is_all_users_workspace()

Returns whether or not the workspace is an all users workspace for the account
to which it belongs.

=head2 $workspace->set_permissions( set_name => $name )

Given a permission-set name, this method sets the workspace's
permissions according to the definition of that set.

The valid set names and the permissions they give are shown below.
Additionally, all permission sets give the same permissions as C<member> plus
C<impersonate> to the C<impersonator> role.

=head2 $workspace->is_plugin_enabled($plugin)

Returns true if the specified plugin is enabled for this workspace.

=head2 $workspace->enable_plugin($plugin)

Enables the plugin for the specified workspace.

=head2 $workspace->disable_plugin($plugin)

Disables the plugin for the specified workspace.

=head2 $account->plugins_enabled()

Returns an array for the plugins enabled.

=head2 $workspace->enable_spreadsheet()

Check whether spreadsheets are enabled or not.

=over 4

=item * public

=over 8

=item o guest - read, edit, comment

=item o authenticated_user - read, edit, comment, email_in

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out

=back

=item * member-only

=over 8

=item o guest - none

=item o authenticated_user - email_in

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out

=back

=item * authenticated-user-only

=over 8

=item o guest - none

=item o authenticated_user - read, edit, attachments, comment, delete, email_in, email_out

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out

=back

=item * public-read-only

=over 8

=item o guest - read

=item o authenticated_user - read

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out

=back

=item * public-comment-only

=over 8

=item o guest - read, comment

=item o authenticated_user - read, comment

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out

=back

=item * public-authenticate-to-edit ( Deprecated, do not use. )

=over 8

=item o guest - read, edit_controls

=item o authenticated_user - read, edit, attachments, comment, delete, email_in, email_out

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out

=back

=item * public-join-to-edit

=over 8

=item o guest - read, self_join 

=item o authenticated_user - read, edit, attachments, comment, delete, email_in, email_out

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out

=back

=item * intranet

=over 8

=item o guest - read, edit, attachments, comment, delete, email_in, email_out

=item o authenticated_user - read, edit, attachments, comment, delete, email_in, email_out

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out

=back

=back

Additionally, when a name that starts with public is given, this
method will also change allows_html_wafl and email_notify_is_enabled
to false.

=head2 $workspace->add_user( user => $user, role => $role )

Adds the user to the workspace with the given role. If no role is
specified, this defaults to "member".

=head2 $workspace->assign_role_to_user( user => $user, role => $role )

Assigns the specified role to the given user. If the user already has a role
for this workspace, this method changes that role.

=head2 $workspace->has_user( $user )

Returns a boolean indicating whether or not the user has an explicitly
assigned role for this workspace.

=head2 $workspace->role_for_user($user)

Returns the most effective C<Socialtext::Role> that this user has in the
workspace (which was either assigned to them explicitly, or was inferred via
Group membership).  If the User has B<no> Role in the workspace, this method
returns false.

=head2 $workspace->remove_user( user => $user )

Removes an explicitly assigned role for the user in this workspace, if
they have one.

=head2 $workspace->user_has_role( user => $user, role => $role )

Returns a boolean indicating whether or not the user has the given
role.

=head2 $workspace->user_count()

Returns the number of users with an explicitly assigned role in the
workspace (possibly via a group; pass C<< direct => 1 >> to limit to direct workspace roles).

=head2 $workspace->users()

Returns a cursor of C<Socialtext::User> objects for users in the
workspace, ordered by username.

Passthrough to C<Socialtext::Workspace::Roles-E<gt>UsersByWorkspaceId()>.
Refer to L<Socialtext::Workspace::Roles> for more information on acceptable
parameters.

=head2 $workspace->user_roles()

Returns a cursor of pairs of C<Socialtext::User> and
C<Socialtext::Role> objects for users in the the
workspace, ordered by username.

=head2 $workspace->add_group(group=>$group, role=>$role)

Adds the given C<$group> to the Workspace with the specified C<$role>.  If no
C<$role> is provided, a default Role will be used instead.

=head2 $workspace->remove_group(group=>$group)

Removes any Role that the given C<$group> may have in the Workspace.  If the
Group has no Role in the Workspace, this method does nothing.

=head2 $workspace->has_group($group)

Checks to see if the given C<$group> has a Role in the Workspace, returning
true if it does, false otherwise.

=head2 $workspace->role_for_group($group)

Returns the C<Socialtext::Role> object representing the Role that the given
C<$group> has in this Workspace.  In a list context, returns all effective roles.

=head2 $workspace->groups()

Returns a cursor of C<Socialtext::Group> objects for Groups that have a Role
in the Workspace, ordered by Group name.

=head2 $workspace->group_count()

Returns the count of Groups that have a Role in the Workspace.

=head2 $workspace->to_hash()

Returns a hash reference representation of the workspace, suitable
for using with JSON, YAML, etc.

=head2 $workspace->export_to_tarball( dir => $dir, [name => $name] )

This method exports the workspace as a tarball. This tarball can be
restored by calling C<< Socialtext::Workspace->ImportFromTarball() >>.

The "dir" parameter is optional, and if none is given, it will use a
temp directory.

The "name" parameter is optional.  If it is given the exported tarball uses
Workspace name $name instead of workspace's actual name.  When the tarball is
re-imported it will have name $name.

This method returns the full path to the created tarball.

The exported data includes the workspace data, pages, user data for
all users who are members of the workspace, and the roles for those
users.

=head2 $workspace->real()

Real workspaces return true, NoWorkspaces return false.

=head2 Socialtext::Workspace->Any()

Returns one workspace at random. This was needed for interfacing with
the C<Socialtext::Hub> object, which always needs a workspace object, but in
some cases you may not care I<which> workspace you use.

=head2 Socialtext::Workspace->ImportFromTarball( tarball => $file, overwrite => $bool )

Given a tarball produced by C<< $workspace->export_to_tarball() >>,
this method will create a workspace based on that export.

If the workspace already exists, it throws an exception, but you can
force it to overwrite this workspace by passing "overwrite" as a true
value.

It never overwrites existing users.

=head2 Socialtext::Workspace->AllWorkspaceIdsAndNames()

Returns an array ref of workspace ID and name pairs.  These pairs are also
array refs.

=head2 Socialtext::Workspace->All(PARAMS)

Returns a cursor for all the workspaces in the system. It accepts the
following parameters:

=over 4

=item * limit and offset

These parameters can be used to add a C<LIMIT> clause to the query.

=item * order_by - defaults to "name"

This must be one "name", "user_count", "account_name",
"creation_datetime", or "creator".

=item * sort_order - "ASC" or "DESC"

This defaults to "ASC" except when C<order_by> is "creation_datetime",
in which case it defaults to "DESC".

=back

=head2 Socialtext::Workspace->ByAccountId(PARAMS)

Returns a cursor for all the workspaces in the specified account.

This accepts the same parameters as C<< Socialtext::Workspace->All()
>>, but requires an additional "account_id" parameter. When this
method is called, the C<order_by> parameter may not be "account_name".

=head2 Socialtext::Workspace->ByName(PARAMS)

Returns a cursor for all the workspaces matching the specified string.

This accepts the same parameters as C<< Socialtext::Workspace->All()
>>, but requires an additional "name" parameter. Any workspaces
containing the specified string anywhere in their name will be
returned.

If the "name" parameters begin with the C<\b>, then it's matched from
the beginning instead.

=head2 Socialtext::Workspace->Count()

Returns the number of workspaces in the system.

=head2 Socialtext::Workspace->CountByName( name => $name )

Returns the number of workspaces in the system containing the
specified string anywhere in their name.

=head2 Socialtext::Workspace->MostOftenAccessedLastWeek($limit)

Returns a list of the most often accessed I<public> workspaces.  Restricted to
the C<$limit> (default 10) most often accessed public workspaces, accessed
over the last week.

Returned as a list of list-refs that contain the "name" and "title" of the
workspace.

=head2 Socialtext::Workspace->read_breadcrumbs( USER )

Returns the list of recently viewed workspaces for the user

=head2 Socialtext::Workspace->prepopulate_breadcrumbs( USER )

If the user's breadcrumbs list is emptry, this routine will add the first 10
workspaces to the breadcrumb list.

=head2 Socialtext::Workspace->write_breadcrumbs( USER, BREAD )

Save the user's breadcrumb list

=head2 Socialtext::Workspace->drop_breadcrumb( USER )

Add a workspace breadcrumb to the user's list

=head2 Socialtext::Workspace->Default()

Return the default workspace, if any, as specified in the config file.

=head2 Socialtext::Workspace->new_from_hash_ref(hash)

Returns a new instantiation of a Workspace object. Data members for the
object are initialized from the hash reference passed to the method.

=head2 Socialtext::Workspace->permissions()

Return a Socialtext::Workspace::Permission object

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc., All Rights Reserved.

=cut

