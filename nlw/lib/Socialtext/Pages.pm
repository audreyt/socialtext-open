# @COPYRIGHT@
package Socialtext::Pages;
use strict;
use warnings;

use base 'Socialtext::Base';

use Carp qw/croak/;
use Class::Field qw( const field );
use Email::Valid;
use Guard;
use Readonly;
use Try::Tiny;
use Scalar::Util qw/blessed/;
use Socialtext::File;
use Socialtext::Log 'st_log';
use Socialtext::Page;
use Socialtext::Paths;
use Socialtext::SQL qw/:exec sql_format_timestamptz/;
use Socialtext::String qw/title_to_id MAX_PAGE_ID_LEN/;
use Socialtext::Timer qw/time_scope/;
use Socialtext::User;
use Socialtext::Validate qw( validate DIR_TYPE );
use Socialtext::WeblogUpdates;
use Socialtext::Workspace;
use Socialtext::l10n qw(loc __);

const class_id => 'pages';
const class_title => __('class.pages');

field current => 
      -init => '$self->new_page($self->current_name)';

sub ensure_current {
    my ($self, $page) = @_;
    $page = $self->new_page($page) unless blessed($page);
    my $old_current = $self->current;
    my $g = guard { $self->current($old_current) };
    $self->current($page);
    return $g;
}

=head2 $page->all()

Returns a list of all page objects that exist in the current workspace.
This includes deleted pages.

=cut

sub all {
    my $self = shift;
    my $t = time_scope 'all_pages';
    return map {$self->new_page($_)} $self->all_ids;
}

=head2 $pages->all_active()

Returns a list of all active page objects that exist in the current
workspace and are active (not deleted).

=cut

sub all_active {
    my $self = shift;
    my $t = time_scope 'all_active';
    return grep {$_->active} $self->all();
}

sub all_ids {
    my $self = shift;
    my %p = @_;
    my $t = time_scope 'all_ids';
    my $hide_deleted = $p{not_deleted} ? "AND NOT deleted" : '';
    my $sth = sql_execute(<<EOT,
SELECT page_id 
    FROM page
    WHERE workspace_id = ?
        $hide_deleted
    ORDER BY last_edit_time DESC
EOT
        $self->hub->current_workspace->workspace_id,
    );
    my $pages = $sth->fetchall_arrayref();
    return map { $_->[0] } @$pages;
}

=head2 $pages->all_ids_newest_first()

Returns a list of all the directories in page_data_directory,
sorted in reverse date order. Skips symlinks.

=cut

sub all_ids_newest_first {
    my $self = shift;
    return $self->all_ids;
}

=head2 $pages->all_ids_locked()

Returns a list of all page_id's which are currently locked.

=cut

sub all_ids_locked {
    my $self = shift;
    my $t = time_scope 'all_locked';
    my $sth = sql_execute(<<EOT,
SELECT page_id 
    FROM page
    WHERE workspace_id = ?
    AND locked = 't'
    ORDER BY last_edit_time DESC
EOT
        $self->hub->current_workspace->workspace_id,
    );
    my $pages = $sth->fetchall_arrayref();
    return map { $_->[0] } @$pages;
}

sub all_newest_first {
    my $self = shift;
    my $t = time_scope 'all_newest_first';
    return map {$self->new_page($_)} 
      $self->all_ids_newest_first;
}

sub all_since {
    my $self = shift;
    my $minutes = shift;
    my $active_only = ((shift) ? "AND deleted = false" : '');

    my $t = time_scope 'all_since';
    my $sth = sql_execute(<<EOT,
SELECT page_id 
    FROM page
    WHERE workspace_id = ?
        AND last_edit_time > ('now'::timestamptz - ?::interval)
        $active_only
    ORDER BY last_edit_time DESC
EOT
        $self->hub->current_workspace->workspace_id,
        "$minutes minutes",
    );
    my $pages = $sth->fetchall_arrayref();
    return map { $self->new_page($_->[0]) } @$pages;
}

