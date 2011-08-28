# @COPYRIGHT@
package Socialtext::Formatter::SharepointLinkDictionary;
use base 'Socialtext::Formatter::AbsoluteLinkDictionary';

use strict;
use warnings;

use Class::Field qw'field';

field free      => '/default.aspx?WikiPageName=%{page_uri}&Workspace=%{workspace}';
field interwiki => '/default.aspx?WikiPageName=%{page_uri}&Workspace=%{workspace}%{section}';

1;
