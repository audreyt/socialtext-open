#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 12;
use Socialtext::Formatter::Wafl;

# Ideally, this test would call a javascript unescape_comments() function via
# a standalone javascript interpreter to verify that the implementation does
# the right thing.  Currently, we don't have the infrastructure to do that,
# but we should work on it.

my @cases = (
    'text <!-- a comment --> and more text',
    '<option>--------</option>',
    '<option>-----------</option>',
    '`$foo -= 2;`',
    '=-=-=-=- cut here -=-=-=-=',
    '`$foo = $bar - $baz;`'
);

# XXX: this just emulates what the javascript code really does.
sub unescape_comments {
    my $html = shift;

    $html =~ s/-=/-/g;
    $html =~ s/==/=/g;

    return $html;
}

foreach my $case (@cases) {
    my $escaped = Socialtext::Formatter::Wafl->escape_wafl_dashes($case);

    unlike( $escaped, qr/--/, "'$case' is a proper comment" );
    is( unescape_comments($escaped), $case, "'$case' decodes properly" );
}
