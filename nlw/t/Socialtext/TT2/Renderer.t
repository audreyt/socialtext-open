#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::More tests => 3;

use File::Path ();
use File::Temp ();
use Socialtext::AppConfig;
use Socialtext::TT2::Renderer;
use Socialtext::File ();

{
    my $tempdir = File::Temp::tempdir( CLEANUP => 1 );
    my $template_name = 'template.tmpl';
    my $template_file = "$tempdir/$template_name";

    open my $fh, '>', $template_file
        or die "Cannot write to $template_file: $!";
    print $fh <<'EOF';
This is a template

[% foo %]
EOF
    close $fh;

    my $mod_time = (stat $template_file)[9];

    my $output =
        Socialtext::TT2::Renderer->render(
            template => $template_name,
            paths    => [ $tempdir ],
            vars     => { foo => 42 },
        );

    my $expect = <<'EOF';
This is a template

42
EOF

    is( $output, $expect, 'output matches what was expected' );

    # This is necessary in order to force TT2 to stat the template
    # file again.
    sleep 2;

    # We want to change the file but leave the last mod time as it
    # was, to make sure that our template renderer is using TT2 in
    # such a way that it caches templates.
    open $fh, '>', $template_file
        or die "Cannot write to $template_file: $!";
    print $fh <<'EOF';
This is a new template.
EOF
    close $fh;
    utime $mod_time, $mod_time, $template_file
        or die "Cannot call utime on $template_file: $!";

    $output =
        Socialtext::TT2::Renderer->render(
            template => $template_name,
            paths    => [ $tempdir ],
            vars     => { foo => 42 },
        );
    is( $output, $expect, 'output matches old version of template' );
}

{
    File::Path::rmtree( Socialtext::AppConfig->template_compile_dir(), 0, 1 );

    Socialtext::TT2::Renderer->PreloadTemplates();

    my @files = Socialtext::File::files_under( Socialtext::AppConfig->template_compile_dir() );

    ok( scalar @files,
        'calling PreloadTemplates actually caused something to show up in the template compilation directory' );
}
