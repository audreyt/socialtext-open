package Socialtext::Search::Solr::Searcher;
# @COPYRIGHT@
use Moose;
use MooseX::AttributeInflate;
use Socialtext::Log qw(st_log);
use Socialtext::Timer qw/time_scope/;
use Socialtext::Search::AbstractFactory;
use Socialtext::Search::Solr::QueryParser;
use Socialtext::Search::SimpleAttachmentHit;
use Socialtext::Search::SimplePageHit;
use Socialtext::Search::SignalHit;
use Socialtext::Search::PersonHit;
use Socialtext::Search::GroupHit;
use Socialtext::Search::Utils;
use Socialtext::AppConfig;
use Socialtext::Exceptions;
use Socialtext::Workspace;
use Socialtext::JSON qw/decode_json encode_json/;
use WebService::Solr;
use namespace::clean -except => 'meta';
use Guard;

=head1 NAME

Socialtext::Search::Solr::Searcher

=head1 SYNOPSIS

  my $s = Socialtext::Search::Solr::Factory->create_searcher($workspace_name);
  $s->search(...);

=head1 DESCRIPTION

Search the solr index.

=cut

extends 'Socialtext::Search::Searcher';
extends 'Socialtext::Search::Solr';

has '_default_rows' => (is => 'ro', isa => 'Num', default => 20);

has_inflated 'query_parser' =>
    (is => 'ro', isa => 'Socialtext::Search::Solr::QueryParser',
     handles => [qw/parse/]);

my %DocTypeToFieldBoost = (
    '' => 'title^3 tag^1.25',
    page => 'title^3 tag^1.25',
    attachment => 'filename^1',
    signal => 'body^0.2 link^0.1 tag^2 filename^0.375',
    person => 'name_pf_t^2 sounds_like^0.5 *_pf_rt^0.1 tag^0.3',
);

# Use a negative-boosting bq to mod down attachment's relative score
# when it's matched along with other doctypes.
my %DocTypeToBoostQuery = (
    '' => "(*:* -doctype:attachment)^25",              # 50 * ((  1/0.8)-1)
    'signal' => "(*:* -doctype:signal_attachment)^50", # 100 * ((1.2/0.8)-1)
);

# Perform a search and return the results.
sub search {
    my $self = shift;
    my ($thunk, $num_hits) = $self->begin_search(@_);
    return @{ $thunk->() || [] };
}

# Start a search, but don't process the results.  Return a thunk and a number
# of hits.  The thunk returns an arrayref of processed results.
sub begin_search {
    my ( $self, $query_string, $authorizer, $workspaces, %opts ) = @_;
    my $name = $workspaces ? join(',', @$workspaces) : $self->ws_name;
    $name ||= $opts{doctype} || 'unknown';

    my ($docs, $num_hits)
        = $self->_search($query_string, undef, $workspaces, %opts);

    my $thunk = sub {
        _debug("Processing $name thunk");
        my $t = time_scope('solr_begin');
        my $results = $self->_process_docs($docs);
        return $results;
    };
    return ($thunk, $num_hits);
}

