# @COPYRIGHT@
package Socialtext::Formatter::RESTLinkDictionary;

use warnings;
use strict;

use base 'Socialtext::Formatter::LinkDictionary';

use Class::Field qw'field';

use constant Prefix => '%{url_prefix}/data/workspaces/%{workspace}';

field free      => Prefix.'/pages/%{page_uri}%{section}';
field interwiki => Prefix.'/pages/%{page_uri}%{section}';
field interwiki_edit => '';
field search_query => Prefix.'/pages?q=%{search_term}';
field category_query => Prefix.'/tags/%{category}/pages';

# REVIEW: What's the right count, is any count at all right?
field recent_changes_query =>
    Prefix.'/pages?order=newest;count=50';

field category => Prefix.'/tags/%{category}/pages';
field weblog   => Prefix.'/tags/%{category}/pages';
field blog     => Prefix.'/tags/%{category}/pages';
field file     => Prefix.'/attachments/%{page_uri}:%{id}/files/%{filename}';
field image    => Prefix.'/attachments/%{page_uri}:%{id}/%{size}/%{filename}';

field people_profile => '%{url_prefix}/st/profile/%{user_id}';
field people_photo => '%{url_prefix}/data/people/%{user_id}/photo';
field people_photo_small => '%{url_prefix}/data/people/%{user_id}/small_photo';

# REVIEW: this is for http:text which is just weird so we let it ride, with
# a slight adjustment
sub special_http {
    my $self = shift;
    return '/%{workspace}/' . $self->SUPER::special_http();
}


1;
