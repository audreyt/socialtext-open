# @COPYRIGHT@
package Socialtext::CategoryPlugin;
use strict;
use warnings;

use base 'Socialtext::Query::Plugin';

use Class::Field qw( const field );
use List::Util qw/min/;
use Readonly;
use URI::Escape ();

use Socialtext::File;
use Socialtext::Pages;
use Socialtext::Paths;
use Socialtext::Permission qw( ST_ADMIN_WORKSPACE_PERM );
use Socialtext::SQL qw/:exec sql_txn/;
use Socialtext::Timer qw/time_scope/;
use Socialtext::Validate qw( validate SCALAR_TYPE USER_TYPE );
use Socialtext::l10n;

const class_id => 'category';
const class_title => __('class.category');
const cgi_class   => 'Socialtext::Category::CGI';

sub Decode_category_email {
    my $class = shift;
    my $category = shift || return;
    $category =~ s/(?<=\w)_(?!_)/=20/g;
    $category =~ s/__/_/g;
    $category =~ s/=/%/g;
    Encode::_utf8_off($category);
    $category = $class->uri_unescape($category);
    return $category;
}

{
    Readonly my $UnsafeChars => '^a-zA-Z0-9_.-';

    sub Encode_category_email {
        my $class    = shift;
        my $category = URI::Escape::uri_escape_utf8( shift, $UnsafeChars );
        $category =~ s/%/=/g;
        $category =~ s/_/__/g;
        $category =~ s/=20/_/g;
        return $category;
    }
}

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add( action => 'category_list' );
    $registry->add( action => 'category_display' );
    $registry->add( action => 'category_delete_from_page' );
    $registry->add( wafl => 'category_list' => 'Socialtext::Category::Wafl' );
    $registry->add( wafl => 'category_list_full' => 'Socialtext::Category::Wafl' );
    $registry->add( wafl => 'tag_list' => 'Socialtext::Category::Wafl' );
    $registry->add( wafl => 'tag_list_full' => 'Socialtext::Category::Wafl' );
}

sub category_list {
    my $self = shift;
    my %weighted = $self->weight_categories;
    my $tags = $weighted{tags};

    my @rows = grep { $_->{page_count} > 0 } map {
        {
            display    => $_->{name},
            escaped    => $self->uri_escape( $_->{name} ),
            page_count => $_->{page_count},
        }
    } lsort_by name => @$tags;

    my $is_admin = $self->hub->authz->user_has_permission_for_workspace(
        user       => $self->hub->current_user,
        permission => ST_ADMIN_WORKSPACE_PERM,
        workspace  => $self->hub->current_workspace,
    );

    $self->screen_template('view/taglistview');
    return $self->render_screen(
        display_title => loc("wiki.all-tags"),
        rows          => \@rows,
        allow_delete  => 0,
    );
}

sub category_delete_from_page {
    my $self = shift;

    return unless $self->hub->checker->check_permission('edit');

    my $page_id = shift || $self->uri_escape($self->cgi->page_id);
    my $category = shift || $self->cgi->category;
    my $page = $self->hub->pages->new_page($page_id);

    return unless $self->hub->checker->can_modify_locked($page);

    $page->delete_tag($category); # automatically saves
}

sub all {
    my $self = shift;

    my $dbh = sql_execute(<<EOT, 
SELECT tag FROM page_tag
    WHERE workspace_id = ?
    GROUP BY tag
    ORDER BY tag
EOT
        $self->hub->current_workspace->workspace_id,
    );

    my $tags = $dbh->fetchall_arrayref;
    return map { $_->[0] } @$tags;
}

sub add_workspace_tag {
    my $self = shift;
    my $tag  = shift;

    sql_execute(<<EOT,
INSERT INTO page_tag VALUES (?, NULL, ?)
EOT
        $self->hub->current_workspace->workspace_id, $tag,
    );

}


sub exists {
    my $self = shift;
    my $tag  = shift;

    my $result = sql_singlevalue(<<EOT,
SELECT 1 FROM page_tag
    WHERE workspace_id = ?
      AND LOWER(tag) = LOWER(?)
EOT
        $self->hub->current_workspace->workspace_id,
        $tag,
    );
    return $result;
}

