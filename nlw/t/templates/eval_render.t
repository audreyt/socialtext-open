#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::More;
use File::Find qw(find);
use Socialtext::TT2::Renderer;
use Socialtext::File qw(get_contents);

my $template_dir = 'share/skin/s3/template';
my @templates;
find( sub { push @templates, $File::Find::name if -f }, $template_dir );
@templates = grep { !m{\.swp$} && s{^$template_dir/}{} } @templates;

plan tests => scalar @templates;

### Create our test fixtures *OUT OF PROCESS*; we call fork() for each test we
### run, and we'll have troubles with an already loaded/used DBH if we create
### the fixtures in-process.
BEGIN {
    system('dev-bin/make-test-fixture --fixture db');
};

my $skin = Socialtext::Skin->new;
my @paths = (
    @{$skin->template_paths},
    glob("share/plugin/*/template"),
);

my $renderer = Socialtext::TT2::Renderer->instance;

# We need to fork before running each test in order to test that [% USE %]
# properly brings in any plugins required. If we didn't use fork, a template
# that does use a filter would bring it into %INC, masking any errors caused
# by subsequent templates that fail to USE the filter.

for my $template (@templates) {
    if (my $child = fork) {
        wait;
        is $?, 0, $template;
        next;
    }

    # Child runs the test
    $renderer->render(
        template => $template,
        paths    => \@paths,
        vars     => {
            pluggable => FakePluggable->new,
            frame_name => 'layout/html',
        },
    );
    exit;
}

package FakePluggable;
sub new { bless {}, $_[0] }
sub registered { 0 }
sub hook {}
