#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 18;
use Test::Socialtext::Fatal;
fixtures('workspaces', 'public');

use Socialtext::Pages;
use Socialtext::Page;
use File::Path ();
use File::Spec;
use File::Temp ();
use Storable ();
use Socialtext::Formatter::Parser;
use Digest::MD5 qw/md5_hex/;
use Encode qw/encode_utf8/;

my $cache_dir = Socialtext::AppConfig->formatter_cache_dir;
my $page_name = 'cache page';

if ( -e $cache_dir ) {
    diag("removing $cache_dir");
    File::Path::rmtree($cache_dir);
}

my $hub = new_hub('admin');
my $text = <<'EOF';
This is the page.

{link public [welcome]}

{link foobar [welcome]}
EOF
my $page = Socialtext::Page->new( hub => $hub )->create(
    title   => $page_name,
    content => $text,
    creator => $hub->current_user,
);

FIRST_PARSE: {
    check_with_user( user => 'devnull1@socialtext.com' );
}

SECOND_PARSE_USES_CACHE: {
    # the cache is only used if its last mod time is _greater_ than the
    # page file (not if they're the same)
    my $text_md5 = md5_hex(encode_utf8($text));
    my $cache_file = File::Spec->catfile(
        $cache_dir, $hub->current_workspace->workspace_id,
        $text_md5 . '_' . $page->id );

    my $parser = Socialtext::Formatter::Parser->new(
        table      => $hub->formatter->table,
        wafl_table => $hub->formatter->wafl_table,
    );
    my $parsed = $parser->text_to_parsed( <<'EOF' );
Coming from the cache.

{link public [welcome]}

{link foobar [welcome]}
EOF
    Storable::nstore( $parsed, $cache_file );

    my $future = time + 5;
    utime $future, $future, $cache_file
        or die "Cannot call utime on $cache_file: $!";
    check_with_user(
        user       => 'devnull1@socialtext.com',
        from_cache => 1,
    );

    ok( -e $cache_dir, 'cache directory exists' );
}


CACHE_DIR_UNWRITEABLE: {
    my $dir = File::Temp::tempdir( CLEANUP => 1 );

    my $cache_subdir = File::Spec->catdir( $dir,
        $hub->current_workspace()->workspace_id() );
    mkdir $cache_subdir
        or die "Cannot make $cache_subdir: $!";

    chmod 0400, $cache_subdir or die "Cannot chmod $cache_subdir to 0400: $!";

    Socialtext::AppConfig->set( formatter_cache_dir => $dir );

    like exception { check_with_user( user => 'devnull1@socialtext.com' ) },
        qr/Failed to cache using questions.*(not writable|Permission denied)/,
        'Page caching dies when dir is not writable';

    # Without this it won't get cleaned up because of the chmod
    END { chmod 0700, $cache_subdir }
    chmod 0700, $cache_subdir;
}

user_updates_invalidate_cache: {
    my $user = create_test_user(
        first_name  => 'Bubba',
        middle_name => 'Bo Bob',
        last_name   => 'Brain',
    );
    my $email   = $user->email_address;

    my $ws_name = "workspace_" . time;
    my $hub     = new_hub($ws_name, $user->username);

    my $title   = 'user_updates_invalidate_cache';
    my $page    = Socialtext::Page->new(hub => $hub)->create(
        title   => $title,
        content => "This page has a {user: $email} wafl in it",
        creator => $user,
    );
    $hub->pages->current($page);

    my $before      = $hub->pages->new_from_name($title)->to_html_or_default;
    my $before_name = $user->display_name;
    like $before, qr/$before_name/, 'Page renders with Display Name';
    is $before_name, 'Bubba Bo Bob Brain', '... based on first/middle/last';

    # Change User's "first_name"; should invalidate page cache
    first_name_invalidates_cache: {
        # sleep a tiny bit so the "page render" and "update the user" don't
        # happen within the same second.
        sleep 2;

        $user->update_store(
            first_name => 'Jane',
        );
        my $after_name = $user->display_name;
        is $after_name, 'Jane Bo Bob Brain',
            'Updating first name triggers display_name recalculation';

        my $after = $hub->pages->new_from_name($title)->to_html_or_default;
        isnt $after, $before, 'Page contents change when User data changes';
        like $after, qr/$after_name/, '... with new Display Name for User';
    }

    # Change User's "middle_name"; should invalidate page cache
    middle_name_invalidates_cache: {
        # sleep a tiny bit so the "page render" and "update the user" don't
        # happen within the same second.
        sleep 2;

        $user->update_store(
            middle_name => 'Penelope',
        );
        my $after_name = $user->display_name;
        is $after_name, 'Jane Penelope Brain',
            'Updating middle name triggers display_name recalculation';

        my $after = $hub->pages->new_from_name($title)->to_html_or_default;
        isnt $after, $before, 'Page contents change when User data changes';
        like $after, qr/$after_name/, '... with new Display Name for User';
    }

    # Change User's "last_name"; should invalidate page cache
    last_name_invalidates_cache: {
        # sleep a tiny bit so the "page render" and "update the user" don't
        # happen within the same second.
        sleep 2;

        $user->update_store(
            last_name => 'Smith',
        );
        my $after_name = $user->display_name;
        is $after_name, 'Jane Penelope Smith',
            'Updating last name triggers display_name recalculation';

        my $after = $hub->pages->new_from_name($title)->to_html_or_default;
        isnt $after, $before, 'Page contents change when User data changes';
        like $after, qr/$after_name/, '... with new Display Name for User';
    }
}

sub check_with_user {
    my %p = @_;

    my $hub = new_hub('admin');
    my $user = Socialtext::User->new( username => $p{user} );
    $hub->current_user($user);
    my $output = $hub->pages->new_from_name($page_name)->to_html_or_default;

    if ( $p{should_fail} ) {
        unlike(
            $output,
            qr{\Qhref="/foobar/welcome"},
            'foobar link not present'
        );
        like(
            $output,
            qr{wafl_permission_error},
            'permission error'
        );
    }
    else {
        like(
            $output,
            qr{a brand new page},
            'new content present'
        )
            if $p{new_page_content};
        like(
            $output,
            qr{Coming from the cache},
            'content is from the cache'
        )
            if $p{from_cache};
        like(
            $output,
            qr{\Qhref="/public/welcome"},
            'public link present'
        );
        like(
            $output,
            qr{\Qhref="/foobar/welcome"},
            'foobar link present'
        );
    }
}
