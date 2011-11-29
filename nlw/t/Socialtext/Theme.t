#!/usr/bin/env perl
use strict;
use warnings;

use File::Temp qw(tempdir);
use Test::More;
use Test::Socialtext;
use Test::Differences;
use Socialtext::SQL qw(sql_execute sql_singlevalue);
use Socialtext::Theme;

fixtures('db');

my $att_id = sql_singlevalue('SELECT attachment_id FROM attachment LIMIT 1');
my $theme_id = sql_singlevalue('SELECT theme_id FROM theme LIMIT 1');
my $default = Socialtext::Theme->Default();

valid_settings: {
    my $class = 'Socialtext::Theme';

    # exercise _valid_hex_color
    ok $class->ValidSettings(header_color=>'#abcdba'), 'hex color 1';
    ok $class->ValidSettings(header_color=>'#ABCDBA'), 'hex color 1a';
    ok !$class->ValidSettings(header_color=>'#1234567'), 'hex color 2';
    ok !$class->ValidSettings(header_color=>'red'), 'hex color 3';
    ok !$class->ValidSettings(header_color=>'#qwerty'), 'hex color 4';
    ok !$class->ValidSettings(header_color=>''), 'hex color 5';
    ok $class->ValidSettings(header_color=>'#cc6600'), 'hex color 6';

    # exercise _valid_position
    ok $class->ValidSettings(header_image_position=>'left top'), 'position 1';
    ok !$class->ValidSettings(header_image_position=>'left'), 'position 2';
    ok !$class->ValidSettings(header_image_position=>'top left'), 'position 3';
    ok !$class->ValidSettings(header_image_position=>'left left'), 'position 4';
    ok !$class->ValidSettings(header_image_position=>''), 'position 5';

    # exercise _valid_tiling
    ok $class->ValidSettings(header_image_tiling=>'repeat'), 'tiling 1';
    ok $class->ValidSettings(header_image_tiling=>'no-repeat'), 'tiling 2';
    ok !$class->ValidSettings(header_image_tiling=>'both none'), 'tiling 3';
    ok !$class->ValidSettings(header_image_tiling=>'repeat no-repeat'), 'tiling 4';
    ok !$class->ValidSettings(header_image_tiling=>''), 'tiling 5';

    # exercise _valid_font
    ok $class->ValidSettings(body_font=>'Helvetica'), 'font 1';
    ok !$class->ValidSettings(body_font=>'Comic Sans'), 'font 2';
    ok !$class->ValidSettings(body_font=>''), 'font 3';
    ok !$class->ValidSettings(body_font=>'Helvetica, Lucida, sans-serif'), 'font 4';
    ok $class->ValidSettings(body_font=>'serif'), 'font 5';
    ok $class->ValidSettings(body_font=>'sans-serif'), 'font 6';

    # exercise _valid_attachment_id
    ok $class->ValidSettings(header_image_id=>$att_id), 'attachment 1';
    ok !$class->ValidSettings(header_image_id=>'NaN'), 'attachment 2';
    ok !$class->ValidSettings(header_image_id=>'99999999999'), 'attachment 3';
    ok !$class->ValidSettings(header_image_id=>''), 'attachment 4';
    ok $class->ValidSettings(header_image_id=>undef), 'attachment 5';

    # exercise _valid_theme_id
    ok $class->ValidSettings(base_theme_id=>$theme_id), 'theme 1';
    ok !$class->ValidSettings(base_theme_id=>'NaN'), 'theme 2';
    ok !$class->ValidSettings(base_theme_id=>'999999999'), 'theme 3';
    ok !$class->ValidSettings(base_theme_id=>''), 'theme 4';

    # excercise _valid_foreground_shade
    ok $class->ValidSettings(foreground_shade=>'light'), 'foreground 1';
    ok $class->ValidSettings(foreground_shade=>'dark'), 'foreground 2';
    ok !$class->ValidSettings(foreground_shade=>'anything else'), 'foreground 3';

    # field doesn't exist
    ok !$class->ValidSettings(ENOSUCH_field=>'nothing'), 'no such field';
}

as_hash: {
    my $minimal = $default->as_hash(set=>'minimal');
    my @undef = grep { !defined($minimal->{$_}) } Socialtext::Theme->COLUMNS;
    ok scalar(@undef) == 0, 'all columns in minimal as_hash()';

    my $default = $default->as_hash();
    @undef = grep { !defined($default->{$_}) } qw(
        background_image_filename
        background_image_mime_type
        background_image_url
        header_image_filename
        header_image_mime_type
        header_image_url
        foreground_shade
    );
    ok scalar(@undef) == 0, 'additional columns in full as_hash()';
}

export_import: {
    my $dir = tempdir(CLEANUP=>1);
    my $account = create_test_account_bypassing_factory();
    my $filename = sql_singlevalue(
        'SELECT filename FROM attachment WHERE attachment_id = ?', $att_id);
    my $name = $default->name;
    my %static = (
        header_image_tiling=>'vertical',
        background_image_tiling=>'none',
        header_image_position=>'left top',
        header_color=>'#cc6600',
        background_image_position=>'right bottom',
        header_font=>'Arial',
        background_color=>'#ffffff',
        tertiary_color=>'#eeeeee',
        body_font=>'Times',
        primary_color=>'#dddddd',
        secondary_color=>'#cccccc',
        foreground_shade=>'light',
    );

    $account->prefs->save({
        theme=>{
            %static,
            base_theme_id=>$default->theme_id,
            background_image_id=>$att_id,
            header_image_id=>$att_id,
            logo_image_id=>$att_id,
            favicon_image_id=>$att_id,
        },
    });

    diag "make exportable";
    my $theme = $account->prefs->prefs->{theme};
    my $exportable = Socialtext::Theme->MakeExportable($theme, $dir);

    ok -f "$dir/$filename", 'exported images';

    for my $key (keys %static) {
        ok $static{$key} eq $exportable->{$key}, "static $key exported";
    }

    my @dynamic_fields = qw(
        base_theme background_image header_image logo_image favicon_image);
    for my $dynamic (@dynamic_fields) {
        my $missing = $dynamic .'_id';
        ok !defined($exportable->{$missing}), "dynamic $missing missing";
        ok defined($exportable->{$dynamic}), "dynamic $dynamic added";

        my $cmp = $dynamic eq 'base_theme' ? $name : $filename;
        is $exportable->{$dynamic}, $cmp, "dynamic $dynamic expected value";
    }

    diag "make_importable";
    my $importable = Socialtext::Theme->MakeImportable($exportable, $dir);

    for my $key (keys %static) {
        ok $static{$key} eq $importable->{$key}, "static $key imported";
    }

    for my $dynamic (@dynamic_fields) {
        my $found = $dynamic .'_id';
        ok !defined($exportable->{$dynamic}), "dynamic $dynamic missing";
        ok defined($importable->{$found}), "dynamic $found added";

        if ($dynamic eq 'base_theme') {
            is $importable->{base_theme_id}, $default->theme_id, 'found theme';
        }
        else {
            my $imported_id = $importable->{$found};
            isnt $imported_id, $att_id, 'found new attachment';
            my $imported_name = sql_singlevalue(
                'SELECT filename FROM attachment WHERE attachment_id = ?',
                $imported_id
            );

            is $imported_name, $filename, 'imported file has the same name';
        }
    }


}

done_testing;
exit;
################################################################################