sub all_at_or_after {
    my $self = shift;
    my $after_epoch = shift;
    my $active_only = ((shift) ? "AND deleted = false" : '');

    my $t = time_scope 'all_at_or_after';
    my $dt = DateTime->from_epoch(epoch => $after_epoch);
    my $sth = sql_execute(<<EOT,
SELECT page_id 
    FROM page
    WHERE workspace_id = ?
        AND last_edit_time >= ?::timestamptz
        $active_only
    ORDER BY last_edit_time DESC
EOT
        $self->hub->current_workspace->workspace_id,
        sql_format_timestamptz($dt),
    );
    my $pages = $sth->fetchall_arrayref();
    return map { $self->new_page($_->[0]) } @$pages;
}

sub random_page {
    my $self = shift;
    my $t = time_scope 'random_page';
    my $sth = sql_execute(<<EOT,
SELECT page_id 
    FROM page
    WHERE workspace_id = ?
      AND deleted = false
    ORDER BY RANDOM()
    LIMIT 1
EOT
        $self->hub->current_workspace->workspace_id,
    );
    my $pages = $sth->fetchall_arrayref();
    return (@$pages ? $self->new_page($pages->[0][0]) : undef );
}

sub name_to_title { $_[1] }

sub id_to_uri { $_[1] }

# REVIEW: Probably a class Method
sub title_to_uri {
    my $self = shift;
    $self->uri_escape(shift);
}

sub show_mouseover {
    my $self = shift;
    return $self->{show_mouseover} if defined $self->{show_mouseover};
    $self->{show_mouseover} = 
      $self->hub->preferences->new_for_user( $self->hub->current_user )->mouseover_length->value;
}

sub title_to_disposition {
    my $self = shift;
    my $page_name = shift;
    my $page = $self->new_from_name($page_name);

    return unless $page;

    return ('title="[' . loc("link.incipient") . ']" class="incipient"', 
            "?action=display;is_incipient=1;page_name=".
            $self->uri_escape($page_name),
           ) unless $page->active;

    my $disposition = '';
    if ($self->show_mouseover) {
        my $preview = $page->summary;
        $disposition = qq|title="$preview"|;
    }

    return ($disposition, $page->uri);
}

sub current_name {
    my $self = shift;
    my $page_name = 
      $self->hub->cgi->page_name ||
      $self->hub->current_workspace->title;
    return $page_name || '0';
}

sub unset_current {
    my $self = shift;
    delete $self->{current};
}

*new_page = \&new_from_name;
sub new_from_name {
    my $self = shift;
    my $page_name = shift;
    my $id = title_to_id($page_name);
    return if length($id) > MAX_PAGE_ID_LEN;

    # Try loading the page twice - sometimes the page_id can become
    # double encoded if it contains utf8 characters that have been 
    # encoded into %\d\d already.
    my $page = $self->By_id(
        hub          => $self->hub,
        workspace_id => $self->hub->current_workspace->workspace_id,
        page_id      => $id,
        deleted_ok   => 1,
        no_die       => 1,
    ) || try { $self->By_id(
        hub          => $self->hub,
        workspace_id => $self->hub->current_workspace->workspace_id,
        page_id      => $page_name,
        deleted_ok   => 1,
        no_die       => 1,
    ) };

    $page //= Socialtext::Page->Blank(
        hub     => $self->hub, # will use current_user/workspace
        name    => $page_name, # so it gets the right title
        page_id => $id, # so we don't have to re-calc the id
    );
    return $page;
}

# This avoids problems in new_from_name wherein the title gets
# set to the URI, not the Subject of the page, even if the page
# already exists.
sub new_from_uri {
    my $self = shift;
    my $uri  = shift;

    my $page = Socialtext::Page->new(
        hub => $self->hub,
        id  => title_to_id($uri) );

    die("Invalid page URI: $uri") unless $page;

    my $return_id = title_to_id($page->title);
    $page->title( $uri ) unless $return_id eq $uri;

    return $page;
}

sub new_page_from_any {
    croak "new_page_from_any removed; convert your test to construct a page with accessors, sorry";
}

