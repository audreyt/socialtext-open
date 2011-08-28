# @COPYRIGHT@
package Apache::Constants;
use strict;
use warnings;
use base 'Exporter';

our @EXPORT_OK = qw(REDIRECT NOT_FOUND OK DECLINED FORBIDDEN);
our %EXPORT_TAGS = (
    response => [qw(REDIRECT)],
    common => [qw(OK DECLINED NOT_FOUND FORBIDDEN)],
);

sub OK { 200 }
sub DECLINED { -1 }
sub FORBIDDEN { 403 }
sub REDIRECT { 302 }
sub NOT_FOUND { 404 }

1;
