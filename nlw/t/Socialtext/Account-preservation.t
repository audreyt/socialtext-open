#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 11;
use Test::Differences qw(eq_or_diff);
use Test::Socialtext::Account qw(export_account import_account_ok);
use Test::Socialtext::Workspace;
use Test::Socialtext::Group;
use Test::Socialtext::User;

fixtures(qw( db ));

###############################################################################
# TEST: Ownership/creation data is preserved across Account export/import.
preserved_across_export: {
    # Set up an Account with a Workspace, Group, and some Users.
    my $account = create_test_account_bypassing_factory();

    my $group_owner = create_test_user(
        account     => $account,
        first_name  => 'Guybrush',
        middle_name => 'Ulysses',
        last_name   => 'Threepwood',
    );
    my $group = create_test_group(
        account => $account,
        user    => $group_owner,
    );

    my $ws_owner = create_test_user(account => $account);
    my $ws = create_test_workspace(
        account => $account,
        user    => $ws_owner,
    );

    my $inviter = create_test_user(account => $account);
    my $invitee = create_test_user(
        account            => $account,
        created_by_user_id => $inviter->user_id,
    );

    $inviter->record_login();
    $inviter = Socialtext::User->new(user_id => $inviter->user_id);

    # Dump data on all of the entities as they exist now.
    my %before = (
        account         => _dump_account($account),
        group_owner     => _dump_user($group_owner),
        group           => _dump_group($group),
        workspace_owner => _dump_user($ws_owner),
        workspace       => _dump_workspace($ws),
        inviter         => _dump_user($inviter),
        invitee         => _dump_user($invitee),
    );

    ###########################################################################
    # Export the Account, nuke the system from space, then re-import.
    my $export_dir = export_account($account);
    Test::Socialtext::Workspace->delete_recklessly($ws);
    Test::Socialtext::Group->delete_recklessly($group);
    Test::Socialtext::User->delete_recklessly($_)
        for ($group_owner, $ws_owner, $inviter, $invitee);
    Test::Socialtext::Account->delete_recklessly($account);
    import_account_ok($export_dir);
    ###########################################################################

    # Re-query all of the entities.
    $group_owner = Socialtext::User->new(username  => $group_owner->username);
    $ws_owner    = Socialtext::User->new(username  => $ws_owner->username);
    $inviter     = Socialtext::User->new(username  => $inviter->username);
    $account     = Socialtext::Account->new(name   => $account->name);
    $group       = $account->groups->next();
    $ws          = Socialtext::Workspace->new(name => $ws->name);
    $invitee     = Socialtext::User->new(username  => $invitee->username);

    # Dump data on all of the entities as they exist after the import.
    my %after = (
        account         => _dump_account($account),
        group_owner     => _dump_user($group_owner),
        group           => _dump_group($group),
        workspace_owner => _dump_user($ws_owner),
        workspace       => _dump_workspace($ws),
        inviter         => _dump_user($inviter),
        invitee         => _dump_user($invitee),
    );

    # Compare everything to make sure it matches up right, using a custom
    # flattener so that Test::Differences outputs a reasonably easy to follow
    # diff.
    foreach my $key (keys %before) {
        my $received = _flatten($after{$key});
        my $expected = _flatten($before{$key});
        eq_or_diff $received, $expected, "$key preserved across export/import";
    }
}

sub _flatten {
    my $data = shift;
    my $flat = [ ];
    foreach my $key (sort keys %{$data}) {
        my $val = $data->{$key};
        $val = '' unless (defined $val);
        if (ref($val) eq 'ARRAY') {
            $val = '[ ' . join(', ',@{$val}) . ' ]';
        }
        push @{$flat}, qq{$key => $val};
    }
    return $flat;
}

###############################################################################
# Custom dumper methods, to ensure that we check for the fields we expect to
# see preserved across export/import.
#
# These methods *are* different than the standard "to_hash()" or
# "serialize_to_export()" methods; we *want* a separate dump routine here so
# that we can verify that those routines are DTRT across an export.
sub _dump_account {
    my $acct = shift;
    my $data = {
        plugins              => [ $acct->plugins_enabled ],
        all_users_workspaces => [
            map { $_->name } @{ $acct->all_users_workspaces }
        ],
    };
    foreach my $field (qw(
        account_type
        allow_invitation
        desktop_2nd_bg_color
        desktop_bg_color
        desktop_header_gradient_bottom
        desktop_header_gradient_top
        desktop_highlight_color
        desktop_link_color
        desktop_logo_uri
        desktop_text_color
        email_addresses_are_hidden
        is_exportable
        is_system_created
        name
        restrict_to_domain
        skin_name
        )) {
        $data->{$field} = $acct->$field();
    }
    return $data;
}

sub _dump_group {
    my $group = shift;
    my $data = {
        created_by_username  => $group->creator->username,
        creation_datetime    => $group->creation_datetime,
        primary_account_name => $group->primary_account->name,
    };
    foreach my $field (qw(
        description
        driver_group_name
        is_system_managed
        permission_set
        )) {
        #plugins
        $data->{$field} = $group->$field();
    }
    return $data;
}

sub _dump_workspace {
    my $ws   = shift;
    my $dump = {
        account_name      => $ws->account->name,
        creation_datetime => $ws->creation_datetime,
        creator_username  => $ws->creator->username,
    };
    foreach my $field (qw(
        allows_html_wafl
        allows_page_locking
        allows_skin_upload
        basic_search_only
        cascade_css
        comment_by_email
        comment_form_note_bottom
        comment_form_note_top
        comment_form_window_height
        custom_title_label
        customjs_name
        customjs_uri
        email_addresses_are_hidden
        email_notification_from_address
        email_notify_is_enabled
        email_weblog_dot_address
        enable_unplugged
        external_links_open_new_window
        header_logo_link_uri
        homepage_is_dashboard
        homepage_weblog
        incoming_email_placement
        invitation_filter
        invitation_template
        logo_uri
        name
        no_max_image_size
        page_title_prefix
        prefers_incoming_html_email
        restrict_invitation_to_search
        show_title_below_logo
        show_welcome_message_below_logo
        skin_name
        sort_weblogs_by_create
        title
        unmasked_email_domain
        uploaded_skin
        )) {
        $dump->{$field} = $ws->$field();
    }
    return $dump;
}

sub _dump_user {
    my $user = shift;
    my $data = {
        creator_username     => $user->creator->username,
        creation_datetime    => $user->creation_datetime,
        last_login_datetime  => $user->last_login_datetime,
        primary_account_name => $user->primary_account->name,
    };
    foreach my $field (qw(
        display_name
        email_address
        email_address_at_import
        first_name
        middle_name
        is_business_admin
        is_system_created
        is_technical_admin
        last_name
        password
        username
        )) {
        $data->{$field} = $user->$field();
    }
    return $data;
}
