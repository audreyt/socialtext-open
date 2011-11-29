#!perl
# @COPYRIGHT@
use mocked qw(Socialtext::l10n system_locale); # Has to come firstest.
use Test::More;
use Test::Socialtext;
use Test::Socialtext::Fatal;
use Test::Differences;
use strict;
use warnings;

# Fixtures: clean, help
#
# Need to know that the "help" workspace is the only one present when we start
# our tests.
fixtures( 'clean', 'help' );

use Socialtext::EmailAlias;
use Socialtext::File;
use Socialtext::Paths;
use Socialtext::Account;
use Socialtext::Workspace;
use Socialtext::Cache;
use utf8;

Socialtext::Cache->clear('authz_plugin');

{
    is( Socialtext::Workspace->Count(), 1, 'Only help workspace in DBMS yet' );
}

ALL_WORKSPACE_IDS_AND_NAMES: {
    my $info = Socialtext::Workspace->AllWorkspaceIdsAndNames();
    is_deeply(
        $info,
        [
            [ 1, 'help-en' ],
        ],
        "Checking AllWorkspaceIdsAndNames"
    );
}

{
    my $ws = Socialtext::Workspace->create(
        name       => 'short-name',
        title      => 'Longer Title',
        account_id => Socialtext::Account->Socialtext()->account_id,
    );
    isa_ok( $ws, 'Socialtext::Workspace' );

    is( $ws->name,  'short-name',   'name of new workspace is short-name' );
    is( $ws->title, 'Longer Title', 'title of new workspace is Longer Title' );
    is( $ws->account->name, 'Socialtext',
        'name of account for workspace is SOcialtext' );
    ok( $ws->email_notify_is_enabled,
        'new workspace defaults to email notify enabled' );
    is( $ws->created_by_user_id, Socialtext::User->SystemUser()->user_id(),
        'creator is system user' );
    is( $ws->account_id, Socialtext::Account->Socialtext()->account_id(),
        'account id is for Socialtext account' );
    is( Socialtext::User->SystemUser()->workspace_count(), 0,
        'system user is not in any workspaces' );
    ok( Socialtext::EmailAlias::find_alias( $ws->name ), 'found alias for new workspace' );

    is( Socialtext::Workspace->Count(), 2, 'workspace count is 2' );

    my $hostname = Socialtext::AppConfig->web_hostname;

    if ( my $custom_port = Socialtext::AppConfig->custom_http_port ) {
        $hostname .= ":$custom_port";
    }
    like( $ws->uri, qr{\Qhttp://$hostname/short-name/\E}i,
          'check workspace uri' );

    Workspace_skin_should_override_account_skin: {
        $ws->update(skin_name => 'reds3');
        $ws = Socialtext::Workspace->new(name => $ws->name);
        is( $ws->skin_name, '', 'workspace skin is not settable' );

        $ws->account->update(skin_name => 's3');
        $ws = Socialtext::Workspace->new(name => $ws->name);
        is $ws->skin_name, '', 'workspace skin is not reset when account is updated';
    }
}

{
    eval {
        Socialtext::Workspace->create(
            name                     => 'short-name',
            title                    => undef,
            incoming_email_placement => 'foobar',
            skin_name                => 'does-not-exist',
        );
    };
    my $e = $@;
    check_errors($e);
    ok( ( grep { /account must be specified/ } $e->messages ),
        'got error message saying account is required' );
}

NO_DASH_IN_NAME:
{
    eval {
        Socialtext::Workspace->create(
            name       => '-dash-start',
            title      => 'dash at start',
            account_id => Socialtext::Account->Socialtext()->account_id,
        );
    };
    my $e = $@;
    ok( ( grep { /Workspace name may not begin with -/ } $e->messages ),
        'got error message saying name may not begin with -' );
}

NO_DASH_IN_TITLE:
{
    eval {
        Socialtext::Workspace->create(
            name       => 'no-dash-start',
            title      => '-dash at start',
            account_id => Socialtext::Account->Socialtext()->account_id,
        );
    };
    my $e = $@;
    ok( ( grep { /and may not begin with a '-'/ } $e->messages ),
        'and may not begin with a -' );
}

Different_name_case: {
    Socialtext::Workspace->create(
        name       => 'monkey-rubber',
        title      => 'Monkey Rubber',
        account_id => Socialtext::Account->Socialtext()->account_id,
    );

    ok(Socialtext::Workspace->new( name => 'monkey-rubber' ),
       'Loaded with same case');
    ok(Socialtext::Workspace->new( name => 'Monkey-Rubber' ),
       'Loaded with different case');
}

Undef_skin_name: {
    Socialtext::Workspace->create(
        name       => 'undef-skin',
        title      => 'Undef Skin',
        account_id => Socialtext::Account->Socialtext()->account_id,
        skin_name  => undef,
    );

    ok(Socialtext::Workspace->new( name => 'undef-skin' ),
       'undef skin_name worked okay');
}

{
    Socialtext::Workspace->create(
        name       => 'short-name-2',
        title      => 'Longer Title 2',
        account_id => Socialtext::Account->Socialtext()->account_id,
    );
    my $ws = Socialtext::Workspace->new( name => 'short-name' );

    eval {
        $ws->update(
            title                    => undef,
            incoming_email_placement => 'foobar',
            skin_name                => 'does-not-exist',
        );
    };
    check_errors($@);
}


Delete_a_workspace: {
    my $ws = Socialtext::Workspace->new( name => 'short-name' );
    $ws->delete;

    ok( ! Socialtext::EmailAlias::find_alias('short-name'),
        'alias for short-name-2 does not exist after workspace is deleted' );
}

INHERITING_WORKSPACE_INVITE:
{
    my $ws = Socialtext::Workspace->create(
        name                => 'invite-inherit',
        title               => 'Invitation Inheritance',
        account_id          => Socialtext::Account->Socialtext()->account_id,
        invitation_template => 'my_template',
        invitation_filter => 'friends',
        restrict_invitation_to_search => '1',
    );

    is(
        $ws->invitation_filter, 'friends',
        "Workspace inherited the invitation filter correctly\n"
    );
    is(
        $ws->invitation_template, 'my_template',
        "Workspace inherited the invitation template correctly\n"
    );
    is(
        $ws->restrict_invitation_to_search, '1',
        "Workspace inherited the invitation search restriction correctly\n"
    );
}

EMAIL_NOTIFICATION_FROM_ADDRESS:
{
    my $ws = Socialtext::Workspace->create(
        name       => 'email-address-test',
        title      => 'The Workspace Title',
        account_id => Socialtext::Account->Socialtext()->account_id,
    );

    is( $ws->email_notification_from_address(),
        'noreply@socialtext.com',
        'default from address is noreply@socialtext.com' );

    is( $ws->formatted_email_notification_from_address(),
        '"The Workspace Title" <noreply@socialtext.com>',
        'formatted default from address includes workspace title and noreply@socialtext.com' );

    $ws->update( email_notification_from_address => 'bob@example.com' );

    is( $ws->email_notification_from_address(),
        'bob@example.com',
        'default from address now bob@example.com' );

    is( $ws->formatted_email_notification_from_address(),
        '"The Workspace Title" <bob@example.com>',
        'formatted default from address now includes workspace title and bob@example.com' );

    # Tests RT #21870
    $ws->update( title => q{Title with, a comma} );

    is( $ws->email_notification_from_address(),
        'bob@example.com',
        'default from address still just bob@example.com' );

    is( $ws->formatted_email_notification_from_address(),
        q{"Title with, a comma" <bob@example.com>},
        'default from address includes workspace title and bob@example.com' );
}

{
    eval {
        Socialtext::Workspace->create(
            name                     => 'a',
            title                    => 'b',
            incoming_email_placement => 'foobar',
            skin_name                => 'does-not-exist',
        );
    };
    my $e = $@;
    ok( ( grep {/3 and 30/} $e->messages ),
        'name < 3 characters is not allowed' );
    ok( ( grep {/2 and 64/} $e->messages ),
        'title < 2 characters is not allowed' );
}

{
    eval {
        Socialtext::Workspace->create(
            name  => '123456789012345678901234567890A',
            title =>
                '1234567890123456789012345678901234567890123456789012345678901234A',
            incoming_email_placement => 'foobar',
            skin_name                => 'does-not-exist',
        );
    };
    my $e = $@;
    ok( ( grep {/3 and 30/} $e->messages ),
        'name > 30 characters is not allowed' );
    ok( ( grep {/2 and 64/} $e->messages ),
        'title > 64 characters is not allowed' );
}

{
    my $ws = Socialtext::Workspace->create(
        name       => 'logo-test',
        title      => 'logo testing',
        account_id => Socialtext::Account->Socialtext()->account_id,
    );

    eval { $ws->update( logo_uri => '/foo/bar.png' ) };
    like( $@, qr/cannot set logo_uri/i, 'cannot set logo_uri directly via update()' );

    my $file = 't/extra-attachments/FormattingTest/thing.png';
    $ws->set_logo_from_file(
        filename   => $file,
    );
    like( $ws->logo_uri, qr{/logos/logo-test/logo-test-.+\.png$},
          'logo uri has been updated' );
    ok( -f $ws->logo_filename, 'saved logo file exists' );

    eval {
        $ws->set_logo_from_file(
            filename   => 'foobar.notanimage',
        );
    };
    like(
        $@, qr/must be a gif.+/,
        'cannot set the logo when the extension is not a recognized file type'
    );

    ok( -f $ws->logo_filename,
        'old logo was not deleted when trying to set an invalid logo' );

    # test a text file posing as an image
    my $text_file = 't/attachments/foo.txt';
    eval {
        $ws->set_logo_from_file(
            filename   => $text_file,
        );
    };

    like(
        $@, qr/\QLogo file must be a gif, jpeg, or png file\E/,
        'cannot set logo with non image file posing as one'
    );

    $ws->set_logo_from_uri( uri => 'http://example.com/image.png' );
    is( $ws->logo_uri, 'http://example.com/image.png', 'logo_uri has changed' );
    is( $ws->logo_filename, undef, 'logo_filename is now undef' );
}

{
    my $user = Socialtext::User->SystemUser;
    my $ws = Socialtext::Workspace->new( name => 'short-name-2' );

    eval { $ws->assign_role_to_user(
               user => $user,
               role => Socialtext::Role->Member(),
           ) };
    like( $@, qr/system-created/, 'system user cannot be assigned a role in a workspace' );
    is( $user->workspace_count, 0, 'workspace count for system user is 0' );
}

{
    my $user = Socialtext::User->create(
        username      => 'devnull11@socialtext.com',
        email_address => 'devnull11@socialtext.com',
        password      => 'd3vnu11l',
    );
    my $ws = Socialtext::Workspace->new( name => 'short-name-2' );

    eval { $ws->assign_role_to_user(
               user => $user,
               role => Socialtext::Role->Guest(),
           ) };
    like( $@, qr/cannot explicitly assign/i, 'cannot assign the guest role' );

    eval { $ws->assign_role_to_user(
               user => $user,
               role => Socialtext::Role->AuthenticatedUser(),
           ) };
    like( $@, qr/cannot explicitly assign/i, 'cannot assign the authenticated user role' );
}

{
    my $user = Socialtext::User->new( username => 'devnull11@socialtext.com' );
    my $ws = Socialtext::Workspace->create(
        name               => 'short-name-3',
        title              => 'Longer Title 3',
        created_by_user_id => $user->user_id,
        account_id         => Socialtext::Account->Socialtext()->account_id,
    );

    is( $user->workspace_count, 1, 'devnull1 is in one workspace' );
    is( $user->workspaces()->next()->workspace_id(), $ws->workspace_id(),
        'devnull1 is in the workspace that was just created' );
    ok( $ws->user_has_role( user => $user, role => Socialtext::Role->Admin() ),
        'devnull1 is a admin in the workspace that was just created' );
}

{
    my $ws = Socialtext::Workspace->create(
        name       => 'short-name-4',
        title      => 'Longer Title 4',
        account_id => Socialtext::Account->Socialtext()->account_id,
    );

    {
        my @uris = ( 'http://example.com/ping', 'http://example.com/ping2' );
        $ws->set_ping_uris( uris => \@uris );

        is_deeply( [ sort $ws->ping_uris ], \@uris,
                   'ping uris matches what was just set', );
    }

    {
        my @uris = ( 'https://example.com/ping3', 'https://example.com/ping3' );
        $ws->set_ping_uris( uris => \@uris );
        is_deeply( [ $ws->ping_uris ], ['https://example.com/ping3'],
            'set_ping_uris discards duplicates, allows https' );
    }

    {
        my @uris = ( 'file:///etc/hostname', 'http://example.com/ping3' );
        eval { $ws->set_ping_uris( uris => \@uris ) };
        like( $@, qr{file:///.+not a valid},
              'cannot use non http(s) URIs for pings' );
    }
}

{
    Socialtext::EmailAlias::create_alias( 'has-alias' );
    eval { Socialtext::Workspace->create(
               name         => 'has-alias',
               title        => 'Has an alias',
               account_id   => Socialtext::Account->Socialtext()->account_id,
           ) };
    ok( $@, ' alias matching the ws name already existed' );
    ok( ! Socialtext::Workspace->new( name => 'has-alias' ),
        'The has-alias workspace exists' );
}

Clone_from_workspace: {
    # put some non-default content in an empty workspace.
    my $to_clone_hub = new_hub('no-pages');
    my $page = Socialtext::Page->new( hub => $to_clone_hub )->create(
        title   => 'Monkey Favorites',
        content => 'Bananas, Trees, Jungles',
        creator => $to_clone_hub->current_user
    );

    # make sure we have a title page for later tests.
    my $title_page = Socialtext::Page->new( hub => $to_clone_hub )->create(
        title   => 'No Pages',
        content => 'There are no pages.',
        creator => $to_clone_hub->current_user
    );

    my $ws = Socialtext::Workspace->create(
        name             => 'cloned',
        title            => 'Cloned from',
        account_id       => Socialtext::Account->Socialtext()->account_id,
        clone_pages_from => $to_clone_hub->current_workspace->name,
    );

    # Make sure the new workspace 'inherits' the homepage.
    my $cloned_hub = new_hub( 'cloned' );
    my $cloned_title_page = $cloned_hub->pages->new_from_name( $ws->title );
    like $cloned_title_page->content(), qr/There are no pages/, 
        'New workspace inherits the homepage.';

}

clone_workspace_pages: {
    my $user = create_test_user();
    my $dest = create_test_workspace();
    my $template = create_test_workspace();

    my $hub = new_hub($template->name, $user->username);
    my $keep = $hub->pages->new_from_name('some page to copy');
    $hub->pages->current->create(
        content => 'nothing special',
        creator => $user,
        title => 'some_page_to_copy'
    );

    my $toss = $hub->pages->new_from_name('some workspace usage 2011 04 23 past week');
    $hub->pages->current->create(
        content => 'lotsa usage',
        creator => $user,
        title => 'some_workspace_usage_2011_04_23_past_week',
    );

    my $deleted = $hub->pages->new_from_name('Deleted Page');
    $hub->pages->current->create(
        content => 'i should not be here',
        creator => $user,
        title => 'deleted_page',
    );
    $deleted->delete(user=>$user);

    $dest->clone_workspace_pages($template->name);

    $hub->current_workspace($dest);
    my @pages = map { $_->page_id } $hub->pages->all();
    eq_or_diff \@pages, [qw/some_page_to_copy/], 'correct pages cloned';
}

NON_ASCII_WS_NAME: {
    eval { Socialtext::Workspace->create(
        name               => 'high-ascii-' . Encode::decode( 'latin-1', chr(155) ),
        title              => 'A title',
        account_id         => Socialtext::Account->Socialtext()->account_id,
        skip_default_pages => 1,
    ) };
    like( $@, qr/\Qmust contain only lower-case letters, numbers, underscores/,
          'workspace name with non-ASCII letters is invalid' );
}

customjs_uri: {
    my $ws = Socialtext::Workspace->create(
        name       => 'customjs-1',
        title      => 'Custom JS 1',
        account_id => Socialtext::Account->Socialtext()->account_id,
    );
    is( $ws->customjs_uri, '', 'Default custom javascript URI is blank'),
    is( $ws->customjs_name, '', 'Default custom javascript name is blank'),

    $ws->update(customjs_name => '');
    $ws->update(customjs_uri => 'custom.js');
    is( $ws->customjs_uri, 'custom.js', 'Custom javascript set correctly'),

    $ws->update(customjs_uri => '');
    $ws->update(customjs_name => 'my_company');
    is( $ws->customjs_name, 'my_company', 'Custom javascript set correctly'),
}

CHANGE_WORKSPACE_TITLE: {
    my $ws = Socialtext::Workspace->create(
        name               => 'title-tester',
        title              => 'Original Title',
        account_id         => Socialtext::Account->Socialtext()->account_id,
    );

    my $main = Socialtext->new();
    my $hub  = $main->load_hub(
        current_workspace => $ws,
        current_user      => Socialtext::User->SystemUser(),
    );
    $hub->registry()->load();

    my $old_front_page = $hub->pages()->new_from_name( $ws->title() );
    ok( $old_front_page->exists(), 'Page named after workspace title exists' );

    $ws->update( title => 'My Brand New Title' );

    my $new_front_page = $hub->pages()->new_from_name( $ws->title() );
    ok( $new_front_page->exists(), 'Page named after new workspace title exists' );
    like( $new_front_page->content(), qr/Welcome to the " \+ Socialtext.wiki_title/,
          'new front page has expected content' );

    $ws->update( title => 'Original Title' );

    $old_front_page = $hub->pages()->new_from_name( $ws->title() );
    ok( $old_front_page->exists(), 'Page named after original workspace title exists' );
    like( $old_front_page->content(), qr/Welcome to the " \+ Socialtext.wiki_title/,
          'original front page has expected content after rename to original title' );
}

TITLE_IS_VALID: {
    #
    # Check length boundary conditions.
    #
    
    ok( ! Socialtext::Workspace->TitleIsValid( title => 'a'),
        'Too-short workspace title fails'
    );

    ok( ! Socialtext::Workspace->TitleIsValid( title => ('a' x 65) ),
        'Too-long workspace title fails'
    );

    ok( Socialtext::Workspace->TitleIsValid( title => 'aa' ),
        'Workspace title of exactly 2 characters succeeds'
    );
    
    ok( Socialtext::Workspace->TitleIsValid( title => ('a' x 64) ),
        'Workspace title of exactly 64 characters succeeds'
    );

    #
    # Check the title which had the utf8 characters.
    #
    ok( ! Socialtext::Workspace->TitleIsValid( title => 'あ'),
        'Too-short workspace utf8 title fails'
    );

    ok( ! Socialtext::Workspace->TitleIsValid( title => ('あ' x 29) ),
        'Too-long workspace utf8 title fails after URL encoding'
    );

    ok( Socialtext::Workspace->TitleIsValid( title => 'ああ' ),
        'Workspace title of exactly 2 utf8 characters succeeds'
    );
    
    ok( Socialtext::Workspace->TitleIsValid( title => ('あ' x 28) ),
        'Workspace title of exactly 28 utf8 charaters succeeds'
    );
}

NAME_IS_VALID: {

    # Check an invalid name, then a valid name, to make
    # sure that the errors from the invalid name aren't
    # preserved between calls.
    #
    {
        Socialtext::Workspace->NameIsValid( name => 'aa');
        ok( Socialtext::Workspace->NameIsValid( name => 'valid'),
            'Errors are cleared from default error list between calls'
        );
    }

    # Make sure simple valid names work.
    #
    ok( Socialtext::Workspace->NameIsValid( name => 'valid'),
        'Valid workspace name succeeds'
    );

    #
    # Check length boundary conditions.
    #

    ok( ! Socialtext::Workspace->NameIsValid( name => 'aa'),
        'Too-short workspace name fails'
    );

    ok( ! Socialtext::Workspace->NameIsValid( name => ('a' x 31) ),
        'Too-long workspace name fails'
    );

    ok( Socialtext::Workspace->NameIsValid( name => 'aaa' ),
        'Workspace name of exactly 3 characters succeeds'
    );

    ok( Socialtext::Workspace->NameIsValid( name => ('a' x 30) ),
        'Workspace name of exactly 30 characters succeeds'
    );

    #
    # Other miscellaneous problems
    #

    ok( ! Socialtext::Workspace->NameIsValid( name => q() ),
        'Blank workspace name fails'
    );

    ok( ! Socialtext::Workspace->NameIsValid( name => 'data' ),
        'Reserved word as workspace name fails'
    );

    ok( ! Socialtext::Workspace->NameIsValid( name => 'COWLOVE'),
        'No capitals in workspace name'
    );

    # Check basic parameter validation
    {
        my $e;

        eval { Socialtext::Workspace->NameIsValid( name => undef ) };

        $e = $@;

        like( $e->message,
             qr/'name' parameter .+ not one of the allowed types/i,
            'Undef workspace name generates expected exception'
        );

        eval { Socialtext::Workspace->NameIsValid( name => 'aaa', errors => '' ) };

        $e = $@;

        like( $e->message,
            qr/'errors' parameter .+ not one of the allowed types/i,
            'Undef errors array generates expected exception'
        );
    }

    # Check for specific messages in the error lists
    {
        my @errors;

        Socialtext::Workspace->NameIsValid( name => 'aa', errors => \@errors );
        ok( ( grep { qr/3 and 30/i } @errors ),
            'Expected error message was returned for too-short workspace name'
        );

        @errors = ();
        Socialtext::Workspace->NameIsValid( name => 'st_stuff', errors => \@errors );
        ok( ( grep { qr/reserved word/i } @errors ),
            'Expected error message was returned for reserved workspace name'
        );
    }

    # Check for multiple errors in a single workspace name
    {
        my @errors;
        Socialtext::Workspace->NameIsValid(
            name    => 'st_illegal/and/reserved',
            errors  => \@errors
        );

        is( scalar(@errors), 2,
            'Correct number of errors for workspace name with multiple problems'
        );

        ok( ( grep { qr/3 and 30/i } @errors ),
            'Error list contains length message'
        );

        ok( ( grep { qr/reserved word/i } @errors ),
            'Error list contains reserved word message'
        );
    }
}

HELP_WORKSPACE_WITH_WS_MISSING: {
    system_locale('xx');  # Set locale to xx, but help-xx doesn't exist yet.

    my $ws1 = Socialtext::Workspace->help_workspace();
    is( $ws1->name, "help-en", "help_workspace() is help-en" );

    my $ws2 = Socialtext::Workspace->new( name => "help" );
    is( $ws2->name, "help-en", "new(name => help) DTRT" );
}

HELP_WORKSPACE_WITH_WS_NOT_MISSING: {
    system_locale('xx');
    Socialtext::Workspace->create(
        name       => 'help-xx',
        title      => 'Help XX',
        account_id => Socialtext::Account->Socialtext()->account_id,
    );

    my $ws1 = Socialtext::Workspace->help_workspace();
    is( $ws1->name, "help-xx", "help_workspace() is help-xx" );

    my $ws2 = Socialtext::Workspace->new( name => "help" );
    is( $ws2->name, "help-xx", "new(name => help) DTRT" );
}

HELP_WORKSPACES: {
    my $ws = [ sort Socialtext::Workspace->Help_workspaces() ];
    eq_or_diff $ws, [ qw/help-adminguide help-en/ ], 'have proper help wksp';
}

CASCADE_CSS: {
    my $ws = Socialtext::Workspace->create(
        name       => 'cscss-1',
        title      => 'Cascade CSS',
        account_id => Socialtext::Account->Socialtext()->account_id,
    );
    is( $ws->cascade_css, 1, 'Worksdpace defaults to cascading CSS'),

    $ws->update(cascade_css => 0);
    is( $ws->cascade_css, 0, 'Cascading CSS set correctly'),
}

EXPORT_WITH_MISSING_DIR: {
    my $ws = Socialtext::Workspace->create(
        name       => 'export-1',
        title      =>  'Export Workspace',
        account_id => Socialtext::Account->Socialtext()->account_id,
    );

    eval {
        $ws->export_to_tarball( dir  => '/sys/doesnt-exist',
                                name => $ws->name );
    };

    like($@,
        qr/Export Directory .+ does not exist./i,
        'Non-existent export directory generates expected error message'
    );
}

Rudimentary_Plugin_Test: {
    my $ws = Socialtext::Workspace->create(
        name       => 'pluggy',
        title      =>  'Export Workspace',
        account_id => Socialtext::Account->Socialtext()->account_id,
    );
    $ws->enable_plugin('socialcalc');
    is($ws->is_plugin_enabled('socialcalc'), '1', 'socialcalc enabled.');
    is_deeply([ $ws->plugins_enabled ], [ 'socialcalc' ],
        'list enabled plugins');
    $ws->disable_plugin('socialcalc');
    is($ws->is_plugin_enabled('socialcalc'), '0', 'socialcalc disabled.');
    is_deeply([ $ws->plugins_enabled ], [],
        'list enabled plugins');

    ok exception { $ws->enable_plugin('people') }, 'cannot enable people';
    ok(!$ws->is_plugin_enabled('people'), 'people did not get enabled');
    ok exception { $ws->enable_plugin('whatevs') }, 'cannot enable whatevs';
    ok(!$ws->is_plugin_enabled('whatevs'), 'fake plugin did not get enabled');
}

done_testing;
exit;


sub check_errors {
    my $e = shift;
    ok( $e,
        'got an error after giving bad data to Socialtext::Workspace->create'
    );

    for my $regex (
        qr/one of top, bottom, or replace/,
        qr/title is a required field/,
        ) {
            my $errors = join ', ', $e->messages;
            like $errors, $regex, "got error message matching $regex";
    }
}
