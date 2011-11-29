# @COPYRIGHT@
package Socialtext::Revision::SideBySideDiff;
use strict;
use warnings;

use base 'Socialtext::Base';

use Class::Field qw( field );
use Socialtext::Helpers;
use Socialtext::l10n qw( loc );
use Socialtext::TT2::Renderer;

field 'before_page';
field 'after_page';
field 'hub';

sub _tag_diff {
    my $self = shift;
    my %p = (
        old_tags => [],
        new_tags => [],
        highlight_class => '',
        @_
    );

    my %in_old;
    foreach (@{$p{old_tags}}) { $in_old{$_} = 1; }

    my $text = join ', ',
        map {exists $in_old{$_} ? $_ : "<span class='$p{highlight_class}'>$_</span>" } @{$p{new_tags}};

    return $text;
}

sub header {
    my $self = shift;
    my @header;

    my %tags = ();
    my @before = map { Socialtext::String::html_escape($_) }
        grep !/^Recent Changes$/, $self->before_page->tags_sorted;
    my @after = map { Socialtext::String::html_escape($_) }
        grep !/^Recent Changes$/, $self->after_page->tags_sorted;

    for my $page ($self->before_page, $self->after_page) {
        my %col;
        my $pretty_revision = $page->revision_num;
        my $rev_text = loc('page.revision=revision', $pretty_revision);
        $col{link} = Socialtext::Helpers->script_link(
            "<strong>$rev_text</strong></a>",
            action      => 'revision_view',
            page_id     => $page->id,
            revision_id => $page->revision_id,
        );
        $col{tags} = ($page == $self->before_page) ? 
            $self->_tag_diff(
                new_tags => \@before,
                old_tags => \@after,
                highlight_class => 'st-revision-compare-old',
            ) :
            $self->_tag_diff(
                new_tags => \@after,
                old_tags => \@before,
                highlight_class => 'st-revision-compare-new',
            );
        $col{editor} = $page->last_edited_by->username;
        $col{summary} = $page->edit_summary;
        $col{date} = $page->datetime_for_user;
        push @header, \%col;
    }
    return \@header;
}

1;

=head1 NAME

Socialtext::Revision::SideBySideDiff - Base revision compare class

=head1 SYNOPSIS

  package Socialtext::Revision::HtmlSideBySideDiff;
  use base 'Socialtext::Revision::SideBySideDiff';

=head1 DESCRIPTION

Base revision compare class. Handles tags and layout.

=cut
