#!perl
# @COPYRIGHT@
use warnings;
use strict;
use File::Temp ();
use Test::Socialtext tests => 4;

BEGIN { use_ok 'Socialtext::CLI' }
use Test::Socialtext::CLIUtils qw/expect_failure expect_success/;

fixtures(qw( db ));

HTML_ARCHIVE: {
    my $ws      = create_test_workspace();
    my $ws_name = $ws->name();

    my $file = Cwd::abs_path(
        ( File::Temp::tempfile( SUFFIX => '.zip', OPEN => 0 ) )[1] );
    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => ['--workspace', $ws_name, '--file', $file]
            )->html_archive();
        },
        qr/\QAn HTML archive of the $ws_name workspace has been created in $file.\E/,
        'html-archive success'
    );
    ok( -f $file, 'zip file exists' );

    unlink $file
        or warn "Could not unlink temp file $file: $!";
}
