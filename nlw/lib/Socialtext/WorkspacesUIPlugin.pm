# @COPYRIGHT@
package Socialtext::WorkspacesUIPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

use File::Spec;
use Class::Field qw( const );
use Socialtext::ArchiveExtractor;
use Socialtext::AppConfig;
use Socialtext::Permission qw( ST_EMAIL_IN_PERM );
use Socialtext::Role;
use Socialtext::l10n qw(loc);
use Socialtext::File::Copy::Recursive qw(dircopy);
use Socialtext::Log 'st_log';
use Socialtext::Group ();
use YAML qw(LoadFile);

sub class_id { 'workspaces_ui' }
const cgi_class => 'Socialtext::WorkspacesUI::CGI';

sub register {
    my $self = shift;
    my $registry = shift;
    # Web UI
    $registry->add(action => 'workspaces_settings_appearance');
    $registry->add(action => 'workspaces_settings_skin');
    $registry->add(action => 'skin_upload');
    $registry->add(action => 'remove_skin_files');
    $registry->add(action => 'workspaces_settings_features');
    $registry->add(action => 'workspaces_listall');
    $registry->add(action => 'workspaces_create');
    $registry->add(action => 'workspaces_created');
    $registry->add(action => 'workspaces_unsubscribe');
    $registry->add(action => 'workspaces_permissions');
    $registry->add(action => 'workspace_clone');
    $registry->add(action => 'workspaces_self_join');
}

sub workspaces_listall {
    my $self = shift;

    $self->reject_guest(type => 'settings_requires_account');

    $self->_update_selected_workspaces()
        if $self->cgi->Button;

    my $settings_section = $self->template_process(
        'element/settings/workspaces_listall_section',
        workspaces => $self->hub->current_user->workspaces,
        $self->status_messages_for_template,
    );

    $self->screen_template('view/settings');
    return $self->render_screen(
        settings_table_id => 'settings-table',
        settings_section  => $settings_section,
        hub               => $self->hub,
        display_title     => loc('config.wiki-list'),
        pref_list         => $self->_get_pref_list('global'),
    );
}

sub _update_selected_workspaces {
    my $self = shift;
    $self->hub->current_user->set_selected_workspaces(
        workspaces =>
        [ map { Socialtext::Workspace->new( workspace_id => $_ ) } $self->cgi->selected_workspace_id ],
    );

    $self->message(loc("config.saved"));
}

sub workspaces_settings_appearance {
    my $self = shift;

    return $self->_workspace_settings('appearance');
}

sub _render_page {
    my $self = shift;
    my $section_template = shift;
    my %p = @_;

    my $settings_section = $self->template_process(
        $section_template,
        $self->hub->helpers->global_template_vars,
        workspace => $self->hub->current_workspace,
        $self->status_messages_for_template,
        %p,
    );

    $self->screen_template('view/settings');
    return $self->render_screen(
        settings_table_id => 'settings-table',
        settings_section  => $settings_section,
        hub               => $self->hub,
        display_title     => loc('config.wiki-current'),
        pref_list         => $self->_get_pref_list,
    );
}

sub _render_skin_settings_page {
    my $self = shift;
    my %args = @_;

    my $skin_path = $self->custom_skin_path();

    my @skin_files = ();

    if (-e $skin_path) {
        push @skin_files, map {
            {
                name => (split m{$skin_path/(.*)})[1] || "",
                size => -s $_,
                date => $self->hub->timezone->date_local_epoch((stat($_))[9])
            }
        } Socialtext::File::files_under($skin_path);
    }

    $self->_reconfigure_workspace_for_skin($args{info_yaml});

    my $a = $self->_render_page(
        "element/settings/workspaces_settings_skin_section",
        skin_files => \@skin_files,
        uploaded_skin => $self->hub->current_workspace->uploaded_skin,
        %args,
    );
    open my $fh, ">/tmp/a"; print $fh $a; return $a;
}

sub _reconfigure_workspace_for_skin {
    my $self = shift;
    my $config = shift; # [in] workspace config in info.yaml

    if (exists($config->{cascade_css})) {
        $self->hub->current_workspace->update(
            cascade_css => ($config->{cascade_css} ? 1 : 0),
        );
    }
    $self->hub->current_workspace->customjs_uri($config->{customjs_name} || "");
}