sub new_page_title {
    my $self = shift;
    my @months = qw(January February March April May June
        July August September October November December
    );

    my ($sec, $min, $hour, $mday, $mon) = 
      gmtime(time + $self->hub->timezone->timezone_seconds);

    my $ampm = 'am';
    $ampm = 'pm'  if ($hour > 11);
    $hour -= 12 if ($hour > 12);
    $hour = 12 if ($hour == 0);

    my $user = $self->hub->current_user;

    my $title =
        sprintf("%s, %s %s, %d:%02d$ampm", 
                $user->best_full_name,
                $months[$mon], $mday, $hour, $min
               );

    my $current_workspace = $self->hub->current_workspace->name;

    my $x = 2;
    while ( $self->page_exists_in_workspace( $title, $current_workspace ) ) {
        $title =~ s/(?: - \d+)|\z$/ - $x/;
        $x++;
    }

    return $title;
}

=head2 create_new_page

Create a "new page". That is, a page with a title that is automaticall
generated. A scabrous thing, but necessary in the current UI.

Returns a L<Socialtext::Page> object.

=cut
sub create_new_page {
    my $self = shift;

    # See comment in display() about using this error_type.
    $self->hub->require_permission(
        permission_name => 'edit',
        error_type      => 'login_to_edit',
    );

    my $page = $self->new_from_name( $self->new_page_title );

    return $page;
}

sub page_exists_in_workspace {
    my $self       = shift;
    my $page_title = shift;
    my $ws_name    = shift;
    my $page       = $self->page_in_workspace( $page_title, $ws_name );

    return ( $page ) ? 1 : 0;
}

sub page_in_workspace {
    my $self       = shift;
    my $page_title = shift;
    my $ws_name    = shift;
    my $main       = Socialtext->new();

    $main->load_hub(
        current_user      => Socialtext::User->SystemUser(),
        current_workspace => Socialtext::Workspace->new( name => $ws_name ),
    );
    $main->hub()->registry()->load();

    my $page = $main->hub->pages->new_from_name($page_title);
    return $page->active ? $page : undef;
}

my %in_progress = ();
sub render_in_workspace {
    my ($self, $page_id, $ws, $callback) = @_;

    my $page_key = $ws->workspace_id . ":$page_id";
    return if (exists $in_progress{$page_key});
    $in_progress{$page_key} = 1;
    scope_guard { delete $in_progress{$page_key} };

    my $main;
    my $hub = $self->hub;
    if ($ws->workspace_id ne $self->hub->current_workspace->workspace_id) {
        my $original_hub = $hub;
        ($main, $hub) = $ws->_main_and_hub($original_hub->current_user);

        my $link_dictionary = $original_hub->viewer->link_dictionary->clone;
        $link_dictionary->free($link_dictionary->interwiki);
        $hub->viewer->link_dictionary($link_dictionary);

        # {bz: 4881}: We need to disable the cache, as the link dictionary was modified.
        local $Socialtext::Page::DISABLE_CACHING = 1;

        $callback->($hub->pages->new_page($page_id));
        return; # make above call void context
    }
    else {
        $callback->($hub->pages->new_page($page_id));
        return; # make above call void context
    }
}

sub html_for_page_in_workspace {
    my $self = shift;
    my $page_id        = shift;
    my $workspace_name = shift;

    my $ws = Socialtext::Workspace->new(name => $workspace_name);
    my $html;
    $self->render_in_workspace($page_id, $ws, sub {
        my $page = shift;
        $html = $page->to_html_or_default;
    });
    return $html;
}

