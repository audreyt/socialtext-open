# @COPYRIGHT@
package Socialtext::CGI::Scrubbed;
use strict;
use warnings;

INIT {
    delete $INC{'Socialtext/CGI/Scrubbed.pm'};
    require Socialtext::CGI::Scrubbed;
    require CGI;
    our @ISA = 'CGI';
}

1;
