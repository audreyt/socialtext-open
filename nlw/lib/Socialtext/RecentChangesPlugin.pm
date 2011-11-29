# @COPYRIGHT@
package Socialtext::RecentChangesPlugin;
use Socialtext::CategoryPlugin;
use Socialtext::l10n qw(loc __);
use Socialtext::Timer qw/time_scope/;
use Socialtext::Pages;
use Socialtext::Pageset;
use strict;
use warnings;

use base 'Socialtext::Query::Plugin';

use Class::Field qw( const );
use Socialtext::l10n qw(loc __);
use List::Util qw/min/;

const class_id => 'recent_changes';
const class_title      => __('class.recent_changes');
const cgi_class        => 'Socialtext::RecentChanges::CGI';
const default_category => 'recent changes';

sub register {
    my $self = shift;
    $self->SUPER::register(@_);
    my $registry = shift;
    $registry->add(action => 'changes'); # used for displaying all
    $registry->add(action => 'recent_changes_html');
    $registry->add(wafl => 'recent_changes' => 'Socialtext::RecentChanges::Wafl' );
    $registry->add(
        wafl => 'recent_changes_full' => 'Socialtext::RecentChanges::Wafl' );

    $self->_register_prefs($registry);
}

sub pref_names {
    return qw(changes_depth include_in_pages sidebox_changes_depth);
}

sub changes_depth_data {
    my $self = shift;

    return {
        title => loc('wiki.timeframe-for-changes'),
        default_setting => 7,
        options => [
            {setting => 1, display => __('last.24hours')},
            {setting => 2, display => __('last.2days')},
            {setting => 3, display => __('last.3days')},
            {setting => 7, display => __('last.week')},
            {setting => 14, display => __('last.2weeks')},
            {setting => 31, display => __('last.month')},
        ],
    };
}

sub changes_depth {
    my $self = shift;

    my $data = $self->changes_depth_data;
    my $p = $self->new_preference('changes_depth');

    $p->query($data->{title});
    $p->type('pulldown');
    $p->choices($self->_choices($data));
    $p->default($data->{default_setting});

    return $p;
}

sub sidebox_changes_depth_data {
    my $self = shift;

    return {
        title => loc('settings.number-of-items-to-show'),
        default_setting => 4,
        depends_on => 'include_in_pages',
        options => [
            map { {setting => $_, display => $_ } } qw(2 4 6 7 10 15 20)
        ],
    };
}

sub sidebox_changes_depth {
    my $self = shift;

    my $data = $self->sidebox_changes_depth_data;
    my $p = $self->new_preference('sidebox_changes_depth');

    $p->query($data->{title});
    $p->type('pulldown');
    $p->choices($self->_choices($data));
    $p->default($data->{default_setting});

    return $p;
}

sub include_in_pages_data {
    my $self = shift;

    return {
        title => loc("wiki.recent-changes-sidebar-widget"),
        binary => 1,
        default_setting => 0,
        options => [
            {setting => '1', display => loc('do.enabled')},
            {setting => '0', display => loc('do.disabled')},
        ],
    };
}

sub include_in_pages {
    my $self = shift;

    my $data = $self->include_in_pages_data;
    my $p = $self->new_preference('include_in_pages');

    $p->query($data->{title});
    $p->type('boolean');
    $p->default($data->{default_setting});

    return $p;
}


*changes = \&recent_changes;
sub recent_changes {
    my $self = shift;

    if ( $self->cgi->changes =~ /\// ) {
        Socialtext::Exception::DataValidation->throw(
            errors => [loc("error.invalid-/-in-changes")] );
    }

    if ($self->cgi->changes eq 'all') {
        $self->result_set->{predicate} = "action=changes;changes=all";
    }

    $self->dont_use_cached_result_set();
    $self->display_results(
        $self->sortdir,
        miki_url      => $self->hub->helpers->miki_path('recent_changes_query'),
        feeds         => $self->_feeds( $self->hub->current_workspace ),
        Socialtext::Pageset->new(
            cgi => {$self->cgi->all},
            total_entries => $self->result_set->{hits},
        )->template_vars(),
    );
}

sub _feeds {
    my $self = shift;
    my $workspace = shift;

    my $feeds = $self->SUPER::_feeds($workspace);
    $feeds->{rss}->{page} = {
        title => $feeds->{rss}->{changes}->{title},
        url => $feeds->{rss}->{changes}->{url},
    };
    $feeds->{atom}->{page} = {
        title => $feeds->{atom}->{changes}->{title},
        url => $feeds->{atom}->{changes}->{url},
    };

    return $feeds;
}


sub recent_changes_html {
    my $self = shift;
    my $count = $self->preferences->sidebox_changes_depth->value;
    Socialtext::Timer->Continue('get_recent_changes');
    my $changes = $self->get_recent_changes_in_category(count => $count);
    Socialtext::Timer->Pause('get_recent_changes');
    $self->template_process('recent_changes_box_filled.html',
        %$changes,
    );
}