sub category_display {
    my $self = shift;
    my $category = shift || $self->cgi->category;

    my $sortby = $self->cgi->sortby || 'Date';
    my $direction = $self->cgi->direction || $self->sortdir->{ $sortby };
    $direction = $direction eq 'desc' ? 'desc' : 'asc';
    my $limit = $self->cgi->limit || Socialtext::Pageset::PAGE_SIZE;
    $limit = min($limit, Socialtext::Pageset::MAX_PAGE_SIZE);
    my $offset = $self->cgi->offset || 0;

    my $results = $self->_get_pages_for_listview(
        $category, $direction, $sortby, $limit, $offset );

    my $uri_escaped_category = $self->uri_escape($category);
    my $html_escaped_category = $self->html_escape($category);

    $self->screen_template('view/category_display');
    return $self->render_screen(
        summaries              => $self->show_summaries,
        display_title          => loc("nav.tag=tag", $category),
        predicate              => 'action=category_display;category=' . $uri_escaped_category,
        rows                   => $results->{rows},
        html_escaped_category  => $html_escaped_category,
        uri_escaped_category   => $uri_escaped_category,
        email_category_address => $self->email_address($category),
        sortdir                => $self->sortdir,
        sortby                 => $sortby,
        direction              => $direction,
        unplug_uri    => "?action=unplug;tag=$uri_escaped_category",
        unplug_phrase => loc('info.unplug=tag', $html_escaped_category),
        load_row_times         => \&Socialtext::Query::Plugin::load_row_times,
        Socialtext::Pageset->new(
            cgi => {$self->cgi->all},
            total_entries => $results->{total_entries},
        )->template_vars(),
        partial_set => 1,
    );
}

# REVIEW - this is a somewhat nasty hack to use the sorting
# functionality of ST::Query::Plugin without having to inherit from
# it.
sub _sort_closure {
    my $self     = shift;
    my $sort_map = shift;

    my $sort_col;
    my $direction;
    if ($self->cgi->sortby) {
        $sort_col = $self->cgi->sortby;

        $direction =
            length $self->cgi->direction
            ? ($self->cgi->direction and $self->cgi->direction ne 'asc') ? 'desc' : 'asc'
            : $sort_map->{$sort_col};
    } else {
        $sort_col = 'Date';
        $direction = $sort_map->{Date};
    }

    return $self->_gen_sort_closure(
        $sort_map, $sort_col,
        $direction
    );
}

# This is copied verbatim from ST::Query::Plugin, which
# sucks. However, if we use that package's method, the sort sub
# doesn't work. AFAICT, it seems to be a scoping and/or namespace
# problem with the use of $a and $b. I suspect that the sort closure
# is capturing $a and $b in the package where it's defined, or something like that.
#
# Andy adds: Yes, it's a scoping/namespace issue.  However, you can get Perl to pass
# your $a/$b on the stack by providing a prototype for them, as in:
#
# sub _gen_sort_closure($$) {
#    my $a = shift;
#    my $b = shift;
#    ...
# }
sub _gen_sort_closure {
    my $self        = shift;
    my $sortdir_map = shift; # the default mapping of sortby to a direction
    my $sortby      = shift; # the attribute being sorted on
    my $direction   = shift || ''; # the direction ('asc' or 'desc')

    if ( $sortby eq 'revision_count' ) { # The only integral attribute, so use numeric sort
        if ( $direction eq 'asc' ) {
            return sub {
                $a->{revision_count} <=> $b->{revision_count}
                    or lcmp($a->{Subject}, $b->{Subject});
                }
        }
        else {
            return sub {
                $b->{revision_count} <=> $a->{revision_count}
                    or lcmp($a->{Subject}, $b->{Subject});
                }
        }
    }
    elsif ( $sortby eq 'username' ) { 
        # we want to sort by whatever the system knows these users as, which
        # may not be the same as the From header.
        if ( $direction eq 'asc' ) {
            return sub {
                lcmp(Socialtext::User->new( 
                    username => $a->{username} 
                )->best_full_name,
                Socialtext::User->new(
                    username => $b->{username}
                )->best_full_name)
                or lcmp($a->{Subject}, $b->{Subject});
            }
        }
        else {
            return sub {
                lcmp(Socialtext::User->new( 
                    username => $b->{username} 
                )->best_full_name,
                Socialtext::User->new(
                    username => $a->{username}
                )->best_full_name)
                or lcmp($a->{Subject}, $b->{Subject});
            }
        }
    }
    else { # anything else, most likely a string
        if ( $direction eq 'asc' ) {
            return sub {
                lcmp($a->{$sortby}, $b->{$sortby})
                    or lcmp($a->{Subject}, $b->{Subject});
            };
        }
        else {
            return sub {
                lcmp($b->{$sortby}, $a->{$sortby})
                    or lcmp($a->{Subject}, $b->{Subject});
            };
        }
    }
}

