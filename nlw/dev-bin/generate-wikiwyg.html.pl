#!/usr/bin/perl
use strict;
use Template;
use File::Temp;
use lib 'lib';
use Socialtext::File qw(get_contents set_contents);
use Socialtext::System qw(shell_run);

$Socialtext::System::SILENT_RUN = 1;

my $tmp = File::Temp->new(UNLINK => 0, SUFFIX => '.css');
shell_run(
    qw(/opt/ruby/1.8/bin/sass -t compressed --compass),
    'share/sass/wikiwyg.sass', "$tmp",,
);

my $template = Template->new(
    INCLUDE_PATH => 'share/template',
);

my $tt = '<html><head><style>[% css %]</style></head><body class="wiki" onload="window.Socialtext={body_loaded:true}"></body></html>';

my $output = '';
$template->process(\$tt, { css => get_contents("$tmp") }, \$output)
    or die $template->error;

set_contents('share/html/wikiwyg.html', $output);
