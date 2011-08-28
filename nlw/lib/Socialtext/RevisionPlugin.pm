# @COPYRIGHT@
package Socialtext::RevisionPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

use Class::Field qw( const );
use Socialtext::String;
use Socialtext::Encode;
use Socialtext::l10n qw( loc );
use Try::Tiny;

sub EDIT_SUMMARY_MAXLENGTH { 250 }

sub class_id { 'revision' }
const cgi_class => 'Socialtext::Revision::CGI';

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add( action => 'revision_list' );
    $registry->add( action => 'revision_view' );
    $registry->add( action => 'revision_compare' );
    $registry->add( action => 'revision_restore' );
}

# XXX this method may not have test coverage
sub revision_list {
    my $self = shift;
    my $rows = [];
    my $page = $self->hub->pages->current;

    for my $revision_id ( $page->all_revision_ids(Socialtext::SQL::NEWEST_FIRST) ) {
        # TODO make this a SQL query (need to figure out how to produce
        # timezone-preferred timestamp output directly from Pg)
        my $rev = Socialtext::PageRevision->Get(
            hub => $self->hub,
            page_id => $page->page_id,
            revision_id => $revision_id,
        );
        my $row = {
            id           => $revision_id,
            number       => $rev->revision_num,
            edit_summary => $rev->edit_summary || '',
            date         => $rev->datetime_for_user,
            from         => $rev->editor->email_address,
            class        => (@$rows % 2 ? 'trbg-odd' : 'trbg-even'),
            is_deleted   => $rev->deleted,
        };
        $rows->[-1]{next} = $row if @$rows;
        push @$rows, $row;
    }

    $self->screen_template('view/page_revision_list');
    $self->render_screen(
        revision_count => $page->revision_count,
        edit_summary_maxlength => EDIT_SUMMARY_MAXLENGTH(),
        $page->all,
        page           => $page,
        display_title  => $self->html_escape( $page->title ),
        rows           => $rows,
    );
}

sub revision_view {
    my $self = shift;
    my $page = $self->hub->pages->current;
    my $revision_id = $self->cgi->revision_id;

    return $self->redirect( $page->uri ) unless $revision_id;

    $page = try { $page->switch_rev($revision_id) };
    return $self->redirect( $page->uri ) unless $page;

    # find the previous and next revision
    # if there is no previous revision, use the current revision
    # if there is no next revision, use the current revision
    my $this_revision = $revision_id;
    my $previous_revision = $this_revision;
    my $next_revision = $this_revision;
    my $one_more_time = 0;

    for my $revision_id (reverse $page->all_revision_ids) {
      if ($one_more_time) {
        $next_revision = $revision_id;
        last;
      }
      if ($revision_id == $this_revision)  {
        $one_more_time = 1;
      } else {
        $previous_revision = $revision_id;
      }
    }

    my $output = $self->cgi->mode eq 'source'
      ? do { local $_ = $self->html_escape( $page->content ); s/$/<br \/>/gm; $_ }
      : $page->to_html;

    my $revision = Socialtext::PageRevision->Get(
        hub => $self->hub,
        page_id => $page->page_id,
        revision_id => $revision_id,
    );

    $self->screen_template('view/page/revision');
    $self->render_screen(
        $page->all,
        from => $page->last_edited_by->email_address,
        previous_revision => $previous_revision,
        next_revision => $next_revision,
        human_readable_revision => $page->revision_num,
        tags => [ map { Socialtext::String::html_escape($_) }
            $page->tags_sorted ],
        edit_summary => $revision->edit_summary,
        edit_summary_maxlength => EDIT_SUMMARY_MAXLENGTH(),
        display_title    => $self->html_escape( $page->title ),
        display_title_decorator  => loc("page.revision=revision", $revision->revision_num),
        print                   => $output,
    );
}


sub next_compare {
    my $self = shift;
    my $page = $self->hub->pages->current;

    my $old_revision_id =  $self->cgi->old_revision_id;
    my $new_revision_id =  $self->cgi->new_revision_id;
    # find the next newest revision after old if old < new
    # TODO: when old meets new, Next Compare bumps both

    my $previous_revision_id = $old_revision_id;
    my $next_revision_id = $old_revision_id;
    my $one_more_time = 0;

    for my $revision_id ($page->all_revision_ids) {
      if ($one_more_time) {
        $next_revision_id = $revision_id;
        last;
      }
      if ($revision_id == $old_revision_id)  {
        $one_more_time = 1;
      } else {
        $previous_revision_id = $revision_id;
      }
    }
      return ($next_revision_id,$previous_revision_id);
}

sub revision_compare {
    my $self = shift;
    my $page     = $self->hub->pages->current;
    my $page_id  = $page->id;
    my $before_page = $self->hub->pages->new_page($page_id);
    my $new_page = $self->hub->pages->new_page($page_id);

    $before_page->switch_rev($self->cgi->old_revision_id);
    $new_page->switch_rev($self->cgi->new_revision_id);

    my $class = (defined $self->cgi->mode and $self->cgi->mode ne 'source')
        ? 'Socialtext::RenderedSideBySideDiff'
        : 'Socialtext::WikitextSideBySideDiff';

    my $differ = $class->new(
        before_page => $before_page,
        after_page => $new_page,
        hub => $self->hub,
    );

    my $old_revision = $before_page->revision_num;
    my $new_revision = $new_page->revision_num;

    my ($next_id,$prev_id) = $self->next_compare();

    $self->screen_template('view/page/revision_compare');
    $self->render_screen(
        $page->all,
        next_id       => $next_id,
        prev_id       => $prev_id,
        diff_rows     => $differ->diff_rows,
        header        => $differ->header,
        display_title => $self->html_escape($page->title),
        display_title_decorator => loc("revision.compare=old,new", $old_revision, $new_revision),
    );
}