# Grab the wikitext from a spreadsheet and put it in a page object.
# Used by BackLinksPlugin.
sub page_with_spreadsheet_wikitext {
    my $self = shift;
    my $page = shift;

    my $new = $self->hub->pages->new_from_name($page->id);
    my $wikitext = '';
    my $text = $new->content;

    # TODO: use Socialtext::Sheet
    OUTER: while (1) {
        $text =~ s/.*?\n--SocialCalcSpreadsheetControlSave\n//s
            or last; 
        $text =~ s/(.*?)\n--SocialCalcSpreadsheetControlSave\n//s;
        my $section = $1;
        my @parts = ($section =~ /part:(.*)/g);
        while (my $part = shift @parts) {
            last if $part eq 'sheet';
            $text =~ s/.*?\n--SocialCalcSpreadsheetControlSave\n//s
                or last OUTER;
        }
        $text =~ s/(.*?)\n--SocialCalcSpreadsheetControlSave\n//s;
        $section = $1 or last;
        $section =~ /^valueformat:(\d+):text-wiki$/m or last;
        my $num = $1;
        my @lines = ($section =~ /\ncell:.+?:.+?:(.*?):.*tvf:$num/g);
        $wikitext = join "\n", map {
            s/\\c/:/g;
            s/\\n/\n/g;
            s/\\t/\t/g;
            "$_\n";
        } @lines;
        last;
    }
    $new->content($wikitext);
    return $new;
}

sub By_seconds_limit {
    my $class         = shift;
    my $t             = time_scope 'By_seconds_limit';
    my %p             = @_;
    my $since         = $p{since};
    my $seconds       = $p{seconds};
    my $workspace_ids = $p{workspace_ids};
    my $workspace_id  = $p{workspace_id};
    my $offset        = $p{offset};
    my $limit         = $p{count} || $p{limit};
    my $tag           = $p{tag} || $p{category};
    my $hub           = $p{hub};
    my $type          = $p{type};
    my $order_by      = $p{order_by} || 'page.last_edit_time DESC';

    my $where;
    my @bind;
    if ( $since ) {
        $where = q{last_edit_time > ?::timestamptz};
        @bind  = ( $since );
    }
    elsif ( $seconds ) {
        $where = q{last_edit_time > 'now'::timestamptz - ?::interval};
        @bind  = ("$seconds seconds");
    }
    else {
        croak "seconds or count parameter is required";
    }

    return $class->_fetch_pages(
        hub => $hub,
        $workspace_ids ? ( workspace_ids => $workspace_ids ) : (),
        type         => $type,
        where        => $where,
        offset       => $offset,
        limit        => $limit,
        tag          => $tag,
        bind         => \@bind,
        order_by     => $order_by,
        workspace_id => $workspace_id,
        deleted_ok   => $p{deleted_ok},
    );
}

sub All_active {
    my $class        = shift;
    my $t            = time_scope 'All_active';
    my %p            = @_;
    my $hub          = $p{hub};
    my $limit        = $p{count} || $p{limit};
    my $workspace_id = $p{workspace_id};
    my $order_by     = $p{order_by};
    my $offset       = $p{offset};
    my $type         = $p{type};
    my $orphaned     = $p{orphaned} || 0;

    $limit = 500 unless defined $limit;

    return $class->_fetch_pages(
        hub          => $hub,
        limit        => $limit,
        workspace_id => $workspace_id,
        ($order_by ? (order_by => "page.$order_by") : ()),
        offset       => $offset,
        type         => $type,
        orphaned     => $orphaned,
    );
}

sub By_tag {
    my $class        = shift;
    my $t            = time_scope 'By_tag';
    my %p            = @_;
    my $hub          = $p{hub};
    my $workspace_id = $p{workspace_id};
    my $limit        = $p{count} || $p{limit};
    my $offset       = $p{offset};
    my $tag          = $p{tag};
    my $order_by     = $p{order_by} || 'page.last_edit_time DESC';
    my $type         = $p{type};

    return $class->_fetch_pages(
        hub              => $hub,
        workspace_id     => $workspace_id,
        limit            => $limit,
        offset           => $offset,
        tag              => $tag,
        order_by         => $order_by,
        type             => $type,
    );
}

