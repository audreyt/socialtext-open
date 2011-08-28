#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

# Need this line before Test::Mock::LWP loads; otherwise WWW::Mechanize
# will complain HTTP::Request's mocked version is not new enough.
use WWW::Mechanize ();

use Test::More;
use Test::Socialtext::Fatal;
use Socialtext::WikiFixture::TestUtils;
use Data::Dumper;
use mocked 'Socialtext::User';

BEGIN {
    my $test_it = $ENV{ST_RUN_WIKIFIXTURE_TESTS};
    unless ( $test_it ) {
        plan tests => 1;
        # These tests are somewhat fragile, and can be broken by
        # enhancements to the Selenium fixture.  So lets keep them
        # from bothering Socialtext developers, but keep them around
        # for when we need to hack the fixture.
    }
    else {
        plan tests => 330;
    }
    use_ok 'Socialtext::WikiObject::TestPlan';
    exit unless $test_it;
}


# avoid calling ok(0) for an intentionally failing test
local $ENV{ST_WF_TEST} = 1;

# Add to t/bin to the path for our fake st-* commands                           
$ENV{PATH} = "t/bin:$ENV{PATH}"; 
ok -x 't/bin/st-admin';
ok -x 't/bin/st-config';

st_fixture_ok(
    plan => <<EOT,
| st-page-title | monkey |
EOT
    tests => [
        [ 'text_like' => ['id=st-list-title', qr/\Qmonkey\E/]],
    ],
);

st_fixture_ok(
    name => 'Socialtext fixture tests',
    plan => <<EOT,
| st-logoutin |
EOT
    tests => [
        [ 'click_ok' => ['id=logout_btn', 'log out']],
        [ 'wait_for_page_to_load_ok' => 10000],
        [ 'open_ok', '/challenge?%2Ffoo%2Findex.cgi' ],
        [ 'type_ok', ['username' => 'testuser']],
        [ 'type_ok', ['password' => 'password']],
        [ 'click_ok', [q{id=login_btn}, 'log in']],
        [ 'wait_for_page_to_load_ok' => 10000],
    ],
);

