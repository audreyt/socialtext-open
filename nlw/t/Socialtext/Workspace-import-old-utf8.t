#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 2;
fixtures(qw( clean db ));

use Socialtext::User;
use Socialtext::Workspace;

# Version "0" export tarballs did not export in utf8 all the time. See
# RT 20744 for details on what this is testing.

# symlink in the skin used by this tarball, for the duration of the test, and
# remove it when we're done
symlink 's3', 'share/skin/nlw';
END { unlink 'share/skin/nlw' }

Socialtext::Workspace->ImportFromTarball( tarball => 't/test-data/export-tarballs/import-utf8.tar.gz' );

{
    my $user = Socialtext::User->new( username => 'autarch@urth.org' );
    my $umlaut = Encode::decode( 'latin-1', 'Uml' . chr( 0xE4 ) . 'ut' );
    my $chinese = chr(13787) . chr(13809);

    is( $user->first_name(), $umlaut, 'first name is Umlaut (with umlaut on a)' );
    is( $user->last_name(), $chinese, 'last name is Chinese' );
}
