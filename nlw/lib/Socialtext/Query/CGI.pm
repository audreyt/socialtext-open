# @COPYRIGHT@
package Socialtext::Query::CGI;
use strict;
use warnings;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'titles';
cgi 'summaries';
cgi 'direction';
cgi 'search_term';
cgi 'orig_search_term';
cgi 'scope';
cgi 'sortby';
cgi 'page_name';

1;
