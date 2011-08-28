package Socialtext::Rest::PageTagHistory;
# @COPYRIGHT@

use warnings;
use strict;

use base 'Socialtext::Rest::Collection';

$JSON::UTF8 = 1;

sub allowed_methods { 'GET' }

sub collection_name {
    'Tag History for  ' . $_[0]->page->name;
}

sub _resource_to_text {
    my $self = shift;
    my $revisions = shift;

    my $text = '';
    foreach my $revision_tags (@{$revisions}) {
        my $tags = join ', ', @{$revision_tags->{tags}};
        $text .= "Revision Id: $revision_tags->{revision_id}\nRevision Date: $revision_tags->{revision_date}\nTags: $tags\n\n";
    }

    return $text;
}

sub element_list_item {
    my $self = shift;
    my $revision_tags = shift;

    my $url = "revisions/$revision_tags->{revision_id}";

    my $tags = join '</li><li>', 
      map { Socialtext::String::html_escape($_) } @{$revision_tags->{tags}};
    $tags = '<ul><li>' . $tags . "</li></ul>\n";

    my $entry = '<li>Revision Id: <a href="' . $url . '">' . $revision_tags->{revision_id} . '</a></li>';
    $entry .= '<ul>';
    $entry .= '<li>Revision Date: ' . $revision_tags->{revision_date} . '</li>';
    $entry .= '<li>Tags</li>';
    $entry .= $tags;
    $entry .= "</ul>\n";

    return $entry;
}

sub _entities_for_query {
    my $self = shift;

    return map {
        my $revision = $self->hub->pages->new_page( $self->page->id );
        $revision->revision_id($_);
        _revision($revision);
    } $self->page->all_revision_ids();
}

sub _revision {
    my $revision = shift;

    return +{
        revision_id => $revision->revision_id,
        revision_date => $revision->datetime_utc,
        tags => $revision->tags,
    };
}

sub _entity_hash {
    my $self = shift;
    my $revision  = shift;

    return $revision;
}

1;
