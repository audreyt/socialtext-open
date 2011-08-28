# @COPYRIGHT@
package Socialtext::Formatter::LinkDictionary;

use strict;
use warnings;

=head1 NAME

Socialtext::Formatter::LinkDictionary - A system for formatting links in a workspace

=head1 SYNOPSIS

    # set the viewer's link dictionary
    $hub->viewer->link_dictionary(
        Socialtext::Formattr::LinkDictionary->new()
    );

=head1 DESCRIPTION

A Link Dictionary provides the information necessary to turn a piece of
wikitext that represents a link into HTML of the correct form. Wikitext
includes several types of links within one workspace or between workspaces,
the LinkDictionary formats all of these.

This is the default LinkDictionary, it is designed to be subclassed to allow
alternate HTML outputs from the various link types.

=cut
use Class::Field qw'field';

=head1 LINK TYPES

=head2 free

A free link is a link from one page in a workspace to another page in the
same workspace. See L<Socialtext::Formatter::FreeLink>.

=cut
field free      => '%{page_uri}';

=head2 interwiki

An interwiki link is a link from one page in a workspace to a page in
a different workspace. It is also used to make anchored links within
and between pages. See L<Socialtext::Formatter::InterWikiLink>.

=cut
field interwiki => '/%{workspace}/%{page_uri}%{section}';

=head2 interwiki_edit

An interwiki_edit link links directly to the edit section of another 
page on another workspace.

=cut
field interwiki_edit => '/%{workspace}/?page_name=%{page_uri};page_type=%{page_type}#edit';

=head2 interwiki_edit_incipient

An interwiki_edit link links directly to the edit section of another 
page on another workspace with the incipient flag set.

=cut
field interwiki_edit_incipient => '/%{workspace}/?is_incipient=1;page_name=%{page_uri};page_type=%{page_type}#edit';
=head2 search_query, category_query, recent_chages_query

Some forms of wikitext create a link to a set of search, category
or recent changes results. 

=cut
field search_query =>
    '/%{workspace}/?action=search;search_term=%{search_term}';
field category_query =>
    '/%{workspace}/?action=blog_display;category=%{category}';
field recent_changes_query => '/%{workspace}/?action=recent_changes';

=head2 special_http

Wikitext of the form http:text (without the // or host) is used to make
links to actions in workspaces.

=cut
field special_http         => '%{arg1}';

=head2 category

Links to the category display page.

=cut
field category             =>
    '/%{workspace}/?action=category_display;category=%{category}';

=head2 tag

Alias of 'category'

=cut
field tag             =>
    '/%{workspace}/?action=category_display;category=%{category}';


=head2 weblog

Links to weblog display. (Deprecated in favour of blog)

=cut

field weblog =>
    '/%{workspace}/?action=blog_display;category=%{category}';

=head2 blog

Links to blog display.

=cut

field blog =>
    '/%{workspace}/?action=blog_display;category=%{category}';

=head2 file

{file} links to attachments.

=cut
field file => 
    '/data/workspaces/%{workspace}/attachments/%{page_uri}:%{id}/original/%{filename}';

=head2 image

{image} links to attachments.

=cut
field image    => '/data/workspaces/%{workspace}/attachments/%{page_uri}:%{id}/%{size}/%{filename}';

=head2 people links

{user_link} links to a user's people profile if people is installed an enabled.

=cut

field people_profile => '/st/profile/%{user_id}';
field people_photo => '/data/people/%{user_id}/photo';
field people_photo_small => '/data/people/%{user_id}/small_photo';
field people_tag => '/?action=people;tag=%{tag_name}';

=head2 group links

{group_link} links to a group's profile.

=cut

field group => '/?group/%{group_id}';

=head2 signal links

{signal_hash} provides a signal's permalink.

=cut

field signal         => '/st/signals/%{signal_hash}';
field signal_reply   => '/st/signals/%{in_reply_to_hash}?r=%{signal_hash}';
field signal_hashtag => '/?action=search_signals&search_term=tag_exact:%{hashtag}&sortby=newest';

=head1 METHODS

=head2 new

Create a new link dictionary object. The object has fields as described
above.

=cut
sub new {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    my $self = { @_ };
    return bless $self, $class;
}

=head2 clone

Take an existing LinkDictionary and make a copy of it, so it can be modified
for other uses. See L<Socialtext::Pages>.

=cut
# from programming perl 3
sub clone {
    my $model = shift;
    my $self  = $model->new(%$model, @_);
    return $self;
}

=head2 format_link

This is where the action happens. Different classes in the formatter
call format_link with parameters that are replaced in the system.
See L<Socialtext::Formatter::WaflPhrase> for examples.

=cut
sub format_link {
    my $self = shift;
    my %p    = @_;

    my $method        = $p{link};
    my $format_string = $self->$method;

    # replace the fields in the format string
    $format_string =~ s/%{(\w+)}/$p{$1} || ''/ge;

    return $format_string;
}

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., All Rights Reserved.

=cut


1;