sub page_count {
    my $self = shift;
    my $tag  = shift;
    
    $tag = Socialtext::Encode::ensure_is_utf8($tag);

    if (lc($tag) eq 'recent changes') {
        my $prefs = $self->hub->recent_changes->preferences;
        my $seconds = $prefs->changes_depth->value * 1440 * 60;
        return Socialtext::Pages->ChangedCount(
            workspace_id => $self->hub->current_workspace->workspace_id,
            duration => $seconds,
        );
    }

    my $result = sql_singlevalue(<<EOT,
SELECT count(page_id) FROM page_tag
    WHERE workspace_id = ?
      AND LOWER(tag) = LOWER(?)
EOT
        $self->hub->current_workspace->workspace_id,
        $tag,
    );
    return 0+$result;
}

sub get_pages_for_category {
    my $self = shift;
    my $t = time_scope 'get_for_category';
    my ( $tag, $limit, $sort_style, $offset ) = @_;
    $tag = lc($tag);
    $sort_style ||= 'update';
    my $order_by = $sort_style eq 'update' 
                        ? 'last_edit_time DESC' 
                        : 'create_time DESC';

    # Load from the database
    my $pages = [];
    if (lc($tag) eq 'recent changes') {
        $pages = Socialtext::Pages->All_active(
            hub          => $self->hub,
            workspace_id => $self->hub->current_workspace->workspace_id,
            order_by     => $order_by,
            ($limit ? (limit => $limit) : ()),
            ($offset ? (offset => $offset) : ()),
        );
    }
    else {
        $tag = Socialtext::Encode::ensure_is_utf8($tag);
        $pages = Socialtext::Pages->By_tag(
            hub          => $self->hub,
            workspace_id => $self->hub->current_workspace->workspace_id,
            tag          => $tag,
            order_by     => $order_by,
            ($limit ? (limit => $limit) : ()),
            ($offset ? (offset => $offset) : ()),
        );
    }

    return @$pages if wantarray;
    return $pages;
}

sub _get_pages_for_listview {
    my ($self, $tag, $sortdir, $sortby, $limit, $offset) = @_;
    my $t = time_scope 'tagged_for_listview';

    my $hub = $self->hub;
    my $order_by = $self->ui_sort_to_order_by($sortby, $sortdir);
    my $ws_id = $hub->current_workspace->workspace_id;

    my ($total, $model_pages);
    my @args = (
        hub              => $hub,
        workspace_id     => $ws_id,
        order_by         => $order_by,
        offset           => $offset,
        limit            => $limit,
        do_not_need_tags => 1,
    );

    if (lc($tag) eq 'recent changes') {
        $total = Socialtext::Pages->ActiveCount(
            workspace_id => $ws_id
        );
        $model_pages = Socialtext::Pages->All_active(@args);
    }
    else {
        $tag = Socialtext::Encode::ensure_is_utf8($tag);
        push @args, tag => $tag;

        $total = Socialtext::Pages->TaggedCount(
            workspace_id => $ws_id,
            tag          => $tag
        );
        $model_pages = Socialtext::Pages->By_tag(@args);
    }

    return {
        total_entries => $total,
        rows => [map { $_->to_result } @$model_pages],
    };
}

sub get_pages_numeric_range {
    my $self = shift;
    my $category           = shift;
    my $start              = shift || 0;
    my $finish             = shift;
    my $sort_and_get_pages = shift;
    my $limit              = $finish - $start;
    my @pages              = $self->get_pages_for_category(
        $category, $limit, $sort_and_get_pages, $start
    );
    return @pages;
}

