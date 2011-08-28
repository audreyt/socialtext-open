#!perl
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::AppConfig;
use Test::Socialtext;

use Digest::MD5 ();

plan tests => 2;
fixtures(qw( db ));

my $test_dir = Socialtext::AppConfig->test_dir();
my $ws      = create_test_workspace();
my $ws_name = $ws->name();

my $image = 't/attachments/socialtext-logo-30.gif';
$ws->set_logo_from_file(
    filename   => $image,
);

my $md5 = md5_checksum( $ws->logo_filename() );

my $tarball = $ws->export_to_tarball(dir => $test_dir);

# Deleting the user is important so that we know that both user and
# workspace data is restored
$ws->delete();

Socialtext::Workspace->ImportFromTarball( tarball => $tarball );

{
    my $ws = Socialtext::Workspace->new(name => $ws_name);

    ok( $ws->logo_filename(),
        'check that workspace has a local logo file' );

    is( $md5, md5_checksum( $ws->logo_filename() ),
        'md5 checksum for original image and logo after import are the same' );
}

sub md5_checksum {
    my $file = shift;
    open my $fh, '<', $file
        or die "Cannot read $file: $!";

    return Digest::MD5::md5_hex( do { local $/; <$fh> } );
}