# Parses the query string and returns the raw Solr hit results.
sub _search {
    my ( $self, $raw_query_string, $authorizer, $workspaces, %opts) = @_;
    $opts{limit}   ||= $self->_default_rows;
    $opts{timeout} ||= Socialtext::AppConfig->search_time_threshold();

    my @account_ids;
    if ($opts{account_ids}) {
        @account_ids = @{ $opts{account_ids} };
    }
    elsif ($opts{viewer}) {
        @account_ids = $opts{viewer}->accounts(ids_only => 1);
    }

    my $group_ids;
    if ($opts{group_ids}) {
        $group_ids = $opts{group_ids};
    }
    elsif ($opts{viewer}) {
        $group_ids = [$opts{viewer}->groups(ids_only => 1)->all];
    }

    my $query_string = lc $raw_query_string;
    $query_string =~ s/\b(and|or|not)\b/uc($1)/ge;
    $query_string =~ s/\[([^\]]+)\]/'[' . uc($1) . ']'/ge;

    my $query = $self->parse($query_string, \@account_ids, %opts);
    return ([], 0) if $query =~ m/^(?:\*|\?)/;
    $self->_authorize( $query, $authorizer );

    my @filter_query;
    my $field_boosts;
    my $boost_query;

    # No $opts{doctype} indicates workspace search (legacy, could be changed)
    if ($workspaces and @$workspaces) {
        # Pages and attachments in my workspaces.
        push @filter_query, "(doctype:attachment OR doctype:page) AND ("
              . join(' OR ', map { "w:$_" }
                sort { $a <=> $b }
                map { Socialtext::Workspace->new(name => $_)->workspace_id }
                    @$workspaces) . ")";
        $field_boosts = $DocTypeToFieldBoost{''}; # default = attachment + page
        $boost_query = $DocTypeToBoostQuery{''};
    }
    elsif ($opts{doctype}) {
        $field_boosts = $DocTypeToFieldBoost{$opts{doctype}};
        $boost_query = $DocTypeToBoostQuery{$opts{doctype}};

        if ($opts{doctype} eq 'signal') {
            push @filter_query, "(doctype:signal OR doctype:signal_attachment)";
        }
        elsif ($opts{doctype} eq 'attachment') {
            die "attachments need a workspace" unless $self->ws_name;
            my $ws_id = Socialtext::Workspace->new(
                name => $self->ws_name)->workspace_id;

            my @filter = ("doctype:$opts{doctype}", "w:$ws_id");
            push @filter, "page_key:${ws_id}__$opts{page_id}"
                if $opts{page_id};

            push @filter_query, join(" AND ", @filter);
        }
        else {
            push @filter_query, "doctype:$opts{doctype}";
        }

        if ($opts{viewer}) {
            # Only from accounts and groups the viewer has a connection to
            my $nets = join(' OR ',
                ($opts{doctype} ne 'group'
                    ? (map {"a:$_"} @account_ids)
                    : ()),
                (map { "g:$_" } @$group_ids),
            );
            $filter_query[$#filter_query] .= " AND ($nets)";

            if ($opts{doctype} eq 'signal') {
                # Find my public signals and private ones I sent or received
                my $viewer_id = $opts{viewer}->user_id;
                push @filter_query, "pvt:0 OR (pvt:1 AND "
                        . "(dm_recip:$viewer_id OR creator:$viewer_id))";
            }
        }
    }

    # See: http://wiki.apache.org/solr/CommonQueryParameters
    my $query_type = 'dismax';
    $query_type = 'standard' if $query =~ m/\b[a-z_]+:/i;
    $query_type = 'standard' if $query =~ m/\*|\?/;
    $query_type = 'standard' if $query =~ m/\band\b/i or $query =~ m/\bor\b/i;

    # Turn "tag:" search with non-word chars into "tag_exact:", as it's
    # unlikely for them to match under normal "tag:" semantics.
    my $punct = "*?()";
    $query =~ s{\btag:"\s*([^\"$punct]*[^\"[:alnum:]$punct][^\"$punct]*?)\s*"}{tag_exact:"$1"}g;
    $query =~ s{\btag:(?!")([^\s$punct]*[^[:alnum:]\s$punct][^\s$punct]*)}{tag_exact:$1}g;

    # {bz: 4545}: Escape : and \ in quoted strings used for tag_exact queries.
    $query =~ s{\b(tag_exact):"\s*([^\"$punct]*[\\:][^\"$punct]*?)\s*"}{
        my ($field, $quoted) = ($1, $2);
        $quoted =~ s/([\\:])/\\$1/g;
        qq[$field:"$quoted"];
    }eg;

    my @sort = $self->_sort_opts($opts{order}, $opts{direction}, $query_type);
    my $query_hash = {
        # fl = Fields to return
        fl => 'id score doctype',

        # qt = Query Type
        qt => $query_type,

        # qf = Query Fields (Boost)
        ($field_boosts ? (qf => "$field_boosts all") : ()),

        # pf = Phrase Fields (Boost)
        ($field_boosts ? (pf => "$field_boosts all") : ()),

        # bq = Boosting Query
        ($boost_query ? (bq => $boost_query) : ()),

        # mm = Minimum words that must match in a multi-word "dismax" query.
        # The default is 100% (all words must match), but we relax this to
        # 1 (any word matches) for compatibility with multi-word "standard"
        # queries, which is used for words like "field:value" and "prefix*"
        mm => 1,

        # [1 TO *] style range queries result in a
        # org.apache.lucene.search.BooleanQuery$TooManyClauses exception to be
        # thrown. This is fixed by disabling the Highlighter in these cases.
        $query =~ /:\[[^]]+ TO \*\]/
            ? ('hl.usePhraseHighlighter' => 'false') : (),

        # fq = Filter Query - superset of docs to return from
        (@filter_query ? (fq => \@filter_query) : ()),
        rows        => $opts{limit},
        start       => $opts{offset} || 0,
        timeAllowed => $opts{timeout},
        @sort,
    };

    my $t = Socialtext::Timer->new();
    my $num_hits = 0;
    scope_guard {
        # Move this to ST::Timer?
        my $name = 'solr_raw';
        my $elapsed = $t->elapsed();
        $Socialtext::Timer::Timings->{$name}->{how_many}++;
        $Socialtext::Timer::Timings->{$name}->{timer} += $elapsed;

        my $json_data = encode_json({
            timer      => sprintf('%0.03f', $elapsed),
            raw_query  => $raw_query_string,
            hits       => $num_hits,
            solr_query => {
                map { $_ => $query_hash->{$_} } qw/sort qt q fq qf bq start/
            },
        });

        st_log->info('SEARCH,SOLR,'
            .'ACTOR_ID:'. ($opts{viewer} ? $opts{viewer}->user_id : '0') .','
            .$json_data
        );
    };
    my $response = $self->solr->search($query, $query_hash);

    my $resp_headers = eval { $response->content->{responseHeader} };
    if ($@) {
        warn $@;
        _debug("Search response error: $@");
        return ([], 0);
    }

    if ($resp_headers->{partialResults}) {
        Socialtext::Exception::SearchTimeout->throw();
    }

    my $docs = $response->docs;
    $num_hits = $response->pager->total_entries();

    return ($docs, $num_hits);
}

sub _sort_opts {
    my $self       = shift;
    my $order      = lc(shift || '');
    my $direction  = shift;
    my $query_type = shift;

    # Map the UI options into Solr fields
    my %sortable = (
        relevance      => 'score',
        date           => 'date',
        subject        => 'plain_title',
        revision_count => 'revisions',
        create_time    => 'created',
        workspace      => 'w_title',
        sender         => 'creator_name',
        name           => 'name_asort',
        title          => 'plain_title',
    );
    my %default_dir = (
        title => 'asc',
        workspace => 'asc',
        sender => 'asc',
        name => 'asc',
        subject => 'asc',
    );

    # Sugar for Signals search
    if ($order eq 'newest') {
        $order = 'date'; $direction = 'desc';
    }
    elsif ($order eq 'oldest') {
        $order = 'date'; $direction = 'asc';
    }
    # Sugar for Workspace Pages search
    elsif ($order eq 'alpha') {
        $order = 'title';
    }

    # If no valid sort order is supplied, then we use either a date sort or a
    # score sort.
    return ('sort' => $query_type eq 'standard' ? 'date desc' : 'score desc')
        unless $sortable{$order};

    $direction ||= $default_dir{$order} || 'desc';

    # If a valid sort order is supplied, then we secondary sort by date,
    # unless the primary sort is already date, in which case we tie-break
    # by ID to accomodate sub-second differences in Signals.
    # For {bz: 5372}, we also need to sort by has_likes so that all the
    # pages that have never been liked show up lower than ones that have been
    # liked
    my $sec_sort = $order eq 'date'
        ? "id $direction"
        : $order eq 'likes'
            ? "like_count $direction, date desc, id desc"
            : 'date desc, id desc';
    return ('sort' => "$sortable{$order} $direction, $sec_sort");
}

# Either do nothing if the query's authorized, or throw NoSuchResource or
# Auth.
sub _authorize {
    my ( $self, $query, $authorizer ) = @_;
    return unless defined $authorizer;

    unless ($authorizer->( $self->ws_name )) {
        _debug("authorizer failed for ".$self->ws_name);
        Socialtext::Exception::Auth->throw;
    }
}

sub _process_docs {
    my ( $self, $docs ) = @_;
    _debug("Processing search results");

    my @results;
    my %seen;
    for my $doc (@$docs) {
        my $doc_id = $doc->value_for('id');
        next if exists $seen{ $doc_id };
        $seen{$doc_id} = 1;
        push @results, grep { defined } $self->_make_result($doc);
    }

    return \@results;
}

sub _make_result {
    my ($self, $doc) = @_;
    my $key     = $doc->value_for('id');
    my $doctype = $doc->value_for('doctype');
    my $score   = $doc->value_for('score');

    _debug("_make_result: $key $doctype $score");
    if ($doctype eq 'signal') {
        (my $signal_id = $key) =~ s/^signal://;
        return Socialtext::Search::SignalHit->new(
            score => $score,
            signal_id => $signal_id,
        );
    }
    if ($doctype eq 'signal_attachment') {
        $key =~ m/^signal:(\d+):filename:(.+)$/;
        return Socialtext::Search::SignalAttachmentHit->new(
            score => $score,
            signal_id => $1,
            filename => $2,
        );
    }
    if ($doctype eq 'person') {
        (my $user_id = $key) =~ s/^person://;
        return Socialtext::Search::PersonHit->new(
            score => $score,
            user_id => $user_id,
        );
    }
    if ($doctype eq 'group') {
        (my $group_id = $key) =~ s/^group://;
        return Socialtext::Search::GroupHit->new(
            score => $score,
            group_id => $group_id,
        );
    }
    elsif ($doctype eq 'page' or $doctype eq 'attachment') {
        my ($workspace_id, $page, $attachment) = split /:/, $key, 3;

        my $ws = Socialtext::Workspace->new(workspace_id => $workspace_id);
        unless ($ws) {
            _debug("_make_result: No such workspace id=($workspace_id)");
            return undef;
        }

        my $hit = {
            snippet => 'Unknown page',
            key     => $key,
            score   => $doc->value_for('score'),
        };

        my $ws_name = $ws->name;
        return
            defined $attachment
            ? Socialtext::Search::SimpleAttachmentHit->new($hit, $ws_name,
            $page, $attachment)
            : Socialtext::Search::SimplePageHit->new($hit, $ws_name, $page);
    }
    else {
        warn "Unknown doctype return in search results! '$doctype'";
    }
}

# Send a debugging message to syslog.
sub _debug {
    my $msg = shift || "(no message)";
    $msg = __PACKAGE__ . ": $msg";
    st_log->debug($msg);
}

__PACKAGE__->meta->make_immutable;
1;

=head1 NAME

Socialtext::Search::Solr::Searcher
- Solr Socialtext::Search::Searcher implementation.

=head1 SEE

L<Socialtext::Search::Searcher> for the interface definition.

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
