# @COPYRIGHT@
package Socialtext::SearchPlugin;
use strict;
use warnings;

use base 'Socialtext::Query::Plugin';

use Class::Field qw( const field );
use Socialtext::Search qw( search_on_behalf );
use Socialtext::Search::AbstractFactory;
use Socialtext::Workspace;
use Socialtext::l10n qw(loc __);
use Socialtext::Log qw( st_log );
use Socialtext::Timer;
use Socialtext::Pageset;
use Socialtext::String;

const class_id => 'search';
const pref_scope => 'none';
const class_title => __('class.search');
const cgi_class => 'Socialtext::Search::CGI';

const sortdir => {
    Relevance      => 'desc',
    Summary        => 'asc',
    Subject        => 'asc',
    Workspace      => 'asc',
    Date           => 'desc',
    create_time    => 'desc',
    revision_count => 'desc',
    username       => 'asc',
    creator        => 'asc',
};

field 'category_search';
field 'title_search';

=head1 DESCRIPTION

This module acts as an adaptor between the Socialtext::Query::Plugin and associated
template interfaces and the Socialtext::Search index/search abstractions.

This keeps our old search-type URLs and templates working with any search
index that implements the interfaces in the Socialtext::Search namespace.

=cut

sub register {
    my $self = shift;
    $self->SUPER::register(@_);
    my $registry = shift;
    $registry->add( wafl => search => 'Socialtext::Search::Wafl' );
    $registry->add( wafl => search_full => 'Socialtext::Search::Wafl' );
    $registry->add( preference => $self->default_search_order_pref );
    $registry->add( preference => $self->show_summaries_pref );
    $registry->add( preference => $self->direction_pref );
    $registry->add( action => 'search_workspace' );
    $registry->add( action => 'search_workspaces' );
}

# Wrappers around search() so we can use actions to determine scope rather
# than passing the scope parameter
sub search_workspace { $_[0]->search('_') }
sub search_workspaces { $_[0]->search('*') }

# These preference is updated whenever you change your sorting. It does not
# have a settings page like most other workspace preferences.
sub default_search_order_pref {
    my $self = shift;
    my $p = $self->new_preference('default_search_order');
    $p->type('pulldown');

    $p->choices( [
        map { $_ => $_ } keys %{ $self->sortdir }
    ] );
    $p->default('Relevance');
    return $p;
}

sub show_summaries_pref {
    my $self = shift;
    my $p = $self->new_preference('show_summaries');
    $p->type('boolean');
    $p->default(1);
    return $p;
}

sub direction_pref {
    my $self = shift;
    my $p = $self->new_preference('direction');
    $p->type('pulldown');
    $p->choices( [qw/asc desc/] );
    $p->default('desc');
    return $p;
}

sub search {
    my $self = shift;
    my $scope = shift || $self->cgi->scope || '_';
    my $timer = Socialtext::Timer->new;
    my $index = $self->cgi->index;
    my $search_factory = Socialtext::Search::AbstractFactory->GetFactory();

    if (my $cgi_sortby = $self->cgi->sortby) {
        if (my $default_dir = $self->sortdir->{$cgi_sortby}) {
            my $direction = $self->cgi->direction || $default_dir;
            $self->_store_preferences(
                default_search_order => $cgi_sortby,
                direction => $direction,
            );
            $self->sortby($cgi_sortby);
        }
    }
    else {
        $self->sortby($self->preferences->default_search_order->value);
    }

    my $search_term;

    if ($self->cgi->defined('search_term')) {
        $search_term = $self->cgi->search_term;
        $self->dont_use_cached_result_set();
    }
    elsif ($self->cgi->defined('orig_search_term')) {
        $search_term = $self->cgi->orig_search_term;
    }
    else {
        die "no search term?!";
    }

    my %template_args = (
        scope => $scope,
        search_term  => $self->uri_escape($search_term),
        html_escaped_search_term =>
            Socialtext::String::html_escape($search_term),
        $search_factory->template_vars(),
    );

    # Solr returns a partial set of results, so we never want the cached
    # search results.
    $self->dont_use_cached_result_set if $template_args{partial_set};

    $self->hub->log->debug("performing search for $search_term");

    # load the search result which may or may not be cached.
    $self->result_set(
        $self->get_result_set(
            search_term => $search_term,
            scope       => $scope,

            # Solr searches are already sorted
            pre_sorted  => $template_args{partial_set},
        )
    );

    if ($self->result_set->{too_many}) {
        $self->screen_template('view/listview');
        return $self->render_screen(
            %template_args,
            too_many => $self->result_set->{hits},
            error_message => 'Too many results!',
        );
    }

    $self->display_results($self->sortdir,
        %template_args,
        sortby => $self->sortby,
        allow_relevance => 1,
        show_workspace =>
            ( ($scope ne '_') || ($search_term =~ /\bworkspaces:\S+/) || 0 ),
        feeds => $self->_feeds(
            $self->hub->current_workspace, 
            search_term => $search_term,
            scope => $scope,
        ),
        title => loc('search.results'),
        unplug_uri => "?action=unplug;search_term=$template_args{search_term}",
        unplug_phrase =>
            loc('info.unplug-search'),
        Socialtext::Pageset->new(
            cgi => {$self->cgi->all},
            total_entries => $self->result_set->{hits},
        )->template_vars(),
    );
}