sub workspaces_settings_skin {
    my $self = shift;

    $self->hub->assert_current_user_is_admin;

    my $error_message = '';
    my @skipped_files = ();

    if ($self->cgi->Button) {
        my $uploaded = $self->cgi->uploaded_skin;
        if ($uploaded ne $self->hub->current_workspace->uploaded_skin) {
            $self->hub->current_workspace->update(uploaded_skin => $uploaded)
        }
    }

    return $self->_render_skin_settings_page(
        settings_error => $error_message
    );
}

sub skin_upload {
    my $self = shift;

    $self->hub->assert_current_user_is_admin;

    my $error_message = '';
    my @skipped_files = ();
    my $info_yaml;
    $self->_extract_skin(\$error_message, \@skipped_files, \$info_yaml);

    return $self->_render_skin_settings_page(
        settings_error => $error_message,
        info_yaml => $info_yaml,
        skipped_files => \@skipped_files,
    );
}

sub remove_skin_files {
    my $self = shift;

    $self->hub->assert_current_user_is_admin;

    my $skin_path = $self->custom_skin_path();
    Socialtext::File::clean_directory($skin_path);

    $self->hub->current_workspace->update(
        uploaded_skin => 0,
    );

    return $self->_render_skin_settings_page;
}

sub custom_skin_path {
    my $self = shift;
    return $self->hub->skin->skin_upload_path(
        $self->hub->current_workspace->name
    );
}

sub _unpack_skin_file {
    my $self = shift;
    my $file = shift;   # [in] CGI File
    my $tmpdir = shift; # [in] Temp directory to hold the archive's files
    my $error = shift;  # [out] Error message, if any
    my $files = shift;  # [out] Array of files extracted from the archive

    return if (!$file);

    eval {
        my $filename = File::Basename::basename( $file->{filename} );

        if (!Socialtext::ArchiveExtractor::valid_archivename($filename)) {
            $$error = loc('error.invalid-archive=file', $filename );
            return 0;
        }
        my $tmparchive = "$tmpdir/$filename";

        open my $tmpfh, '>', $tmparchive
            or die loc('error.open=file', $file->{filename});
        File::Copy::copy($file->{handle}, $tmpfh)
            or die loc('error.unpack=file', $file->{filename});
        close $tmpfh;

        push @$files, Socialtext::ArchiveExtractor->extract( archive => $tmparchive );
    };
    if ($@ or not @$files) {
        $$error = loc('error.extract-skin');
        return 0;
    }

    return 1;
}

sub _install_skin_files {
    my $self = shift;
    my $files = shift;         # [in] Array of files to copy to the skin directory
    my $error = shift;         # [out] Error message, if any
    my $skipped_files = shift; # [out] Array of files skipped during the extraction

    return if (0 == @$files);

    my $skin_path = $self->custom_skin_path();

    my ($basedir) = map { m{^(.*/)info\.yaml$} } @$files;
    unless ($basedir) {
        $$error = loc("error.info-yaml-required!");
        return;
    }

    my $files_to_copy = qr{ ^(?: css/        |
                                 template/   |
                                 images/     |
                                 javascript/ |
                                 info\.yaml$
                        )}xsm;

    foreach (@$files) {
        my $basefile = $_;
        $basefile =~ s/^$basedir//;
        my ($filename, $path) = File::Basename::fileparse($basefile);

        next if $filename =~ /^\./; # ignore hidden files

        if ($basefile =~ $files_to_copy) {
            Socialtext::File::ensure_directory("$skin_path/$path");
            File::Copy::copy($_, "$skin_path/$basefile")
        }
        elsif ($basefile !~ m{^(?:samples/|README)}) {
            warn "Not including $path";
            push @$skipped_files, $basefile;
        }
    }

    return 1;
}

sub _extract_skin {
    my $self = shift;
    my $error_message = shift; # [out] String to hold any error message
    my $skipped_files = shift; # [out] Array of files skipped during extract
    my $info_yaml = shift; # [out] info.yaml parsed information

    my $file = $self->cgi->skin_file;

    if (!$file) {
        $$error_message = loc('error.skin-upload-failed');
        return 0;
    }

    # if we got a file, unpack it
    my $ok = 1;
    my $tmpdir = File::Temp::tempdir( CLEANUP => 1 );
    my @archive_files = ();
    if ($file) {
        $ok = $self->_unpack_skin_file($file, $tmpdir, $error_message, \@archive_files);
        return if (!$ok);
    }

    # Copy skin files to the custom folder(s)
    if (0 < @archive_files) {
        $self->_install_skin_files(\@archive_files, $error_message, $skipped_files)
    }

    $self->_parse_info_yaml(\@archive_files, $error_message, $info_yaml);

    return $ok;
}

