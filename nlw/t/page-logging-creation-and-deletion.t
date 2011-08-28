#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Socialtext::Log', qw( :tests );
use Test::Socialtext tests => 13;
use Socialtext::Page;
use Socialtext::User;
use Socialtext::Workspace;
use Socialtext::String ();

fixtures(qw( clean empty ));

my $workspace  = 'empty';
my $user       = Socialtext::User->SystemUser;

# edit_content, delete_page, and rename_page are magical.


Page_create_delete_restore_edit: {
    my $page_title = 'Delete and Edit Test';

    Test_page_create: {
        clear_log();
        create_page($workspace, $page_title);
        logged_like('info', 'CREATE,PAGE,');
    }

    Test_page_delete: {
        my $hub = setup_hub($workspace, $page_title, 'delete_page');
        clear_log();

        $hub->pages->current->delete( user => $user );
        logged_like('info', 'DELETE,PAGE,');
    }

    Test_page_recreate: {
        my $hub = setup_hub($workspace, $page_title);
        clear_log();

        $hub->pages->current->create(
            content          => 'Testing...',
            creator          => $user,
            title            => $page_title,
        );
        logged_like('info', 'RESTORE,PAGE,');
    }

    Test_page_edit: {
        my $hub  = setup_hub($workspace, $page_title);
        my $page = $hub->pages->current;
        clear_log();

        $page->edit_rev;
        $page->store(
            content => 'Testing, 1, 2, 3.',
            revision => $page->revision_count + 4,
            subject => $page_title,
            user => $user,
            original_page_id => Socialtext::String::title_to_id($page_title),
        );
        logged_like('info', 'EDIT,PAGE,');
        logged_not_like('info', 'CREATE,PAGE,');
    }
}

Page_create_rename_rename: {
    my $page_title = 'Rename Test';

    Create_page: {
        clear_log();
        create_page($workspace, $page_title);
        logged_like('info', 'CREATE,PAGE,', 'Test setup for rename');
    }

    Rename_page: {
        my $hub = setup_hub($workspace, $page_title, 'rename_page');
        clear_log();

        $hub->pages->current->rename(
            "Renamed $page_title",
            '',
            '',
            0
        );
        logged_like('info', 'RENAME,PAGE,');
    }

    Rename_again: {
        my $hub = setup_hub($workspace, $page_title, 'rename_page');
        clear_log();

        $hub->pages->current->rename(
            "Renamed $page_title",
            '',
            '',
            1
        );
        logged_not_like('info', 'CREATE,PAGE,');
    }
}

Page_create_duplicate_duplicate: {
    my $page_title = 'Duplicate Page Test';

    Create_page: {
        clear_log();
        create_page($workspace, $page_title);
        logged_like('info', 'CREATE,PAGE,', 'Test setup for duplicate');
    }

    Duplicate_page: {
        my $hub = setup_hub($workspace, $page_title);
        clear_log();

        $hub->pages->current->duplicate(
            Socialtext::Workspace->new( name => $workspace ),
            "Duplicate of $page_title",
            '',
            '',
            0
        );
        logged_like('info', 'CREATE,PAGE,', 'Duplicate has correct log entry');
    }

    Duplicate_again: {
        my $hub = setup_hub($workspace, $page_title);
        clear_log();

        $hub->pages->current->duplicate(
            Socialtext::Workspace->new( name => $workspace ),
            "Duplicate of $page_title",
            '',
            '',
            1
        );
        logged_not_like('info', 'CREATE,PAGE,');
    }
}

Page_undelete: {
    my $page_title = 'Undelete page';

    create_page($workspace, $page_title);
    
    my $hub = setup_hub($workspace, $page_title, 'delete_page');
    $hub->pages->current->delete( user => $user );

    Test_page_undelete: {
        my $hub = setup_hub($workspace, $page_title, 'undelete_page');
        $hub->rest->query->param( page_id => 'undelete_page' );
        clear_log();

        $hub->delete_page->undelete_page();

        logged_like('info', 'RESTORE,PAGE,');
        logged_not_like('info', 'CREATE,PAGE,');
    }
}

#########
# helpers
#########

sub setup_hub {
    my $workspace  = shift;
    my $page_title = shift;
    my $action     = shift || 'edit_content';

    my $hub = new_hub( $workspace );
    $hub->rest->query->param( action => $action );

    my $page = $hub->pages->new_from_name( $page_title );
    $hub->pages->current( $page );

    return $hub;
}

sub create_page {
    my $workspace  = shift;
    my $page_title = shift;

    my $hub = setup_hub( $workspace, $page_title );

    $hub->pages->current->create(
        content          => 'Testing...',
        creator          => $user,
        title            => $page_title,
    );
}

