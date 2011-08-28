#!perl
# @COPYRIGHT@

# this test validates that the correct workspace customization attributes
# are "inherited" by newly created workspaces via the web UI

use strict;
use warnings;
use Cwd qw(getcwd);

use Test::More tests => 6;
use Test::Socialtext;
fixtures( 'db' );
use Socialtext::TT2::Renderer;
use Socialtext::Skin;

my $renderer;
my $skin;

BEGIN {
    $renderer = Socialtext::TT2::Renderer->instance;
    $skin = Socialtext::Skin->new;
}

SKIN_RADIO_BUTTON: {
    my $html = $renderer->render(
        template => 'element/settings/workspaces_settings_skin_section',
        vars     => { uploaded_skin => 0 },
        paths => $skin->template_paths('s2'),
    );

    like $html, qr/<input id="st-workspaceskin-default" type="radio" name="uploaded_skin" value="0" checked="true"/, 'default skin selected';
    like $html, qr/<input id="st-workspaceskin-custom" type="radio" name="uploaded_skin" value="1" disabled="true"/, 'custom skin not selected';

    $html = $renderer->render(
        template => 'element/settings/workspaces_settings_skin_section',
        vars     => {
            uploaded_skin => 1,
            skin_files => [
                {name => 'test1', size => 132456, date => '2007-07-15'}
            ],
        },
        paths => $skin->template_paths('s2'),
    );

    like $html, qr/<input id="st-workspaceskin-default" type="radio" name="uploaded_skin" value="0" >/, 'default skin not selected';
    like $html, qr/<input id="st-workspaceskin-custom" type="radio" name="uploaded_skin" value="1" checked="true"/, 'custom skin selected';
}

NO_FILES: {
    my $html = $renderer->render(
        template => 'element/settings/workspaces_settings_skin_section',
        vars     => { name => 'admin', skin_files => [] },
        paths => $skin->template_paths('s2'),
    );

    like $html, qr/<table class="standard-table" style="display: none;">/, 'File table hidden with no files and custom skin';
}

IS_DEFAULT_SKIN: {
    my $html = $renderer->render(
        template => 'element/settings/workspaces_settings_skin_section',
        vars     => {
            skin_files => [
                {name => 'test1', size => 132456, date => '2007-07-15'}
            ],
        },
        paths => $skin->template_paths('s2'),
    );

    like $html, qr/<table class="standard-table"\s*>/, 'File table is block: display with files and default skin';
}