sub _parse_info_yaml {
    my $self = shift;
    my $archive_files = shift; # [in] Files in the archive.
    my $error_message = shift; # [out] list of errors.
    my $info_yaml = shift; # [out] info.yaml parsed information.

    for my $file (@$archive_files) {
        eval {
            $$info_yaml = LoadFile($file) # YAML
              if -e $file && $file =~ m{/info.yaml$};
        };
        if ($@) {
            $$error_message = "Error parsing info.yaml file"
        }
    }
}

sub workspaces_settings_features {
    my $self = shift;

    return $self->_workspace_settings('features');
}

sub _workspace_settings {
    my $self = shift;
    my $type = shift;

    $self->hub->assert_current_user_is_admin;

    $self->_update_workspace_settings()
        if $self->cgi->Button;

    my $section_template = "element/settings/workspaces_settings_${type}_section";
    my $settings_section = $self->template_process(
        $section_template,
        $self->hub->helpers->global_template_vars,
        workspace => $self->hub->current_workspace,
        $self->status_messages_for_template,
    );

    $self->screen_template('view/settings');
    return $self->render_screen(
        settings_table_id => 'settings-table',
        settings_section  => $settings_section,
        hub               => $self->hub,
        display_title     => loc('config.wiki-current'),
        pref_list         => $self->_get_pref_list,
    );
}

sub _update_workspace_settings {
    my $self = shift;

    my %update;
    for my $f ( qw( title incoming_email_placement enable_unplugged
                    email_notify_is_enabled sort_weblogs_by_create
                    homepage_is_dashboard allows_page_locking )
    ) {
        $update{$f} = $self->cgi->$f()
            if $self->cgi->defined($f);
    }

    if ($self->cgi->defined('homepage_is_weblog')) {
        if ($self->cgi->homepage_is_weblog and not $self->cgi->homepage_weblog) {
            $self->add_error(loc('error.blog-name-required'))
        }
        $update{homepage_weblog} = $self->cgi->homepage_is_weblog ?
            $self->cgi->homepage_weblog : '';
    }

    eval {
        my $icon = $self->cgi->logo_file;

        $self->hub->current_workspace->update(%update);
        if ( $self->cgi->logo_type eq 'uri' and $self->cgi->logo_uri ) {
            $self->hub->current_workspace->set_logo_from_uri(
                uri => $self->cgi->logo_uri,
            );
        }
        elsif ( $icon and $icon->{filename} ) {
            $self->_process_logo_upload( $icon );
        }
    };
    if ( my $e = Exception::Class->caught('Socialtext::Exception::DataValidation') ) {
        $self->add_error($_) for $e->messages;
    }
    elsif ( $@ ) {
        die $@;
    }

    if ( defined $update{allows_page_locking}
        && $update{allows_page_locking} == 0
    ) {
        my @ids = $self->hub->pages->all_ids_locked();
        for my $page_id ( @ids ) {
            my $page = $self->hub->pages->new_from_name( $page_id );
            $page->update_lock_status( 0 );
        }
    }

    return if $self->input_errors_found;

    $self->message(loc("config.saved"));
}

sub _process_logo_upload {
    my $self = shift;
    my $logo = shift;

    $self->hub->current_workspace->set_logo_from_file(
        filename   => $logo->{filename},
    );
}

sub workspace_clone {
    my $self = shift;

    return $self->_workspace_clone_or_create(
        loc('config.wiki-clone'),
        'workspace_clone_section',
    );
}

sub workspaces_self_join {
    my $self = shift;

    my $user = $self->hub->current_user;
    my $ws = $self->hub->current_workspace;
    
    $self->redirect('/'.$ws->name)
        unless $self->hub->checker->check_permission("self_join");

    $self->redirect('/'.$ws->name)
        if $self->hub->current_user->is_guest;

    $self->hub->current_workspace->add_user(user=>$user);
    st_log->info("SELF_JOIN,user:". $user->email_address . "(".$user->user_id
            ."),workspace:"
            . $ws->name . "(" . $ws->workspace_id . ")");
            
    $self->redirect('/'.$ws->name);
}