sub By_id {
    my $class            = shift;
    my $t                = time_scope 'By_id';
    my %p                = @_;
    my $hub              = $p{hub};
    my $workspace_id     = $p{workspace_id};
    my $page_id          = $p{page_id};
    my $no_die           = $p{no_die};

    croak 'By_id(... revision_id=>$n) is deprecated' if $p{revision_id};

    my $where;
    my $bind;
    if (ref($page_id) eq 'ARRAY') {
        return [] unless @$page_id;

        $where = 'page_id IN (' 
            . join(',', map { '?' } @$page_id) . ')';
        $bind = $page_id;
    }
    else {
        $where = 'page_id = ?';
        $bind = [$page_id];
    }

    my $pages = $class->_fetch_pages(
        hub              => $hub,
        workspace_id     => $workspace_id,
        where            => $where,
        bind             => $bind,
        deleted_ok       => $p{deleted_ok},
    );
    unless (@$pages) {
        return if $no_die;
        my $pg_ids = join(',', (ref($page_id) ? @$page_id : ($page_id)));
        die "No page(s) found for ($workspace_id, $pg_ids)"
    }
    return @$pages == 1 ? $pages->[0] : $pages;
}

sub _fetch_pages {
    my $class = shift;
    my %p = (
        bind             => [],
        where            => '',
        deleted          => 0,
        tag              => undef,
        workspace_id     => undef,
        workspace_ids    => undef,
        order_by         => undef,
        limit            => undef,
        offset           => undef,
        deleted_ok       => undef,
        orphaned         => 0,
        @_,
    );

    my $tag       = '';
    my $more_join = '';
    if ( $p{tag} ) {
        $more_join = 'JOIN page_tag USING (page_id, workspace_id)';
        $p{where} .= ' AND ' if $p{where};
        $p{where} .= 'LOWER(page_tag.tag) = LOWER(?)';
        push @{ $p{bind} }, $p{tag};
    }

    # If ordering by a user, add the extra join and order by the display name
    if ( ($p{order_by}||'') =~ m/(creator_id|last_editor_id) (\S+)$/ ) {
        $p{order_by} = "LOWER(users.display_name) $2";
        $more_join .= " JOIN users ON (page.$1 = users.user_id)";
    }
    # If ordering by page name, make sure the order is case insensitive
    if ( ($p{order_by}||'') =~ m/page\.name(?: (\S+))?$/ ) {
        $p{order_by} = "LOWER(page.name) $1";
    }

    if ( $p{type} ) {
        $p{where} .= ' AND ' if $p{where};
        $p{where} .= 'page.page_type = ?';
        push @{ $p{bind} }, $p{type};
    }

    my $deleted = '1=1';
    unless ($p{deleted_ok}) {
        $deleted = $p{deleted} ? 'deleted' : 'NOT deleted';
    }

    my $workspace_filter = '';
    my @workspace_ids;
    if ( $p{workspace_ids} ) {
        return [] unless @{$p{workspace_ids}};

        $workspace_filter = '.workspace_id IN ('
            . join( ',', map {'?'} @{ $p{workspace_ids} } ) . ')';
        push @workspace_ids, @{ $p{workspace_ids} };
    }
    elsif (defined $p{workspace_id}) {
        $workspace_filter = '.workspace_id = ?';
        push @workspace_ids, $p{workspace_id};
    }

    if ($p{orphaned}) {
      $p{where} .= ' AND ' if $p{where};
      $p{where} .= ' not exists (select 1 from page_link where page_link.to_page_id = page.page_id and page_link.to_workspace_id = page.workspace_id)';
    }

    my $order_by = '';
    if ($p{order_by} && $p{order_by} =~ /^\S+(:? asc| desc)?$/i) {
        $order_by = "ORDER BY $p{order_by}, page.name asc";
    }

    my $limit = '';
    if ( $p{limit}  && $p{limit} != -1) {
        $limit = 'LIMIT ?';
        push @{ $p{bind} }, $p{limit};
    }

    my $offset = '';
    if ( $p{offset} && $p{offset} != -1) {
        $offset = 'OFFSET ?';
        push @{ $p{bind} }, $p{offset};
    }

    my $page_workspace_filter = $workspace_filter
                                   ? " AND page$workspace_filter"
                                   : '';
    $p{where} = "AND $p{where}" if $p{where};
    my $sth = sql_execute(qq/
    SELECT /.Socialtext::Page::SELECT_COLUMNS_STR.qq/
    FROM page 
        JOIN "Workspace" USING (workspace_id)
        $more_join
    WHERE $deleted
      $page_workspace_filter
      $p{where}
    $order_by
    $limit
    $offset
/,
        @workspace_ids,
        @{ $p{bind} },
    );

    return [
        map { Socialtext::Page->_new_from_row($_) }
        map { $_->{hub} = $p{hub}; $_ }
        @{ $sth->fetchall_arrayref( {} ) }
    ];
}

