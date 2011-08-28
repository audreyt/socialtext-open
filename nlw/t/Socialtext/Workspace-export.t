#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 46;
fixtures(qw( db ));

use File::Basename ();
use File::Temp ();
use YAML ();
use Socialtext::Account;
use Socialtext::AppConfig;
use IO::File;

use ok 'Socialtext::Workspace::Exporter';

my $hub  = create_test_hub();
my $ws   = $hub->current_workspace;
$ws->title("My Awesome Workspace $^T"); # hack to avoid reindexing
$ws->update(title => $ws->title);
my $ws_name = $ws->name;
my $user = $hub->current_user;
my $test_dir = Socialtext::AppConfig->test_dir();

my $private_id  = Test::Socialtext->create_unique_id();
my $middle_name = 'Ulysses';
$user->update_store(
    middle_name         => $middle_name,
    private_external_id => $private_id,
);
my $test_att_id;

setup: {
    my $page = $hub->pages->new_from_name("A Page $^T");
    $page->content('blah');
    $page->store;

    my $fh = IO::File->new("t/attachments/revolts.doc", "<");
    my $attachment = $hub->attachments->create(
        page => $page,
        fh => $fh,
        filename => "../../../revolts.doc", # with slashies that should strip
        embed => 1,
    );
    isa_ok $attachment, 'Socialtext::Attachment';
    is $attachment->filename, "revolts.doc", "attached revolts.doc";
    $test_att_id = $attachment->id;

    $page->rev->clear_body_ref;
    ok $page->content =~ /{file: revolts.doc}/, "got inlined";
}

Export_includes_meta_info: {
   my $wx = new_exporter();
   $wx->export_meta();

   my $meta_file = "$test_dir/meta.yaml";
   ok(-f $meta_file, 'meta.yaml file exists');

   my $yaml = YAML::LoadFile( $meta_file );
   is $yaml->{has_lock}, 1, 'has locks is in the yaml file.';
}

Export_includes_logo_and_info: {
    my $image ='t/attachments/socialtext-logo-30.gif';
    $ws->set_logo_from_file(filename => $image);
    my $wx = new_exporter();
    $wx->export_info();

    my $ws_file = "$test_dir/$ws_name-info.yaml";
    ok( -f $ws_file, 'workspace data yaml dump exists' );

    my $ws_dump = YAML::LoadFile($ws_file);
    is( $ws_dump->{account_name}, 
        Socialtext::Account->Default->name,
        'account_name is Socialtext in workspace dump' );
    is( $ws_dump->{creator_username}, $user->username,
        'check creator name in workspace dump' );

    is $ws_dump->{title}, "My Awesome Workspace $^T";
    ok !exists($ws_dump->{user_set_id}), "no user_set_id";
    ok !exists($ws_dump->{workspace_id}), "no user_set_id";

    my $logo = File::Basename::basename($ws->logo_filename);
    is( $ws_dump->{logo_filename}, $logo,
        'check logo filename' );
    ok -f "$test_dir/$logo", "logo is saved";
}

Export_users_dumped: {
    my $wx = new_exporter();
    $wx->export_users();

    my $users_file = "$test_dir/$ws_name-users.yaml";
    ok( -f $users_file, 'users data yaml dump exists' );

    my $users_dump = YAML::LoadFile($users_file);
    is( $users_dump->[0]{email_address}, $user->email_address,
        'check email address for first user in user dump' );
    is( $users_dump->[0]{creator_username}, 'system-user',
        'check creator name for first user in user dump' );
    is $users_dump->[0]{middle_name}, $middle_name,
        'check middle name for first user in user dump';
    is( $users_dump->[0]{private_external_id}, $private_id,
        'check private/external id for first user in user dump' );
    if ( $users_dump->[0]{user_id} ) {
        fail( "user_id should not exist in dump file." );
    }
}

Export_permissions_dumped: {
    my $wx = new_exporter();
    $wx->export_permissions();

    my $users_file = "$test_dir/$ws_name-permissions.yaml";
    ok( -f $users_file, 'permissions data yaml dump exists' );

    my $perm_dump = YAML::LoadFile($users_file);
    my $p = $perm_dump->[0];
    ok( Socialtext::Role->new( name => $p->{role_name} ),
        "valid role name in first dumped perm ($p->{role_name})" );
    ok( Socialtext::Permission->new( name => $p->{permission_name} ),
        "valid permission name in first dumped perm ($p->{permission_name})" );
}

Export_tarball_format: {
    my $dir = File::Temp->newdir(CLEANUP => 1);
    my $tarball = $ws->export_to_tarball(dir => $dir);
    ok( -f $tarball, 'tarball exists' );

    system( 'tar', 'xzf', $tarball, '-C', $dir )
        and die "Cannot untar $tarball: $!";

    for my $data_dir ( qw( data plugin user ) ) {
        my $d = "$dir/$data_dir/$ws_name";
        ok( -d $d, "$d is in tarball" );
    }

    ok( -f "$dir/$ws_name-info.yaml", 'workspace yaml dump file is in tarball' );
    ok( -f "$dir/$ws_name-users.yaml", 'users yaml dump file is in tarball' );
    ok( -f "$dir/$ws_name-permissions.yaml", 'permissions yaml dump file is in tarball' );
    ok( -f "$dir/meta.yaml", 'Export meta file is in tarball' );

    ok -d "$dir/data/$ws_name/a_page_$^T", "page exists";

    ok -d "$dir/plugin/$ws_name/attachments", "attachments dir exists";
    ok -d "$dir/plugin/$ws_name/attachments/a_page_$^T",
        "attachments dir for page exists";
    ok -f "$dir/plugin/$ws_name/attachments/a_page_$^T/$test_att_id.txt",
        "attachments dir for page exists";
    ok -d "$dir/plugin/$ws_name/attachments/a_page_$^T/$test_att_id",
        "attachments dir for page exists";
    ok -f "$dir/plugin/$ws_name/attachments/a_page_$^T/$test_att_id/revolts.doc",
        "attachments dir for page exists";
}

Export_to_different_name: {
    my $dir = File::Temp->newdir(CLEANUP=>1);
    my $tarball = $ws->export_to_tarball(name => 'monkey', dir => $dir);
    like $tarball, qr/monkey/, 'tarball named like a monkey';
    ok( -f $tarball, 'tarball exists' );

    system( 'tar', 'xzf', $tarball, '-C', $dir )
        and die "Cannot untar $tarball: $!";

    for my $data_dir ( qw( data plugin user ) ) {
        my $d = "$dir/$data_dir/monkey";
        ok( -d $d, "$d is in tarball" );
    }

    ok( -f "$dir/monkey-info.yaml", 'workspace yaml dump file is in tarball' );
    ok( -f "$dir/monkey-users.yaml", 'users yaml dump file is in tarball' );
    ok( -f "$dir/monkey-permissions.yaml", 'permissions yaml dump file is in tarball' );
    ok( -f "$dir/meta.yaml", 'Export meta file is in tarball' );
}

pass 'done';

sub new_exporter {
    my $dir = shift || $test_dir;
    my $name = shift || $ws->name;
    return Socialtext::Workspace::Exporter->new(
        workspace => $ws,
        name      => $name,
        tmpdir    => $test_dir,
    );
}