sub workspaces_create {
    my $self = shift;

    return $self->_workspace_clone_or_create(
        loc('config.wiki-new'),
        'workspaces_create_section',
    );
}

sub _workspace_clone_or_create {
    my $self          = shift;
    my $display_title = shift;
    my $section       = shift;

    my $ws_checker   = $self->hub->checker;
    my $acct_checker = Socialtext::Authz::SimpleChecker->new(
        user      => $self->hub->current_user,
        container => $self->hub->current_workspace->account,
    );

    my $has_perm_ws_admin   = $ws_checker->check_permission('admin_workspace');
    my $has_perm_acct_admin = $acct_checker->check_permission('admin');

    unless ($has_perm_acct_admin) {
        # WS Admins get shown a page of instructions
        if ($has_perm_ws_admin) {
            $section = 'workspaces_cannot_create_section';
        }
        # Everyone else gets thrown back from whence they came
        else {
            Socialtext::WebApp::Exception::Redirect->throw('?');
        }
    }

    # Only *Account* Admin's can create a new WS (not WS Admins)
    if ($has_perm_acct_admin && $self->cgi->Button) {
        my $ws = $self->_create_workspace();

        if ($ws) {
            my $url = 'action=workspaces_created;workspace_id='
                . $ws->workspace_id;
            $self->redirect($url);
        }
    }

    my $settings_section = $self->template_process(
        "element/settings/$section",
        workspace => $self->hub->current_workspace,
        can_create_groups => Socialtext::Group->User_can_create_group($self->hub->current_user),
        $self->status_messages_for_template,
    );

    $self->screen_template('view/settings');
    return $self->render_screen(
        settings_table_id => 'settings-table',
        settings_section  => $settings_section,
        hub               => $self->hub,
        display_title     => $display_title,
        pref_list         => $self->_get_pref_list,
    );
}

sub _create_workspace {
    my $self       = shift;
    my $cgi        = $self->cgi;
    my $hub        = $self->hub;
    my $clone_from = $cgi->clone_pages_from || '';
    my $account_id = shift 
        || $cgi->account_id
        || $hub->current_workspace->account_id;
    my $ws;

    eval {
        my $cws  = $hub->current_workspace;
        my $skin = $hub->skin;

        $ws = Socialtext::Workspace->create(
            name                            => $cgi->name,
            title                           => $cgi->title,
            clone_pages_from                => $clone_from,
            created_by_user_id              => $hub->current_user->user_id,
            account_id                      => $account_id,
            enable_unplugged                => 1,

            # begin customization inheritances
            cascade_css                     => $skin->cascade_css,
            customjs_name                   => $skin->customjs_name,
            skin_name                       => $skin->skin_name,
            customjs_uri                    => $cws->customjs_uri,
            uploaded_skin                   => $cws->uploaded_skin,
            no_max_image_size               => $cws->no_max_image_size,
            invitation_filter               => $cws->invitation_filter,
            email_notification_from_address => $cws->email_notification_from_address,
            restrict_invitation_to_search   => $cws->restrict_invitation_to_search,
            invitation_template             => $cws->invitation_template,
            show_welcome_message_below_logo => $cws->show_welcome_message_below_logo,
            show_title_below_logo           => $cws->show_title_below_logo,
            header_logo_link_uri            => $cws->header_logo_link_uri,
        );

        $ws->set_logo_from_uri( uri => $cgi->logo_uri ) if $cgi->logo_uri;
    };

    if ( my $e = Exception::Class->caught(
        'Socialtext::Exception::DataValidation') 
    ) {
        $self->add_error($_) for $e->messages;
        return;
    }
    die $@ if $@;

    return $ws;
}

sub workspaces_created {
    my $self = shift;
    my $ws = Socialtext::Workspace->new( workspace_id => $self->cgi->workspace_id );

    my $settings_section = $self->template_process(
        'workspaces_created_section.html',
        workspace => $ws,
        $self->status_messages_for_template,
    );

    $self->screen_template('view/settings');
    return $self->render_screen(
        settings_table_id => 'settings-table',
        settings_section  => $settings_section,
        hub               => $self->hub,
        display_title     => loc('config.wiki-created'),
        pref_list         => $self->_get_pref_list,
    );
}

