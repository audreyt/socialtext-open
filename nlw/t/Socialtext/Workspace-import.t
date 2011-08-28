#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::AppConfig;
use Test::Socialtext tests => 17;
use Test::Socialtext::User;
fixtures( 'admin', 'destructive' );

my $test_dir = Socialtext::AppConfig->test_dir();

my $hub = new_hub('admin');

my $admin = $hub->current_workspace();
$admin->permissions->set( set_name => 'public-read-only' );
$admin->set_logo_from_uri( uri => 'http://example.com/logo.gif' );

my $user = $hub->current_user;
my $singapore = join '', map { chr($_) } 26032, 21152, 22369;
my $external_id = Test::Socialtext->create_unique_id();
my $middle_name = 'Ulysses';
# Perl will treat a string with 0xF6 as not UTF8 unless we force it to
# "upgrade" the string to utf8.
my $dot_net = Encode::decode( 'latin-1', 'd' . chr( 0xF6 ) . 't net' );
$user->update_store(
    # Tests handling of utf8 in export/import
    first_name => $singapore,
    last_name  => $dot_net,
    # Ensure "middle_name" is preserved
    middle_name => $middle_name,
    # Used to test that password survives export/import
    password   => 'something or other',
    # Private Ids need to be preserved across export/import too
    private_external_id => $external_id,
);

my $page = $hub->pages->new_from_name('Admin Wiki');
$page->edit_rev;
$page->update(
    content          => 'This is new front page content.',
    revision         => $page->revision_num,
    subject          => 'Admin Wiki',
    user             => $user,
);

my $tarball = $admin->export_to_tarball(dir => $test_dir);

$admin->delete();

# Deleting the user is important so that we know that both user and
# workspace data is restored
Test::Socialtext::User->delete_recklessly($user);

Socialtext::Workspace->ImportFromTarball( tarball => $tarball );

# The actual tests start here ...
{
    # If this works at all we can know that the restore did something
    my $hub = new_hub('admin');
    my $admin = $hub->current_workspace;

    is( $admin->logo_uri(), 'http://example.com/logo.gif',
        'check that logo_uri survived export/import' );

    ok( $admin->user_count, 'admin workspace has users' );

    my $user = Socialtext::User->new( username => 'devnull1@socialtext.com' );
    ok( $admin->has_user( $user ), 'devnull1@socialtext.com is in admin workspace' );

    is( $user->first_name(), $singapore, 'user first name is Singapore (in Chinese)' );
    is( $user->middle_name(), $middle_name, 'user middle name is preserved' );
    is( $user->last_name(), $dot_net, 'user last name is dot net (umlauts on o)' );
    is $user->private_external_id, $external_id, 'private/external id preserved';
    ok( $user->password_is_correct('something or other'), 'password survived import' );

    ok( Socialtext::EmailAlias::find_alias('admin'), 'email alias exists for admin workspace' );

    ok( $admin->permissions->role_can(
            role       => Socialtext::Role->Guest(),
            permission => Socialtext::Permission->new( name => 'read' ) ),
        'guest can read workspace' );

    ok( ! $admin->permissions->role_can(
            role       => Socialtext::Role->Guest(),
            permission => Socialtext::Permission->new( name => 'edit' ) ),
        'guest cannot edit workspace' );

    my $page = $hub->pages->new_from_name('Admin Wiki');
    ok( $page->exists(), 'Admin Wiki page exists' );
    like( $page->content(), qr/new front page content/, 'Admin Wiki page content has expected text' );

    $page = $hub->pages()->new_from_name('Start Here');
    ok( $page->exists(), 'Start Here page exists' );
    like( $page->content(), qr/organize information/, 'Start Here page content has expected text' );

    eval { Socialtext::Workspace->ImportFromTarball( tarball => $tarball ) };
    like( $@, qr/cannot restore/i, 'cannot restore over an existing workspace' );

    eval { Socialtext::Workspace->ImportFromTarball( tarball => $tarball, overwrite => 1 ) };
    is( $@, '', 'can force an overwrite when restoring' );
}
