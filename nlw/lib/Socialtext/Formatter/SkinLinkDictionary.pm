# @COPYRIGHT@
package Socialtext::Formatter::SkinLinkDictionary;
use base 'Socialtext::Formatter::LinkDictionary';

use strict;
use warnings;
use Class::Field qw'field';

field free      => 'http:?action=display;workspace=%{workspace};page_name=%{page_uri}';
field interwiki => 'http:?action=display;workspace=%{workspace};page_name=%{page_uri}';

sub special_http {
    my $self = shift;
    return '%{url_prefix}' . '/%{workspace}/' . $self->SUPER::special_http();
}

1;