sub workspaces_unsubscribe {
    my $self = shift;

    $self->reject_guest(type => 'settings_requires_account');

    if ( $self->cgi->Button ) {
        $self->hub->current_workspace->remove_user( user => $self->hub->current_user );
        $self->redirect('');
    }

    my $settings_section = $self->template_process(
        'element/settings/workspaces_unsubscribe_section',
        workspace => $self->hub->current_workspace,
        $self->status_messages_for_template,
    );

    $self->screen_template('view/settings');
    return $self->render_screen(
        settings_table_id => 'settings-table',
        settings_section  => $settings_section,
        hub               => $self->hub,
        display_title     => loc('config.wiki.unsubscribe'),
        pref_list         => $self->_get_pref_list,
    );
}

sub workspaces_permissions {
    my $self = shift;

    $self->hub()->assert_current_user_is_admin();

    $self->_set_workspace_permissions()
        if $self->cgi()->Button();

    my $set_name
        = $self->hub->current_workspace->permissions->current_set_name();
    my $settings_section = $self->template_process(
        'element/settings/workspaces_permissions_section',
        workspace                   => $self->hub->current_workspace,
        is_appliance                => Socialtext::AppConfig->is_appliance(),
        support_address             => Socialtext::AppConfig->support_address(),
        current_permission_set_name => $set_name,
        fill_in_data                => {
            allows_page_locking => $self->hub->current_workspace->allows_page_locking,
            permission_set_name => $set_name,
            guest_has_email_in  =>
                $self->hub->current_workspace->permissions->role_can(
                    role       => Socialtext::Role->Guest(),
                    permission => ST_EMAIL_IN_PERM,
                ),
        },
        $self->status_messages_for_template,
    );

    $self->screen_template('view/settings');

    return $self->render_screen(
        settings_table_id => 'settings-table',
        settings_section  => $settings_section,
        hub               => $self->hub,
        display_title     => loc('config.wiki-acl'),
        pref_list         => $self->_get_pref_list,
    );
}

sub _set_workspace_permissions {
    my $self    = shift;
    my $ws      = $self->hub()->current_workspace();
    my $message = '';

    $self->_update_workspace_settings();
    $message .= $ws->allows_page_locking
        ? loc('wiki.enabled-locking')
        : loc('wiki.disabled-locking');

    # This was drastically simplified as of 
    # [Story: Remove Public Workspace Option]
    if (my $set_name = $self->cgi()->permission_set_name()) {
        if ($set_name eq 'member-only') {
            $message .= '  ';
            $message .= loc('acl.changed=wiki,set', $ws->name(), loc($set_name));
            $ws->permissions->set( set_name => $set_name );
        }
    }

    # This has to go after the perm settings because ST_EMAIL_IN_PERM
    # _is_ a perm setting.
    my $do = $self->cgi()->guest_has_email_in() ? 'add' : 'remove';
    $ws->permissions->$do(
        role       => Socialtext::Role->Guest(),
        permission => ST_EMAIL_IN_PERM,
    );

    if ($self->cgi()->guest_has_email_in()) {
        $message .= ' ' . loc('config.anyone-can-email=wiki', $ws->name());
    } else {
        if ($ws->permissions->current_set_name() =~ /public-(?:read|comment)-only/) {
            $message .= ' ';
            $message .= loc('config.members-can-email=wiki', $ws->name());
        } else {
            $message .= ' ';
            $message .= loc('config.registered-can-email=wiki', $ws->name());
        }
    }

    $self->message( $message );
}

package Socialtext::WorkspacesUI::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'Button';
cgi name => '-clean';
cgi logo_uri => '-clean';
cgi 'logo_type';
cgi logo_file => '-upload';
cgi 'title';
cgi 'selected_workspace_id';
cgi 'incoming_email_placement';
cgi 'email_notify_is_enabled';
cgi 'homepage_is_dashboard';
cgi 'homepage_is_weblog';
cgi 'homepage_weblog';
cgi 'workspace_id';
cgi 'user_email';
cgi 'user_first_name';
cgi 'user_last_name';
cgi 'sort_weblogs_by_create';
cgi 'account_id';
cgi 'account_name';
cgi 'permission_set_name';
cgi 'guest_has_email_in';
cgi 'enable_unplugged';
cgi 'uploaded_skin';
cgi 'skin_reset';
cgi skin_file => '-upload';
cgi 'clone_pages_from';
cgi 'allows_page_locking';

1;
