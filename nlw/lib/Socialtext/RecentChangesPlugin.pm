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
    $registry->add(preference => $self->changes_depth);
    $registry->add(preference => $self->include_in_pages);
    $registry->add(preference => $self->sidebox_changes_depth);
    $registry->add(wafl => 'recent_changes' => 'Socialtext::RecentChanges::Wafl' );
    $registry->add(
        wafl => 'recent_changes_full' => 'Socialtext::RecentChanges::Wafl' );
}

sub changes_depth {
    my $self = shift;
    my $p = $self->new_preference('changes_depth');
    $p->query(__('config.changes-depth?'));
    $p->type('pulldown');
    my $choices = [
        1 => __('last.24hours'),
        2 => __('last.2days'),
        3 => __('last.3days'),
        7 => __('last.week'),
        14 => __('last.2weeks'),
        31 => __('last.month'),
    ];
    $p->choices($choices);
    $p->default(7);
    return $p;
}

sub sidebox_changes_depth {
    my $self = shift;
    my $p = $self->new_preference('sidebox_changes_depth');
    $p->query(__('wiki.sidebox-number-of-changes?'));
    $p->type('pulldown');
    my $choices = [
        2 => 2, 4 => 4, 6 => 6, 8 => 8, 10 => 10, 15 => 15, 20 => 20
    ];
    $p->choices($choices);
    $p->default(4);
    return $p;
}

sub include_in_pages {
    my $self = shift;
    my $p = $self->new_preference('include_in_pages');
    $p->query(__('wiki.show-sidebox?'));
    $p->type('boolean');
    $p->default(0);
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
        unplug_uri    => "?action=unplug",
        unplug_phrase => loc('info.unplug-recent=count', $self->hub->tiddly->default_count),
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