# XXX have an error here if the request method is not POST
sub revision_restore {
    my $self = shift;
    my $page = $self->hub->pages->current;


    unless ( $self->hub->checker->can_modify_locked($page) ) {
        $self->redirect($page->uri);
        return '';
    }

    if ( $self->hub->checker->check_permission('edit')) {
        $page->restore_revision(
            revision_id => $self->cgi->revision_id,
            user => $self->hub->current_user
        );
    }
    $self->redirect($page->uri);
}

package Socialtext::SideBySideDiff;

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

# XXX this doesn't actually do any comparison. =(
package Socialtext::RenderedSideBySideDiff;

use base 'Socialtext::SideBySideDiff';

sub diff_rows {
    my $self = shift;
    return [{
        before => $self->before_page->to_html,
        after => $self->after_page->to_html,
    }];
}

package Socialtext::WikitextSideBySideDiff;

use base 'Socialtext::SideBySideDiff';
use Algorithm::Diff::XS;

sub diff_rows {
    my $self = shift;
    return $self->compare(
        $self->before_page->content,
        $self->after_page->content
    );
}

sub compare {
    my $self = shift;
    my $before = shift;
    my $after = shift;

    my @chunks = $self->split_into_diffable_divs($before, $after);

    my @sections;
    for my $chunk (@chunks) {
        push @sections, {
            before => $self->compare_chunk($chunk->[0], $chunk->[1], 'before'),
            after => $self->compare_chunk($chunk->[0], $chunk->[1], 'after'),
        };
    };
    return \@sections;
}

sub split_into_diffable_divs {
    my $self = shift;
    my @sdiffs = Algorithm::Diff::XS::sdiff(
        [ $self->split_into_escaped_lines(shift) ],
        [ $self->split_into_escaped_lines(shift) ],
    );
    my @divs;
    my @accumulation = ('','');
    for (0..$#sdiffs) {
        my $row = $sdiffs[$_];
        my $flag = $row->[0];
        my ($left, $right) = @{$row}[1,2];
        $accumulation[0] .= $left;
        $accumulation[1] .= $right;
        if ('u' eq $flag or $_ == $#sdiffs) {
            push @divs, [ @accumulation ];
            @accumulation = ('','');
        }
    }
    return @divs
}

sub split_into_escaped_lines {
    my $self = shift;
    return split /$/m, Socialtext::String::html_escape($_[0]);
}

sub compare_chunk {
    my $self = shift;
    my $before = shift;
    my $after = shift;
    my $desired_output = shift;

    my @before = $self->split_into_words($before);
    my @after = $self->split_into_words($after);

    # Turn off SvUTF8 flag as Algorithm::Diff::XS doesn't do Unicode.
    Encode::_utf8_off($_) for @before;
    Encode::_utf8_off($_) for @after;

    my @cdiffs = Algorithm::Diff::XS::compact_diff(\@before, \@after);
    my $html   = '';

    # some roughness to deal with the terse structure returned by compact_diff:
    for ( my $ii = 0; $ii + 3 <= $#cdiffs; $ii += 2 ) {
        if ($ii % 4) {
            if ('before' eq $desired_output) {
                my @slice = $cdiffs[$ii] .. $cdiffs[ $ii + 2 ] - 1;
                $html .= enspan_old( @before[ @slice ] );
            }
            elsif ('after' eq $desired_output) {
                my @slice = $cdiffs[ $ii + 1 ] .. $cdiffs[ $ii + 3 ] - 1;
                $html .= enspan_new( @after[ @slice ] );
            }
            else {
                warn "Uhh.... something's super wrong.";
            }
        }
        else {
            $html .= join '', @before[ $cdiffs[$ii] .. $cdiffs[ $ii + 2 ] - 1 ];
        }
    }

    # Now put the SvUTF8 flag back on.
    $html = Socialtext::Encode::ensure_is_utf8($html);

    # XXX need to refactor this (and add a unit test - not necessarily in that
    # order)
    if ($html =~ /^\s+$/m) {
        $html =~ s/\n/<br\/>\n/gsm;
    } else {
        $html =~ s/(.)\n/$1<br\/>\n/gsm;
    }
    return Socialtext::String::double_space_harden($html);
}

sub split_into_words { split /\b/, $_[1] }

sub enspan_old {
    return @_
      ? join '', "<span class='st-revision-compare-old'>", @_, "</span>"
      : '';
}

sub enspan_new {
    return @_
      ? join '', "<span class='st-revision-compare-new'>", @_, "</span>"
      : '';
}


package Socialtext::Revision::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'mode';
cgi new_revision_id => '-clean_path';
cgi old_revision_id => '-clean_path';
cgi revision_id     => '-clean_path';

1;

