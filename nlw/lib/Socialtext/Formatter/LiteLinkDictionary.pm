# @COPYRIGHT@
package Socialtext::Formatter::LiteLinkDictionary;
use base 'Socialtext::Formatter::LinkDictionary';

use strict;
use warnings;

use Class::Field qw'field';

field free           => '%{page_uri}';
field interwiki      => '/m/page/%{workspace}/%{page_uri}%{section}';
field interwiki_edit =>
    '/m/page/%{workspace}/%{page_uri}%{section}?action=edit';
field interwiki_edit_incipient =>
    '/m/page/%{workspace}/%{page_uri}%{section}?action=edit;is_incipient=1';
field search_query   => '/m/search/%{workspace}?search_term=%{search_term}';
field category_query => '/m/changes/%{workspace}/%{category}';
field recent_changes_query => '/m/changes/%{workspace}';
field category             => '/m/tag/%{workspace}/%{category}';
field tag                  => '/m/tag/%{workspace}/%{category}';
field weblog               => '/m/changes/%{workspace}/%{category}';
field blog                 => '/m/changes/%{workspace}/%{category}';
# special_http and file and image are default

=head2 people links

{user_link} links to a user's people profile if people is installed an enabled.

=cut

field people_profile => '/m/profile/%{user_id}';

sub format_link {
    my $self   = shift;
    my %p      = @_;
    my $method = $p{link};

    # Fix {bz: 1838}: Normal link dictionary uses "is_incipient=1" to signify
    # incipient pages meant for editing, but in Lite mode we should simply
    # enter Edit mode with "?action=edit".
    if ($method eq 'free') {
        $p{page_uri} =~ s{
            ^
            (.*[;&])?
            page_name=([^;&]+)
            .*
        }{
            (index($1, 'is_incipient=1') >= 0)
                ? "$2?action=edit"
                : $2
        }sex;
    }

    $self->SUPER::format_link(%p);
}

1;
