# @COPYRIGHT@
package Socialtext::RevisionPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

use Class::Field qw( const );
use Socialtext::String;
use Socialtext::Encode;
use Socialtext::l10n qw( loc );
use Socialtext::Revision::RenderedSideBySideDiff;
use Socialtext::Revision::WikitextSideBySideDiff;
use Socialtext::Revision::HtmlSideBySideDiff;
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

    $self->hub->helpers->add_js_bootstrap({
        page => {
            id       => $page->page_id,
            title    => $page->title,
            type     => $page->type,
            full_uri => $page->full_uri,

            new_revision_id => $self->cgi->new_revision_id,
        },
    });

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

    my $output = $self->cgi->mode eq 'html'
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

    my $old_revision = $before_page->revision_num;
    my $new_revision = $new_page->revision_num;
    my ($next_id,$prev_id) = $self->next_compare();

    my $class = 'Socialtext::Revision::HtmlSideBySideDiff';
    my $mode = $self->cgi->mode || 'html'; 
    if ($self->cgi->mode eq 'wikitext') {
        $class = 'Socialtext::Revision::WikitextSideBySideDiff';
       $mode = $self->cgi->mode; 
    }
    elsif ($self->cgi->mode eq 'view') {
        $class = 'Socialtext::Revision::RenderedSideBySideDiff';
    }

    my $differ = $class->new(
        before_page => $before_page,
        after_page => $new_page,
        hub => $self->hub,
    );

    $self->screen_template('view/page/revision_compare');
    $self->render_screen(
        $page->all,
        mode          => $mode,
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


package Socialtext::Revision::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'mode';
cgi new_revision_id => '-clean_path';
cgi old_revision_id => '-clean_path';
cgi revision_id     => '-clean_path';

1;