sub Minimal_by_name {
    my $class        = shift;
    my $t            = time_scope 'Minimal_by_name';
    my %p            = @_;
    my $workspace_id = $p{workspace_id};
    my $limit        = $p{limit} || '';
    my $page_filter  = $p{page_filter} or die "page_filter is mandatory!";
    # \m matches beginning of a word
    $page_filter = '\\m' . $page_filter;

    my @bind = ($workspace_id, $page_filter);

    my $and_type = '';
    if ($p{type}) {
        $and_type = 'AND page_type = ?';
        push @bind, $p{type};
    }

    if ($limit) {
        push @bind, $limit;
        $limit = "LIMIT ?";
    }

    my $sth = sql_execute(<<EOT, @bind);
SELECT * FROM (
    SELECT page_id, 
           name, 
           -- _utc suffix is to prevent performance-impacing naming collisions:
           last_edit_time AT TIME ZONE 'UTC' AS last_edit_time_utc, 
           page_type 
      FROM page
     WHERE NOT deleted
       AND workspace_id = ? 
       AND name ~* ?
       $and_type
     ORDER BY last_edit_time DESC
      $limit
) AS X ORDER BY name
EOT

    my $pages = $sth->fetchall_arrayref( {} );
    foreach my $page (@$pages) {
        $page->{last_edit_time} = delete $page->{last_edit_time_utc};
    }
    return $pages;
}

sub ChangedCount {
    my $class        = shift;
    my $t            = time_scope 'ChangedCount';
    my %p            = @_;
    my $workspace_id = $p{workspace_id} or croak "workspace_id needed";
    my $max_age      = $p{duration} or croak "duration needed";

    return sql_singlevalue(<<EOT,
SELECT count(*) FROM page
    WHERE NOT deleted
      AND workspace_id = ?
      AND last_edit_time > ('now'::timestamptz - ?::interval)
EOT
        $workspace_id, "$max_age seconds",
    );
}

sub ActiveCount {
    my ($class, %p) = @_;
    my $t  = time_scope 'ActiveCount';
    my $id = $p{workspace_id} || $p{workspace};

    return sql_singlevalue(q{
        SELECT count(*) FROM page WHERE NOT deleted AND workspace_id = ?
    }, $id);
}

sub TaggedCount {
    my ($class, %p) = @_;
    my $t = time_scope 'TaggedCount';

    return sql_singlevalue(q{
        SELECT count(*) 
          FROM page
          JOIN page_tag USING (page_id, workspace_id)
         WHERE NOT deleted AND workspace_id = ? AND tag = ?
    }, $p{workspace_id}, $p{tag});
}

################################################################################
package Socialtext::Pages::Formatter;

use base 'Socialtext::Formatter';

sub wafl_classes {
    my $self = shift;
    map {
        s/^File$/Socialtext::Pages::Formatter::File/;
        s/^Image$/Socialtext::Pages::Formatter::Image/;
        $_
    } $self->SUPER::wafl_classes(@_);
}

################################################################################
package Socialtext::Pages::Formatter::Image;

use Socialtext::Formatter::WaflPhrase;
use base 'Socialtext::Formatter::Image';

sub html {
    my $self = shift;
    my ($workspace_name, $page_title, $image_name, $page_id, $page_uri) = 
      $self->parse_wafl_reference;
    return $self->syntax_error unless $image_name;
    return qq{<img src="cid:$image_name" />};
}

################################################################################
package Socialtext::Pages::Formatter::File;

use Socialtext::Formatter::WaflPhrase;
use base 'Socialtext::Formatter::File';

sub html {
    my $self = shift;
    my (undef, undef, $file_name) = $self->parse_wafl_reference;
    my $link = $self->SUPER::html(@_);
    $link =~ s/ target="_blank"//;
    $link =~ s/ href="[^"]+"/ href="cid:$file_name"/i;
    return $link;
}

1;