{
    Readonly my $spec => {
        tag  => SCALAR_TYPE,
        user => USER_TYPE,
    };

    sub delete {
        my $self = shift;
        my %p    = validate( @_, $spec );
        my $tag = $p{tag};

        # Delete the tag on each page
        sql_txn {
            for my $page ( $self->get_pages_for_category($tag) ) {
                $page->delete_tags($tag); # automatically stores
            }

            # Delete any workspace tags
            sql_execute(q{
                DELETE FROM page_tag 
                 WHERE workspace_id = ? AND LOWER(tag) = LOWER(?)
            }, $self->hub->current_workspace->workspace_id, $tag);
        };
    }
}

sub match_categories {
    my $self  = shift;
    my $match = shift;

    return sort grep { /\Q$match\E/i } $self->all;
}

sub weight_categories {
    my $self = shift;
    my %orig_tags = map { lc($_) => $_ } @_;

    my @lower_tags = keys %orig_tags;
    my %data = (
        maxCount => 0,
        tags => [],
    );

    my $tag_args = join(',', map { '?' } @lower_tags);
    my $tag_in = @lower_tags ? "AND LOWER(page_tag.tag) IN ($tag_args)" : '';
    my $dbh = sql_execute(<<EOT, 
SELECT page_tag.tag AS name, count(page_tag.page_id) AS page_count 
    FROM page_tag
    JOIN page ON page.workspace_id = page_tag.workspace_id
             AND page.page_id = page_tag.page_id
             AND NOT page.deleted
    WHERE page_tag.workspace_id = ?
      $tag_in
    GROUP BY page_tag.tag
    ORDER BY count(page_tag.page_id) DESC, page_tag.tag
EOT
        $self->hub->current_workspace->workspace_id, @lower_tags,
    );

    $data{tags} = $dbh->fetchall_arrayref({});
    my $max = 0;
    my %seen_tags;
    my @keepers;
    for (@{ $data{tags} }) {
        # If we were given a list of tags, then we should only return
        # tags in that list
        if (%orig_tags) {
            next if $seen_tags{ lc $_->{name} }++;
            $_->{name} = $orig_tags{ lc $_->{name} };
        }

        $max = $_->{page_count} if $_->{page_count} > $max;
        $_->{page_count} += 0; # cast to number
        push @keepers, $_;
    }
    $data{maxCount} = $max;
    $data{tags} = \@keepers;
    return %data;
}

sub email_address {
    my $self = shift;
    my $category = shift;
    return '' if lc $category eq 'recent changes';
    $category = $self->Encode_category_email($category);
    my $email_address = $self->hub->current_workspace->email_in_address;
    if ( !$self->hub->current_workspace->email_weblog_dot_address ) {
        $email_address =~ s/\@/\+$category\@/;
    }
    else {
        $email_address =~ s/\@/\.$category\@/;
    }
    return $email_address;
}

package Socialtext::Category::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'category';
cgi 'page_id' => '-clean_path';
cgi 'sortby';
cgi 'direction';
cgi 'summaries';
cgi 'offset';
cgi 'limit';

######################################################################
package Socialtext::Category::Wafl;

use base 'Socialtext::Query::Wafl';
use Socialtext::l10n qw(loc);

sub _set_titles {
    my $self = shift;
    my $arguments  = shift;

    my $title_info;
    if ( $arguments =~ /blog/i ) {
  
        if ( $self->target_workspace ne $self->current_workspace_name ) {
            $title_info = loc("blog.recent-posts=tag,wiki", $arguments, $self->target_workspace);
        } else {
            $title_info = loc("blog.recent-posts=tag", $arguments);
        }
    }
    else {
        if ( $self->target_workspace ne $self->current_workspace_name ) {
            $title_info = loc("nav.recent-changes=tag,wiki", $arguments, $self->target_workspace);
        } else {
            $title_info = loc("nav.recent-changes=tag", $arguments);
        }
    }
    $self->wafl_query_title($title_info);
    $self->wafl_query_link( $self->_set_query_link($arguments) );
}

sub _set_query_link {
    my $self = shift;
    my $arguments = shift;
    return $self->hub->viewer->link_dictionary->format_link(
        link => 'category_query',
        workspace => $self->target_workspace,
        category => $self->uri_escape($arguments),
    );
}

sub _get_wafl_data {
    my $self = shift;
    my $hub            = shift;
    my $category       = shift || '';
    my $workspace_name = shift;

    $hub = $self->hub_for_workspace_name($workspace_name);
    $hub->recent_changes->get_recent_changes_in_category(
        count    => 10,
        category => lc($category),
    );
}

1;
