package Socialtext::Page;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::MockBase';
use unmocked 'Data::Dumper';
use unmocked 'Class::Field', 'field', 'const';

field 'name';
field 'id', -init => '$self->name';
field 'uri', -init => '$self->id';

const SELECT_COLUMNS_STR => q{fake AS fake, columns AS columns};

sub _new_from_row {
    bless {@_}, __PACKAGE__;
}

sub title { $_[0]->{title} || $_[0]->name || 'Mock page title' }

sub is_untitled {
    my $title = $_[0]->{id} || ''; 
    if ($title  eq 'untitled_page') {
            return 'Untitled Page';
    }
    elsif ($title eq 'untitled_spreadsheet') {
        return 'Untitled Spreadsheet';
    }
    return '';
}

sub deleted { return $_[0]->{deleted} || 0; }

sub to_html_or_default {
    my $self = shift;
    return $self->{html} || ($self->title . " Mock HTML");
}

sub to_absolute_html {
    my $self = shift;
    return $self->{absolute_html} || "$self->{page_id} Absolute HTML";
}

sub to_html {
    my $self = shift;
    return $self->{html} || "$self->{page_id} HTML";
}

sub preview_text { 'preview text' }

sub directory_path { '/directory/path' }

sub load {} 
sub exists {}
sub loaded { 1 }
sub update { }
sub store {}

sub hub { $_[0]->{hub} || Socialtext::Hub->new }

sub revision_count { $_[0]->{revision_count} || 1 }
sub revision_id { $_[0]->{revision_id} || 1 }

sub content { $_[0]->{content} || 'Mock page content' }

sub add_tags {
    my $self = shift;
    push @{ $self->{tags} }, @_;
}

sub is_spreadsheet { $_[0]->page_type eq 'spreadsheet' }

sub page_type { $_[0]->{type} || 'page' }
sub revision_num { $_[0]{revision} || 'page_rev' }
sub tags { $_[0]{category} || $_[0]{tags} || ['mock_category'] }

sub datetime_for_user { 'Mon 12 12:00am' }
sub create_time { 'Mon 12 12:00am' }
sub creator { Socialtext::User->new(username => 'mocked_user') }
sub edit_summary { 'awesome' }

sub full_uri { '/workspace_mock_workspace_name/current' }
1;
