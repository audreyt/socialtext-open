#!perl -w
# @COPYRIGHT@
use strict;
use warnings;
use File::Path qw/mkpath/;
use Socialtext::File qw/set_contents/;
use File::chdir;
use Socialtext::File;
use YAML;
use FindBin;

use mocked 'Socialtext::Hub';

BEGIN {
    use Test::Socialtext tests => 23;
    use_ok( 'Socialtext::Skin' );
    $Socialtext::Skin::CODE_BASE = 't/share';
    $Socialtext::Skin::PROD_VER = '1.0';
}

my $test_root = Test::Socialtext::Environment->instance->root_dir;

# Cascading S3 Skin
{
    my $hub = Socialtext::Hub->new;
    $hub->current_workspace->skin_name('cascades_s3');
    my $info = $hub->skin->css_info;

    is_deeply($info->{standard}, [
        "/static/1.0/skin/s3/css/bubble.css",
        "/static/1.0/skin/s3/css/screen.css",
        "/static/1.0/skin/s3/css/screen.ie.css",
        "/static/1.0/skin/s3/css/screen.ie6.css",
        "/static/1.0/skin/s3/css/screen.ie7.css",
        "/static/1.0/skin/s3/css/print.css",
        "/static/1.0/skin/s3/css/print.ie.css",
        "/static/1.0/skin/cascades_s3/css/screen.css",
        "/static/1.0/skin/cascades_s3/css/screen.ie.css",
        "/static/1.0/skin/cascades_s3/css/print.css",
        "/static/1.0/skin/cascades_s3/css/print.ie.css",
    ], 'Custom s3 CSS is correct');

    ok(!$info->{common}, "Custom s3 skin does not have common.css");

    is_deeply($hub->skin->template_paths, [
        "t/share/skin/s2/template",
        "$test_root/cache/user_frame",
        "t/share/skin/s3/template",
        "t/share/skin/cascades_s3/template",
    ], 'Custom s3 skin has both template dirs');
}

# Cascading S2 skin
{
    my $hub = Socialtext::Hub->new;
    $hub->current_workspace->skin_name('cascades_s2');
    my $info = $hub->skin->css_info;

    is_deeply($info->{standard}, [
        "/static/1.0/skin/s2/css/screen.css",
        "/static/1.0/skin/s2/css/screen.ie.css",
        "/static/1.0/skin/s2/css/print.css",
        "/static/1.0/skin/s2/css/print.ie.css",
        "/static/1.0/skin/cascades_s2/css/screen.css",
        "/static/1.0/skin/cascades_s2/css/screen.ie.css",
        "/static/1.0/skin/cascades_s2/css/print.css",
        "/static/1.0/skin/cascades_s2/css/print.ie.css",
    ], 'Cascading skin containers s2 css');

    is_deeply($info->{common}, [
        "/static/1.0/skin/common/css/common.css",
    ], 'Cascading skin has common.css');

    is_deeply($hub->skin->template_paths, [
        "t/share/skin/s2/template",
        "$test_root/cache/user_frame",
        "t/share/skin/cascades_s2/template",
    ], 'Cascading skin has both template dirs');
}

# Non-cascading skin
{
    my $hub = Socialtext::Hub->new;
    $hub->current_workspace->skin_name('nocascade');
    my $info = $hub->skin->css_info;

    is_deeply($info->{standard}, [
        "/static/1.0/skin/nocascade/css/screen.css",
        "/static/1.0/skin/nocascade/css/screen.ie.css",
        "/static/1.0/skin/nocascade/css/print.css",
        "/static/1.0/skin/nocascade/css/print.ie.css",
    ], 'Non cascading does not include the s2 skin');

    is_deeply($info->{common}, [
        "/static/1.0/skin/common/css/common.css",
    ], 'Non cascading skin has common.css');

    is_deeply($hub->skin->template_paths, [
        "t/share/skin/s2/template",
        "$test_root/cache/user_frame",
        "t/share/skin/nocascade/template",
    ], 'Non cascading skin has both template dirs');
}