sub get_recent_changes_in_category {
    my $self = shift;
    my %p = @_;
    $self->new_changes( %p );
    return $self->result_set;
}

sub new_changes {
    my $self = shift;
    my %p = @_;
    my $type = $p{type} || '';
    my $count = $p{count};
    my $category = $p{category};

    Socialtext::Timer->Continue('RCP_new_changes');
    $self->result_set($self->new_result_set($type));

    my $limit = $count || $self->cgi->limit || Socialtext::Pageset::PAGE_SIZE;
    $limit = min($limit, Socialtext::Pageset::MAX_PAGE_SIZE);
    my $offset = $self->cgi->offset || 0;
    my $order_by = $self->ui_sort_to_order_by();

    my $ws_id = $self->hub->current_workspace->workspace_id;
    my %args = (
        hub => $self->hub,
        workspace_id => $ws_id,
        do_not_need_tags => 1,
        limit => $limit,
        offset => $offset,
        order_by => $order_by,
    );
    my $pages_ref;
    if ($category) {
        $pages_ref = Socialtext::Pages->By_tag(%args, tag => $category);
    }
    else {
        $pages_ref = Socialtext::Pages->All_active(%args);
    }

    my $total = Socialtext::Pages->ActiveCount(workspace => $ws_id);
    my $changed_total = $self->count_by_seconds_limit();

    my $display_title;
    if (defined $type && $type eq 'all') {
        $display_title = loc("page.all");
    }
    else {
        my $depth = $self->preferences->changes_depth;
        my $last_changes_time = loc($depth->value_label);
        $display_title = loc('page.changes=time,changed,total', $last_changes_time, $changed_total, $total);
    }

    Socialtext::Timer->Continue('new_changes_push_result');
    local $Socialtext::Page::No_result_times = 1;
    for my $page (@$pages_ref) {
        $self->push_result($page);
    }
    Socialtext::Timer->Pause('new_changes_push_result');

    $self->result_set->{hits} = $total;
    $self->result_set->{display_title} = $display_title;
    $self->result_set->{partial_set} = 1;
    Socialtext::Timer->Pause('RCP_new_changes');
}

sub by_seconds_limit {
    my $self = shift;
    my %args = @_;
    $args{workspace_id} ||= $self->hub->current_workspace->workspace_id;

    my $prefs = $self->hub->recent_changes->preferences;
    my $seconds = $prefs->changes_depth->value * 1440 * 60;
    my $pages = Socialtext::Pages->By_seconds_limit(
        seconds          => $seconds,
        hub              => $self->hub,
        count            => $self->preferences->sidebox_changes_depth->value,
        do_not_need_tags => 1,
        %args,
    );
    return $pages;
}

sub count_by_seconds_limit {
    my $self = shift;
    my $t = time_scope 'count_by_seconds';

    my $prefs = $self->hub->recent_changes->preferences;
    my $seconds = $prefs->changes_depth->value * 1440 * 60;
    return Socialtext::Pages->ChangedCount(
        duration    => $seconds,
        workspace_id => $self->hub->current_workspace->workspace_id,
    );
}

sub new_result_set {
    my $self = shift;
    my $type = shift || '';
    return +{
        rows => [],
        hits => 0,
        display_title => '',
        predicate => 'action=' . $self->class_id . ';changes=' . $type,
    }
}

sub default_result_set {
    my $self = shift;
    $self->new_changes( type => $self->cgi->changes || '' );
    return $self->result_set;
}

######################################################################
package Socialtext::RecentChanges::CGI;

use base 'Socialtext::Query::CGI';
use Socialtext::CGI qw( cgi );

cgi 'changes';
cgi 'offset';
cgi 'limit';
cgi 'sortby';

######################################################################
package Socialtext::RecentChanges::Wafl;

use Socialtext::CategoryPlugin;
use base 'Socialtext::Category::Wafl';
use Socialtext::l10n qw(loc __);

sub _set_titles {
    my $self = shift;
    my $title_info;;
    if ($self->target_workspace ne $self->current_workspace_name) {
        $title_info = loc("nav.news=wiki", $self->target_workspace);
    } else {
        $title_info = loc("nav.news");
    }
    $self->wafl_query_title($title_info);
    $self->wafl_query_link($self->_set_query_link);
}

sub _set_query_link {
    my $self = shift;
    my $arguments = shift;
    return $self->hub->viewer->link_dictionary->format_link(
        link => 'recent_changes_query',
        workspace => $self->target_workspace,
    );
}

sub _parse_arguments {
    my $self = shift;
    my $arguments = shift;

    $arguments =~ s/^\s*<//;
    $arguments =~ s/>\s*$//;

    my $workspace_name = $arguments;
    $workspace_name = $self->current_workspace_name unless $workspace_name;
    return ( $workspace_name, undef );
}

1;