sub _feeds {
    my $self      = shift;
    my $workspace = shift;
    my %query     = @_;

    my $uri_escaped_query  = $self->uri_escape($query{search_term});
    my $scope = $query{scope};

    my $root  = $self->hub->syndicate->feed_uri_root($workspace);
    # REVIEW: Even though these are not page feeds, they are called
    # page because the template share/template/view/listview looks
    # for rss.page.url to display a feed on the page.
    my %feeds = (
        rss => {
            page => {
                title => loc('search.rss=wiki,query', $workspace->title, $query{search_term})
,
                url => $root . "?search_term=$uri_escaped_query;scope=$scope",
            },
        },
        atom => {
            page => {
                title => loc('search.atom=wiki,query', $workspace->title, $query{search_term}),
                url => $root . "?search_term=$uri_escaped_query;scope=$scope;type=Atom",
            },
        },
    );

    return \%feeds;
}

sub search_for_term {
    my ( $self, %query )  = @_;
    my $search_term = $query{search_term};
    my $scope = $query{scope} || '_';
    $self->{_current_search_term} = $search_term;
    $self->{_current_scope} = $scope;
    $self->hub->log->debug("searchquery '" . $search_term . "'");

    Socialtext::Timer->Continue('search_for_term');
    $self->result_set($self->new_result_set);
    my $result_set = $self->result_set;
    eval {
        my ($rows, $hit_count) = $self->_new_search(%query);
        $self->title_search(1) if $search_term =~ m/^(?:=|title:)/;
        $self->hub->log->debug("hitcount " . scalar @$rows);
        foreach my $row (@$rows) {
            $self->hub->log->debug("hitrow $row->{page_uri}")
                if exists $row->{page_uri};
            $self->hub->log->debug("hitkeys @{[keys %$row]}");
        }

        $result_set->{hits} = $hit_count;
        $result_set->{rows} = $rows;

        $search_term =~ s/=(\S+|"[^"]+")/title:$1/g;
        $result_set->{display_title} = 
            loc("search.pages=query", $search_term);
        $result_set->{predicate} = 'action=search';

        $self->write_result_set;
    };
    if ($@) {
        if ($@ =~ /malformed query/) {
            $self->error_message($self->template_process(
                    'search_help_field.html',
                )
            );
        } elsif ($@->isa('Socialtext::Exception::NoSuchResource')) {
            $self->error_message(
                  "You tried to search on the workspace named '"
                . $@->name
                . "', which does not exist." );
        } elsif ($@->isa('Socialtext::Exception::Auth')) {
            # FIXME: It would be better to show the name of the workspace
            # they're not authorized to see. -mml 20070504
            $self->error_message(
                  "You are not authorized to perform the requested search." );
        } elsif ($@->isa('Socialtext::Exception::SearchTimeout')) {
            $result_set->{hits} = 0;
            $result_set->{search_term} = $search_term;
            $result_set->{scope} = $scope;
            $result_set->{search_timeout} = 1;
        } else {
            $self->hub->log->warning("searchdie '$@'");
        }
    }
    Socialtext::Timer->Pause('search_for_term');
}

sub _new_search {
    my ( $self, %query ) = @_;

    my $sortby = $self->sortby || $self->cgi->sortby || 'Date';
    my $direction = $self->_direction || $self->sortdir->{$sortby};

    Socialtext::Timer->Continue('search_on_behalf');
    $self->{_current_search_term} = $query{search_term};
    $self->{_current_scope} = $query{scope} || '_';
    my $offset = defined($query{offset}) ? $query{offset} : $self->cgi->offset;

    my ($hits, $hit_count) = search_on_behalf(
        $self->hub->current_workspace->name,
        $query{search_term},
        $query{scope},
        $self->hub->current_user,
        sub { },    # FIXME: We'd rather message the user than ignore these.
        sub { },    # FIXME: We'd rather message the user than ignore these.
        offset => $offset || 0,
        order => $sortby,
        direction => $direction,
        limit => $query{limit},
    );
    Socialtext::Timer->Pause('search_on_behalf');

    eval { $self->_load_pages_for_hits($hits) };
    warn $@ if $@;

    my %cache;
    my @results;
    Socialtext::Timer->Continue('hitrows');
    for my $hit (@$hits) {
        my $key = $hit->composed_key;
        next if $cache{$key};
        my $row = $self->_make_row($hit);

        # Only add non-empty rows to the result_set.
        if (defined $row and keys %$row) {
            $cache{$key}++;
            push @results, $row;
        }
    }
    Socialtext::Timer->Pause('hitrows');

    return \@results, $hit_count;
}