# S3 skin
{
    my $hub = Socialtext::Hub->new;
    $hub->current_workspace->skin_name('s3');
    my $info = $hub->skin->css_info;

    is_deeply($info->{standard}, [
        "/static/1.0/skin/s3/css/bubble.css",
        "/static/1.0/skin/s3/css/screen.css",
        "/static/1.0/skin/s3/css/screen.ie.css",
        "/static/1.0/skin/s3/css/screen.ie6.css",
        "/static/1.0/skin/s3/css/screen.ie7.css",
        "/static/1.0/skin/s3/css/print.css",
        "/static/1.0/skin/s3/css/print.ie.css",
    ], 'S3 skin does not include the s2 skin');

    ok(!$info->{common}, "S3 skin does not have common.css");

    is_deeply($hub->skin->template_paths, [
        "t/share/skin/s2/template",
        "$test_root/cache/user_frame",
        "t/share/skin/s3/template",
    ], 'S3 skin has both template dirs');
}

# Uploaded S2 skin
my $info_file = 't/share/uploaded-skin/admin/info.yaml';
{
    my $hub = Socialtext::Hub->new;
    $hub->{current_workspace} =
        Socialtext::Workspace->new(name => 'admin');
    $hub->current_workspace->skin_name('s2');
    $hub->current_workspace->uploaded_skin('1');

    YAML::DumpFile($info_file => {
        name => 'uploaded',
        cascade_css => 1,
    });

    my $info = $hub->skin->css_info;

    is_deeply($info->{standard}, [
        "/static/1.0/skin/s2/css/screen.css",
        "/static/1.0/skin/s2/css/screen.ie.css",
        "/static/1.0/skin/s2/css/print.css",
        "/static/1.0/skin/s2/css/print.ie.css",
        "/static/1.0/uploaded-skin/admin/css/screen.css",
    ], 'Uploaded skin css is included');

    is_deeply($hub->skin->template_paths, [
        "t/share/skin/s2/template",
        "$test_root/cache/user_frame",
        "t/share/uploaded-skin/admin/template",
    ], 'Uploaded templates are included in template_paths');
}

# Uploaded S3 skin
{
    my $hub = Socialtext::Hub->new;
    $hub->{current_workspace} =
        Socialtext::Workspace->new(name => 'admin');
    $hub->current_workspace->skin_name('s2');
    $hub->current_workspace->uploaded_skin('1');

    YAML::DumpFile($info_file => {
        parent => 's3',
        name => 'uploaded',
        cascade_css => 1,
    });

    my $info = $hub->skin->css_info;

    is_deeply($info->{standard}, [
        "/static/1.0/skin/s3/css/bubble.css",
        "/static/1.0/skin/s3/css/screen.css",
        "/static/1.0/skin/s3/css/screen.ie.css",
        "/static/1.0/skin/s3/css/screen.ie6.css",
        "/static/1.0/skin/s3/css/screen.ie7.css",
        "/static/1.0/skin/s3/css/print.css",
        "/static/1.0/skin/s3/css/print.ie.css",
        "/static/1.0/uploaded-skin/admin/css/screen.css",
    ], 'Uploaded skin css is included');

    is_deeply($hub->skin->template_paths, [
        "t/share/skin/s2/template",
        "$test_root/cache/user_frame",
        "t/share/skin/s3/template",
        "t/share/uploaded-skin/admin/template",
    ], 'Uploaded templates are included in template_paths');
}

# Socialtext::Skin works outside the hub
{
    my $cascades_s2 = Socialtext::Skin->new(name => 'cascades_s2');
    is $cascades_s2->skin_info->{parent}, 's2', 'cascades_s2 inherits from s2';
    is $cascades_s2->parent->skin_info->{skin_name}, 's2', 'parent is s2';
    is $cascades_s2->skin_info->{cascade_css}, 1, 'cascades_s2 cascades_s2';
    is_deeply($cascades_s2->template_paths, [
        "t/share/skin/s2/template",
        "$test_root/cache/user_frame",
        "t/share/skin/cascades_s2/template",
    ], 'Cascading skin has both template dirs');
}

# Non existent skins return undef
{
    my $skin = Socialtext::Skin->new(name => 'absent');
    isa_ok $skin, 'Socialtext::Skin', 'got the "absent" skin';
    ok !$skin->exists, "... and it doesn't actually exist";
}