st_fixture_ok(
    name => 'Turn off watching, page already not watched',
    plan => <<EOT,
| st-watch-page | 0 | # comment |
EOT
    sel_setup => [
        [ 'get_attribute' => 'foo/watch-off.gif'],
    ],
    tests => [
        [ 'get_attribute' => q{//img[@id='st-watchlist-indicator']/@src} ]
    ],
);

st_fixture_ok(
    name => 'Turn on watching, page already watched',
    plan => <<EOT,
| st-watch-page | 1 |
EOT
    sel_setup => [
        [ 'get_attribute' => 'foo/watch-on.gif'],
    ],
    tests => [
        [ 'get_attribute' => q{//img[@id='st-watchlist-indicator']/@src} ]
    ],
);

st_fixture_ok(
    name => 'Turn on watching, page not watched',
    plan => <<EOT,
| st-watch-page | 1 |
EOT
    sel_setup => [
        [ 'get_attribute' => 'foo/watch-off.gif'],
        [ 'get_attribute' => 'foo/watch-off.gif'],
        [ 'get_attribute' => 'foo/watch-on.gif'],
    ],
    tests => [
        [ 'get_attribute' => q{//img[@id='st-watchlist-indicator']/@src} ],
        [ 'click_ok' => [q{//img[@id='st-watchlist-indicator']}, 
                         'clicking watch button'] ],
        [ 'get_attribute' => q{//img[@id='st-watchlist-indicator']/@src} ],
        [ 'get_attribute' => q{//img[@id='st-watchlist-indicator']/@src} ],
    ],
);

st_fixture_ok(
    name => 'Watchlist page: Turn on watching, page not watched',
    plan => <<EOT,
| st-watch-page | 1 | jabber |
EOT
    sel_setup => [
        [ 'get_attribute' => 'monkey'],
        [ 'get_attribute' => 'jabber'],
        [ 'get_attribute' => 'foo/watch-off.gif'],
        [ 'get_attribute' => 'foo/watch-off.gif'],
        [ 'get_attribute' => 'foo/watch-on.gif'],
    ],
    tests => [
        [ 'get_attribute' => 
          q{//div[@id='st-watchlist-content']/div[2]/div[2]/img/@alt} ],
        [ 'get_attribute' => 
          q{//div[@id='st-watchlist-content']/div[3]/div[2]/img/@alt} ],
        [ 'click_ok' => 
          [ q{//div[@id='st-watchlist-content']/div[3]/div[2]/img},
            'clicking watch button'] ],
        [ 'get_attribute' => 
          q{//div[@id='st-watchlist-content']/div[3]/div[2]/img/@src}],
        [ 'get_attribute' => 
          q{//div[@id='st-watchlist-content']/div[3]/div[2]/img/@src}],
        [ 'get_attribute' => 
          q{//div[@id='st-watchlist-content']/div[3]/div[2]/img/@src}],
    ],
);

st_fixture_ok(
    name => 'Watchlist page: Turn off watching, page watched',
    plan => <<EOT,
| st-watch-page | 0 | jabber |
EOT
    sel_setup => [
        [ 'get_attribute' => 'jabber'],
        [ 'get_attribute' => 'foo/watch-on.gif'],
        [ 'get_attribute' => 'foo/watch-off.gif'],
    ],
    tests => [
        [ 'get_attribute' => 
          q{//div[@id='st-watchlist-content']/div[2]/div[2]/img/@alt} ],
        [ 'click_ok' => 
          [ q{//div[@id='st-watchlist-content']/div[2]/div[2]/img},
            'clicking watch button'] ],
        [ 'get_attribute' => 
          q{//div[@id='st-watchlist-content']/div[2]/div[2]/img/@src}],
        [ 'get_attribute' => 
          q{//div[@id='st-watchlist-content']/div[2]/div[2]/img/@src}],
    ],
);

st_fixture_ok(
    name => 'Turn off watching, page watched',
    plan => <<EOT,
| st-watch-page | 0 |
EOT
    sel_setup => [
        [ 'get_attribute' => 'foo/watch-on.gif'],
        [ 'get_attribute' => 'foo/watch-off.gif'],
    ],
    tests => [
        [ 'get_attribute' => q{//img[@id='st-watchlist-indicator']/@src} ],
        [ 'click_ok' => [q{//img[@id='st-watchlist-indicator']}, 
                         'clicking watch button'] ],
        [ 'get_attribute' => q{//img[@id='st-watchlist-indicator']/@src} ],
    ],
);

st_fixture_ok(
    name => 'No matching row',
    plan => <<EOT,
| st-watch-page | 0 | foo |
EOT
    sel_setup => [
        [ 'get_attribute' => 'jabber'],
        [ 'get_attribute' => undef ],
    ],
    tests => [
        [ 'get_attribute' => 
          q{//div[@id='st-watchlist-content']/div[2]/div[2]/img/@alt} ],
        [ 'get_attribute' => 
          q{//div[@id='st-watchlist-content']/div[3]/div[2]/img/@alt} ],
    ],
);

st_fixture_ok(
    name => 'Check a page IS watched',
    plan => <<EOT,
| st-is-watched | 1 |
EOT
    sel_setup => [
        [ 'get_attribute' => 'foo/watch-on.gif'],
    ],
    tests => [
        [ 'get_attribute' => q{//img[@id='st-watchlist-indicator']/@src} ],
    ],
);

st_fixture_ok(
    name => 'Check a page is NOT watched',
    plan => <<EOT,
| st-is-watched | 0 |
EOT
    sel_setup => [
        [ 'get_attribute' => 'foo/watch-off.gif'],
    ],
    tests => [
        [ 'get_attribute' => q{//img[@id='st-watchlist-indicator']/@src} ],
    ],
);

st_fixture_ok(
    name => 'Search',
    plan => <<EOT,
| st-search | foo | bar |
EOT
    tests => [
        [ 'type_ok' => [ q{st-search-term}, 'foo' ] ],
        [ 'click_ok' => 'link=Search' ],
        [ 'wait_for_page_to_load_ok' => 10000 ],
        [ 'text_like' => ['id=st-list-title', qr/\Qbar\E/] ],
    ],
);

st_fixture_ok(
    name => 'Search results',
    plan => <<EOT,
| st-result | foo |
EOT
    tests => [
        [ 'text_like' => ['id=st-search-content', qr/\Qfoo\E/] ],
    ],
);

st_fixture_ok(
    name => 'Search results',
    plan => <<EOT,
| st-result | foo |
EOT
    tests => [
        [ 'text_like' => ['id=st-search-content', qr/\Qfoo\E/] ],
    ],
);

st_fixture_ok(
    name => 'st_should_be_admin on',
    plan => <<EOT,
| st-should-be-admin | foo | 1 |
EOT
    sel_setup => [
        [ 'get_text' => 'bar' ],
        [ 'get_text' => 'foo' ],
    ],
    tests => [
        [ 'get_text' => '//tbody/tr[2]/td[2]' ],
        [ 'get_text' => '//tbody/tr[3]/td[2]' ],
        [ 'check_ok' => '//tbody/tr[3]/td[3]/input' ],
        [ 'click_ok' => 'Button' ],
        [ 'wait_for_page_to_load_ok' => 10000 ],
        [ 'text_like' => ['st-settings-section', qr/\QChanges Saved\E/ ]],
    ],
);

st_fixture_ok(
    name => 'st_should_be_admin off',
    plan => <<EOT,
| st-should-be-admin | foo | 0 |
EOT
    sel_setup => [
        [ 'get_text' => 'foo' ],
        [ 'get_text' => 'bar' ],
    ],
    tests => [
        [ 'get_text' => '//tbody/tr[2]/td[2]'],
        [ 'uncheck_ok' => '//tbody/tr[2]/td[3]/input'],
        [ 'click_ok' => 'Button' ],
        [ 'wait_for_page_to_load_ok' => 10000 ],
        [ 'text_like' => ['st-settings-section', qr/\QChanges Saved\E/ ]],
    ],
);

Missing_args: {
    my %args = ( selenium => Test::WWW::Selenium->new );
    like exception { Socialtext::WikiFixture::Socialtext->new(%args) },
              qr/workspace is mandatory/;
    $args{workspace} = 1;
    like exception { Socialtext::WikiFixture::Socialtext->new(%args) },
              qr/username is mandatory/;
    $args{username} = 1;
    like exception { Socialtext::WikiFixture::Socialtext->new(%args) },
              qr/password is mandatory/;
}

st_fixture_ok(
    name => 'st_login with custom args',
    plan => <<EOT,
| st-login | foo | bar |
EOT
    tests => [
        [ open_ok => '/challenge?%2Ffoo%2Findex.cgi' ],
        [ type_ok => ['username', 'foo']],
        [ type_ok => ['password', 'bar']],
        [ click_ok => [q{id=login_btn}, 'log in']],
        [ wait_for_page_to_load_ok => 10000],
    ],
);

st_fixture_ok(
    name => 'st_submit',
    plan => <<EOT,
| st-submit | | |
EOT
    tests => [
        [ click_ok => [q{//input[@value='Submit']}, 'click submit button']],
        [ wait_for_page_to_load_ok => 10000],
    ],
);

st_fixture_ok(
    name => 'st_message',
    plan => <<EOT,
| st-message | foo | |
EOT
    tests => [
        [ text_like => ['errors-and-messages', qr/\Qfoo\E/]],
    ],
);

Watched_page_timeout: {
    no warnings qw/redefine once/;
    my @ok_args;
    local *Socialtext::WikiFixture::Socialtext::ok = sub { @ok_args = @_ };

    st_fixture_ok(
        name => 'Turn off watching, page watched',
        fixture_args => { 
            selenium_timeout => 1000,
        },
        plan => <<EOT,
| st-watch-page | 0 |
EOT
        sel_setup => [
            [ 'get_attribute' => 'foo/watch-on.gif'],
            [ 'get_attribute' => 'foo/watch-on.gif'],
            [ 'get_attribute' => 'foo/watch-on.gif'],
            [ 'get_attribute' => 'foo/watch-on.gif'],
            [ 'get_attribute' => 'foo/watch-on.gif'],
            [ 'get_attribute' => 'foo/watch-on.gif'],
            [ 'get_attribute' => 'foo/watch-on.gif'],
            [ 'get_attribute' => 'foo/watch-on.gif'],
            [ 'get_attribute' => 'foo/watch-on.gif'],
        ],
        tests => [
            [ 'get_attribute' => q{//img[@id='st-watchlist-indicator']/@src} ],
            [ 'click_ok' => [q{//img[@id='st-watchlist-indicator']}, 
                             'clicking watch button'] ],
            [ 'get_attribute' => q{//img[@id='st-watchlist-indicator']/@src} ],
            [ 'get_attribute' => q{//img[@id='st-watchlist-indicator']/@src} ],
            [ 'get_attribute' => q{//img[@id='st-watchlist-indicator']/@src} ],
        ],
        extra_calls_ok => 1,
    );
    is $ok_args[0], 0;
    is $ok_args[1], q/Timeout waiting for watchlist icon to change/;
}

ST_admin: {
    no warnings qw/redefine once/;
    my @like_args;
    local *Socialtext::WikiFixture::Socialtext::like = sub { @like_args = @_ };
    my $diag_text = '';
    local *Socialtext::WikiFixture::Socialtext::diag = sub { 
        $diag_text .= shift;
    };

    Regular: {
        st_fixture_ok(
            name => 'regular st-admin',
            plan => <<EOT,
| st-admin | foo | qr/foo/ |
EOT
        );
        like $like_args[0], qr/foo/;
        is $like_args[1], qr/foo/s;
    }

    Regular_without_match: {
        $diag_text = '';
        @like_args = ();
        st_fixture_ok(
            name => 'regular st-admin without match',
            plan => <<EOT,
| st-admin | foo |  |
EOT
        );
        is scalar(@like_args), 0, 'no test done';
    }

    my $workspace = 'invalid';
    my $tarball = "/tmp/$workspace.1.tar.gz";
    Export_workspace_no_existing_old_tarball: {
        $diag_text = '';
        unlink $tarball;
        st_fixture_ok(
            name => 'export non-existing st-admin',
            plan => <<EOT,
| st-admin | --export-workspace --workspace $workspace | export-workspace |
EOT
        );
        like $diag_text, qr/st-login:/;
    }

    Export_workspace_existing_old_tarball: {
        $diag_text = '';
        system("date > $tarball");
        st_fixture_ok(
            name => 'export existing st-admin',
            plan => <<EOT,
| st-admin | --export-workspace --workspace $workspace | export-workspace |
EOT
        );
        like $diag_text, qr/Deleting \Q$tarball\E/;
    }
}

ST_config: {
    no warnings qw/redefine once/;
    my @like_args;
    local *Socialtext::WikiFixture::Socialtext::like = sub { @like_args = @_ };
    my $diag_text = '';
    local *Socialtext::WikiFixture::Socialtext::diag = sub { 
        $diag_text = shift;
    };

    Regular: {
        st_fixture_ok(
            name => 'regular st-config',
            plan => <<EOT,
| st-config | foo | qr/foo/ |
EOT
        );
        like $like_args[0], qr/foo/;
        is $like_args[1], qr/foo/s;
    }

    Regular_without_match: {
        @like_args = ();
        st_fixture_ok(
            name => 'regular st-config without match',
            plan => <<EOT,
| st-config | foo |  |
EOT
        );
        is scalar(@like_args), 0, 'no test done';
    }
}

Export_workspace: {
    no warnings qw/redefine once/;
    my @ok_args;
    local *Socialtext::WikiFixture::Socialtext::ok = sub { @ok_args = @_ };

    Default_workspace: {
        my $tarball = "/tmp/foo.1.tar.gz";
        unlink $tarball;
        st_fixture_ok(
            name => 'export_workspace_ok',
            plan => <<EOT,
| st-admin-export-workspace-ok | | |
EOT
        );
        is $ok_args[0], undef;
        is $ok_args[1], "$tarball exists", 'ok message';
    }

    Specific_workspace: {
        my $tarball = "/tmp/bar.1.tar.gz";
        unlink $tarball;
        st_fixture_ok(
            name => 'export_workspace_ok',
            plan => <<EOT,
| st-admin-export-workspace-ok | bar | |
EOT
        );
        is $ok_args[0], undef;
        is $ok_args[1], "$tarball exists", 'ok message';
    }

}

ST_command_lines: {
    no warnings qw/redefine once/;
    my @like_args;
    local *Socialtext::WikiFixture::Socialtext::like = sub { @like_args = @_ };
    my $diag_text = '';
    local *Socialtext::WikiFixture::Socialtext::diag = sub { 
        $diag_text = shift;
    };

    Regular_import: {
        st_fixture_ok(
            name => 'regular st-admin import-workspace',
            plan => <<EOT,
| st-admin | import-workspace foo | qr/foo/ |
EOT
        );
        like $like_args[0], qr/foo/;
        is $like_args[1], qr/foo/s;
    }

    Regular_import_no_arg: {
        st_fixture_ok(
            name => 'regular stdmin import-workspace',
            plan => <<EOT,
| st-admin | import-workspace | qr/import/ |
EOT
        );
        like $like_args[0], qr/import/;
        is $like_args[1], qr/import/s;
    }

    Force_confirmation: {
        st_fixture_ok(
            name => 'force confirmation',
            plan => <<EOT,
| st-force-confirmation | user | password |
EOT
        );
        like $like_args[0], qr/--email user --password password/;
    }

    Open_confirmation_uri: {
        st_fixture_ok(
            name => 'open confirmation uri',
            plan => <<EOT,
| st-open-confirmation-uri | user | password |
EOT
            tests => [
                [open_ok => '/nlw/submit/confirm/foo'],
            ],
        );
    }
}

ST_should_be_admin: {
    st_fixture_ok(
        name => 'Should be admin no',
        plan => <<EOT,
| st-should-be-admin | monkey | 0 |
EOT
        sel_setup => [
            [ 'get_text' => 'bar' ],
            [ 'get_text' => 'monkey' ],
        ],
        tests => [
            [ get_text => '//tbody/tr[2]/td[2]' ],
            [ get_text => '//tbody/tr[3]/td[2]' ],
            [ uncheck_ok => '//tbody/tr[3]/td[3]/input' ],
            [ click_ok => 'Button' ],
            [ wait_for_page_to_load_ok => 10000 ],
            [ text_like => ['st-settings-section', qr/\QChanges Saved\E/]],
        ],
    );

    st_fixture_ok(
        name => 'Should be admin yes',
        plan => <<EOT,
| st-should-be-admin | monkey | 1 |
EOT
        sel_setup => [
            [ 'get_text' => 'monkey' ],
        ],
        tests => [
            [ get_text => '//tbody/tr[2]/td[2]' ],
            [ check_ok => '//tbody/tr[2]/td[3]/input' ],
            [ click_ok => 'Button' ],
            [ wait_for_page_to_load_ok => 10000 ],
            [ text_like => ['st-settings-section', qr/\QChanges Saved\E/]],
        ],
    );

    no warnings qw/redefine once/;
    my @ok_args;
    local *Socialtext::WikiFixture::Socialtext::ok = sub { @ok_args = @_ };
    st_fixture_ok(
        name => 'Should be admin - not there',
        plan => <<EOT,
| st-should-be-admin | monkey | 1 |
EOT
        sel_setup => [
            [ 'get_text' => 'foo' ],
            [ 'get_text' => '' ],
        ],
        tests => [
            [ get_text => '//tbody/tr[2]/td[2]' ],
            [ get_text => '//tbody/tr[3]/td[2]' ],
        ],
    );
    is $ok_args[0], 0;
    is $ok_args[1], "Could not find 'monkey' in the table";
}

ST_click_reset_password: {
    no warnings qw/redefine once/;
    my @ok_args;
    local *Socialtext::WikiFixture::Socialtext::ok = sub { @ok_args = @_ };
    st_fixture_ok(
        name => 'reset password ok',
        plan => <<EOT,
| st-click-reset-password | monkey | |
EOT
        sel_setup => [
            [ 'get_text' => 'monkey' ],
            [ is_checked => 0 ],
        ],
        tests => [
            [ get_text => '//tbody/tr[2]/td[2]' ],
            [ check_ok => '//tbody/tr[2]/td[4]/input' ],
            [ click_ok => 'Button' ],
            [ wait_for_page_to_load_ok => 10000 ],
            [ text_like => ['st-settings-section', qr/\QChanges Saved\E/]],
            [ is_checked => '//tbody/tr[2]/td[4]/input' ],
        ],
    );
    is $ok_args[0], 1;
    is $ok_args[1], 'reset password checkbox not checked';
}




sub st_fixture_ok {
    my %args = @_;
    (my $name = $args{plan}) =~ s/\n.+//sm;
    my $timeout = $args{fixture_args}{selenium_timeout} || 10000;

    my $tests = $args{tests};
    unshift @$tests, 
      [ open_ok => '/challenge?%2Ffoo%2Findex.cgi' ],
      [ type_ok => ['username', 'testuser']],
      [ type_ok => ['password', 'password']],
      [ click_ok => [q{id=login_btn}, 'log in']],
      [ wait_for_page_to_load_ok => $timeout];

    Socialtext::WikiFixture::TestUtils::fixture_ok(
        name => $name,
        default_fixture => 'Socialtext',
        tests => $tests,
        %args,
    );
}