sub get_result_set {
    my ( $self, %query ) = @_;
    my %sortdir = %{$self->sortdir};
    
    $self->{_current_search_term} = $query{search_term};
    $self->{_current_scope} = $query{scope};
    $self->{_current_limit} = $query{limit};
    $self->{_current_offset} = $query{offset};
    if (!$self->{_current_search_term}) {
        $self->result_set($self->new_result_set());
    }
    else {
        $self->result_set($self->read_result_set());
    }
    return $self->result_set if $query{pre_sorted};
    return $self->sorted_result_set(\%sortdir);
}

sub default_result_set {
    my $self = shift;
    die "default_result_set called without a _current_search_term"
        unless $self->{_current_search_term};
    $self->search_for_term(
        search_term => $self->{_current_search_term},
        scope => $self->{_current_scope},
        limit => $self->{_current_limit},
        offset => $self->{_current_offset},
    );
    return $self->result_set;
}

sub read_result_set {
    my $self = shift;

    # try to get the cached result
    my $result_set = $self->SUPER::read_result_set(@_);

    # if we get one, make sure it's for the right search
    if ($result_set and
        defined($result_set->{search_term}) and
        $result_set->{search_term} eq $self->{_current_search_term} and
        defined($result_set->{scope}) and
        defined($self->{_current_scope}) and
        $result_set->{scope} eq $self->{_current_scope})
    {
        return $result_set;
    }
    else {
        # should do a new search
        return $self->default_result_set;
    }
}

sub write_result_set {
    my $self = shift;
    $self->result_set->{search_term} = $self->{_current_search_term};
    $self->result_set->{scope} = $self->{_current_scope};
    eval { $self->SUPER::write_result_set(@_); };
    if ($@) {
        unless ( $@ =~ /lock_store.al/ ) {
            die $@;
        }
        undef($@);
    }
}

sub show_summaries {
    my $self = shift;

    if (defined(my $cgi_summary = $self->cgi->summaries)) {
        if ($cgi_summary ne '') {
            $self->_store_preferences( show_summaries => $cgi_summary );
            return $cgi_summary;
        }
    }
    return $self->preferences->show_summaries->value;
}

sub _store_preferences {
    my $self = shift;
    my %p = @_;

    my %opts = (
        show_summaries => $p{show_summaries},
        default_search_order => $p{default_search_order}
                || $self->preferences->default_search_order->value,
        direction => $p{direction} || $self->cgi->direction
                || $self->preferences->direction->value,
    );
    $opts{show_summaries} = $self->preferences->show_summaries->value
        unless defined $opts{show_summaries};

    my $user = $self->hub->current_user;
    $self->preferences->store( $user, $self->class_id, \%opts );
    $self->hub->preferences_object(
        $self->preferences->new_for_user($user),
    );
}

package Socialtext::Search::CGI;

use base 'Socialtext::Query::CGI';
use Socialtext::CGI qw( cgi );

cgi search_term => '-html_clean';
cgi orig_search_term => '-html_clean';
cgi 'offset';
cgi 'limit';
cgi 'index';

######################################################################
package Socialtext::Search::Wafl;

use base 'Socialtext::Query::Wafl';
use Socialtext::l10n qw(loc);

sub _set_titles {
    my $self = shift;
    my $arguments = shift;
    my $title_info;
    if ( $self->target_workspace ne $self->current_workspace_name ) {
        $title_info = loc('search.for=query,wiki', $arguments, $self->target_workspace);
    } else {
        $title_info = loc('search.for=query', $arguments);
    }
    $self->wafl_query_title($title_info);
    $self->wafl_query_link($self->_set_query_link($arguments));
}

sub _set_query_link {
    my $self = shift;
    my $arguments = shift;
    return $self->hub->viewer->link_dictionary->format_link(
        link => 'search_query',
        workspace => $self->target_workspace,
        search_term => $self->uri_escape($arguments),
    );
}

sub _get_wafl_data {
    my $self = shift;
    my $hub            = shift;
    my $query          = shift;
    my $workspace_name = shift;
    my $main;

    $hub = $self->hub_for_workspace_name( $workspace_name );

    # This is important so that we only see results that the current user is
    # authorized to see (and we see all such results).
    $hub->current_user($self->hub->current_user);

    $hub->search->get_result_set( search_term => $query, limit => 10000 );
}

sub _format_results {
    my ( $self, $results, $separator, $wafl ) = @_;

    my $rows = $results->{rows};

    my $wikitext = $separator . join( $separator,
        map {
            "{$wafl "
                . (
                  $self->hub->current_workspace->name ne $_->{workspace_name}
                ? $_->{workspace_name}
                : '' )
                . " ["
                . $_->{Subject} . ']}'
            } @$rows
    );

    return $self->hub->viewer->text_to_html($wikitext. "\n\n");
}

1;
