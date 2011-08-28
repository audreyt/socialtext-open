# @COPYRIGHT@
package Socialtext::Formatter::RailsDemoLinkDictionary;

use warnings;
use strict;

use base 'Socialtext::Formatter::LinkDictionary';

use Class::Field qw'field';

field free => '%{page_uri}';
field interwiki => '/%{workspace}/pages/%{page_uri}%{section}';
field search_query => '/%{workspace}/search?q=%{search_term}';
field recent_changes_query => '/%{workspace}/changes';

1;
