#!/usr/bin/env perl
# -*- coding: utf-8 -*- vim:fileencoding=utf-8:
# @COPYRIGHT@
use strict;
use warnings;
use IPC::Run qw(run timeout);

use utf8;
use Test::Socialtext tests => 204;
use Test::Socialtext::Search;

fixtures(qw( db no-ceq-jobs ));

use_ok("Socialtext::Search::Solr::Factory");

my $hub = create_test_hub();
Test::Socialtext->main_hub($hub);

my $workspace = $hub->current_workspace->name();

my $INDEXER;
my $SEARCHER;

ok make_indexer(), 'made indexer';
ok make_searcher(), 'made searcher';

###############################################################################
basic_search: {
    erase_index_ok();
    make_page_ok(
        "Cows Rock",
        "There is no such thing as a chicken that dances"
    );
    search_ok( "dances",        1, "Simple word search (in body)" );
    search_ok( "Cows",          1, "Simple word search (in title)" );
    search_ok( "title:Cows",    1, "Title search" );
    search_ok( "=Cows",         1, "Title (=) search" );
    search_ok( "It is raining", 0, "Nonsense" );
}

###############################################################################
more_featured_search: {
    erase_index_ok();
    make_page_ok( "Tom Stoppard", <<'QUOTE', [ "man likes dog", "man" ] );
We cross our bridges when we come to them and burn them behind us, with
nothing to show for our progress except a memory of the smell of smoke, and a
presumption that once our eyes watered.
QUOTE
    search_ok( "bridges",  1, "Literal word search" );
    search_ok( "bridge",   1, "Depluralized word search" );
    search_ok( "bridging", 1, "Similarly stemmed word search" );
    search_ok(
        "The smoking bridge smells", 1,
        "Multiple Word Search with Stemming"
    );
    search_ok(
        "bridge idonotexist", 1,
        "Assert searching defaults to OR connectivity"
    );
    search_ok( 'bridges -smoke',   0, "Search with negation" );
    search_ok( '"smell of smoke"', 1, "Phrase search" );
    search_ok(
        'bridges AND NOT "smell of smoke"', 0,
        "Search with phrase negation"
    );
    search_ok(
        'bridges AND NOT "smoke on the water"', 1,
        "Search without Deep Purple "
    );
    search_ok( "tag:man", 1, "Tag search with word which is standalone" );
    search_ok( "tag:dog", 1, "Tag search with word not also standalone" );
    search_ok( "tag:\"man likes dog\"", 1, "Tag search with phrase" );
    search_ok( "tag:idonotexst", 0, "Tag search for a non-existant tag" );
}

###############################################################################
# As part of RT 26849 faux fields are removed from query strings by replacing
# their ending ":" with a space.  Ensure this works okay.
FIXUP_FAUX_FIELDS: {
    erase_index_ok();
    make_page_ok( "Love Nerd", "Baby Eater", [ "quotes", "writers" ] );
    search_ok( "tag:quotes", 1 );
    search_ok( "baby:eater", 1 );  # baby:eater becomes "baby eater"
}

###############################################################################
# RT 25899: ensure phrase queries work
PHRASE_QUERY_BUG: {
    erase_index_ok();
    make_page_ok( "Little Sheep", "zzz xxx yyy zzz" );
    search_ok( '"yyy zzz"', 1 );  # Breaks with KS 0.15 and less
}

###############################################################################
flexing_multiple_pages: {
    erase_index_ok();
    make_page_ok( "Tom Stoppard", <<'QUOTE', [ "quotes", "writers" ] );
We cross our bridges when we come to them and burn them behind us, with
nothing to show for our progress except a memory of the smell of smoke, and a
presumption that once our eyes watered.
QUOTE
    make_page_ok( "Neil Gaiman", <<'QUOTE', [ "quotes", "writers" ] );
It has always been the prerogative of children and half-wits to point out that
the emperor has no clothes. But the half-wit remains a half-wit, and the
emperor remains an emperor.
QUOTE
    make_page_ok( "Louis Jenkins", <<'QUOTE', [ "poems", "writers" ] );
Diner
 
The time has come to say goodbye, our plates empty except for our greasy
napkins. Comrades, you on my left, balding, middle-aged guy with a ponytail,
and you, Lefty there on my right, though we barely spoke I feel our kinship.
You were steadfast in passing the ketchup, the salt and pepper, no man could
ask for better companions. Lunch is over, the cheeseburgers and fries, the
Denver sandwich, the counter nearly empty. Now we must go our separate ways.
Not a fond embrace, but perhaps a hearty handshake. No? Well then, farewell.
It is unlikely I'll pass this way again. Unlikely we will ever meet again on
this earth, to sit together beneath the neon and fluorescent calmly sipping
our coffee, like the sages sipping their tea underneath the willow, sitting
quietly, saying nothing.
QUOTE
    search_ok( "bridges OR children", 2, "Disjunctive Search" );
    search_ok( "the",                 0, "The is a stop word" );

    search_ok( "tag:writers",       3, "Common tags" );
    search_ok( "tag: writers",      3, "Field search with a space" );
    search_ok( "tag:      writers", 3, "Field search with lots of spaces" );
    search_ok(
        "tag:writers AND tag:quotes", 2,
        "Common tags, with conjunction"
    );

    search_ok( "category:writers", 3, "Common categories (alias for tags)" );
    search_ok(
        "category:writers AND category:poems", 1,
        "Common categories (alias for tags), with conjunction"
    );

    search_ok( "(sages OR bridges) AND (tea OR emperor)", 1,
        "More complex search" );
}

###############################################################################
# If a page has two tags: "cows love" and "super matthew" then make sure a tag
# search for neither of these matches: "love super" or "matthew cows" 
rt22654_crosstag_search_bug: {
    erase_index_ok();
    make_page_ok( "Story of the Mammal", "Mammal Power",
        [ "cows love", "super matthew" ] );
    search_ok( 'tag:"love super"',   0, "" );
    search_ok( 'tag:"matthew cows"', 0, "" );
}

###############################################################################
rt22174_title_search_bug: {
    erase_index_ok();
    make_page_ok( "Beamish Stout", 'has thou slain the jabberwock' );
    make_page_ok( "light", 'is beamish.  has thou slain the jabberwock' );
    search_ok( '"has thou slain the jabberwock" AND title:beamish', 1, "" );
    search_ok( '"has thou slain the jabberwock" AND =beamish',      1, "" );
    search_ok( '=beamish AND "has thou slain the jabberwock"',      1, "" );
}

###############################################################################
basic_utf8: {
    erase_index_ok();
    my $utf8 = "big and Groß";
    make_page_ok( $utf8, "Cows are good but $utf8 en français",
        ["español"] );
    search_ok( "français",         1, "Utf8 body search" );
    search_ok( "Groß",             1, "Utf8 general search" );
    search_ok( "Groß français",   1, "Utf8 search with implicit AND" );
    search_ok( "title:Groß",       1, "Utf8 title search" );
    search_ok( "=Groß",            1, "Utf8 title search (=)" );
    search_ok( "tag:español",      1, "Utf8 tag search" );
    search_ok( "category:español", 1, "Utf8 tag search" );
    search_ok(
        "Groß AND (français OR tag:español) AND category:español",
        1, "Complicated search with UTF-8"
    );

    # Ensure the tokenizer/stemmers aren't just ignoring the UTF-8
    search_ok( "Gro",          0, "UTF-8 not lost in stemming" );
    search_ok( "Gro ",         0, "UTF-8 not lost in stemming" );
    search_ok( "franais",      0, "UTF-8 not substititued away" );
    search_ok( "fran ais",     0, "UTF-8 not substititued away" );
    search_ok( "fran",         0, "UTF-8 not used as token seperator" );
    search_ok( "tag:espa",     0, "UTF-8 not used as token seperator" );
    search_ok( "tag:espa nol", 0, "UTF-8 not used as token seperator" );
}

###############################################################################
lots_of_hits: {
    erase_index_ok();
    for my $n ( 1 .. 105 ) {
        make_page_ok( "Page Test $n", "The contents are $n" );
    }
    search_ok( "Page Test", 20, "Big result sets returned ok" );
}

###############################################################################
# In this test block we are testing to see if $& (or friends) has been used.
# The mention (whether it's in unused code or not) of $&, $' or $` will cause
# Perl regexes to slow down globally, in an exponential fashion (by the length
# of the string being tested).  This is a fundamental limitation and bug in
# Perl.  Search below for "MACHINERY_FOR_DOLLAR_AMP_TIMING_TEST" for more
# information.
test_for_dollar_amp_and_friend: {
    my $MAX_RATIO = 10;
    my $baseline  = run_time_test_externally();
    my $test_time = run_time_test_internally();
    my $ratio_ok  = ( ( $test_time / $baseline ) < $MAX_RATIO );
    ok( $ratio_ok, 'Timing test for $& and friends.' );
    unless ($ratio_ok) {
        my $opt = $ENV{PERL5OPT} || "";
        diag(<<MSG);
A run without \$& (or friends) present took $baseline seconds.  A run in the
current test environment took $test_time seconds.  This is more than
${MAX_RATIO}x as long, which is a sign of the exponential time-increase that
\$& and family introduce.  \$& may be present in your testing environment, or
some module loading during the tests (i.e. dependency modules, production
code, etc).  Please verify if this is the case and remove it if so, since
indexing will be strongly affected.

A common problem in dev-envs is using prv, which will automatically include
diagnostics.pm which uses \$&, and causes this test to fail.  If
diagnostics.pm is included by the environment variable PERL5OPT which has the
current value: PERL5OPT=$opt.
MSG
    }
}

###############################################################################
index_and_search_a_big_document: {
    my $text = "Mary had a little lamb and it liked to drink. " x 100000;
    erase_index_ok();
    ok( 1, '(Indexing big document - 4.4 MB)' );
    make_page_ok( "Really Big Page", $text );
    search_ok( "lamb", 1, "Searching for the big page" );
}

###############################################################################
basic_wildcard_search: {
    erase_index_ok();
    my @words = split /\s+/, "When the roofers are done roofing the roof.";
    my $n = 0;
    for my $word (@words) {
        $n++;
        make_page_ok("Wildcard $n: $word", $word, ["cow_$word"]);
    }
    search_ok("roof*",            3, "Searching for roof*");
    search_ok("title:wildcard",   8, "Searching for wildcard");
    search_ok("title: wild*",     8, "Searching for title: wild*");
    search_ok("title:wild*",      8, "Searching for title:wild*");
    search_ok("=wild*",           8, "Searching for title:wild*");
    search_ok("ro*",              3, "wildcard works when term is short");
    search_ok("roo* OR don*",     4, "Searching for wildcard in disjunction");
    search_ok("don* -roo*",       1, "Searching with negation of wildcard");
    search_ok("tag_exact:cow_r*", 3, "Searching for wildcard in tag_exact");
    search_ok("tag:roo*", 3, "Searching for wildcard in tag");
    search_ok("(roof*)",  3, "Searching for wildcard in tag in parens.");
}

exit;

###############################################################################
###############################################################################
### Helper methods (no tests after here)
###############################################################################
###############################################################################
sub make_page_ok {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ( $title, $content, $tags ) = @_;
    my $page = Socialtext::Page->new(hub => $hub)->create(
        title => $title,
        content => $content,
        creator => $hub->current_user,
        categories => $tags || [],
    );
    index_ok( $page->id );

    return $page;
}

sub search_ok {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ( $term, $num_of_results, $text ) = @_;
    my @results = eval { searcher()->search($term, undef, [$workspace]) };
    diag($@) if $@;

    my $hits = ( $num_of_results == 1 ) ? "hit" : "hits";
    my $name = $text
        ? "'$term' returns $num_of_results $hits: $text"
        : "'$term' returns $num_of_results $hits";
    is scalar @results, $num_of_results, $name;
    return @results;
}

sub index_ok {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $INDEX_MAX = 60*5;    # Maximum of 5 minutes to index page.

    my $page = shift;
    my $id   = ref($page) ? $page->id : $page;

    # Use a double eval in case the alarm() goes off in between returing from
    # the inner eval and before alarm(0) is executed.
    my $fail;
    eval {
        local $SIG{ALRM} = sub {
            die "Indexing $id is taking more than $INDEX_MAX seconds.\n";
        };
        alarm($INDEX_MAX);
        eval { 
            indexer()->index_page($id);
        };
        $fail = $@;
        alarm(0);
    };

    diag("ERROR Indexing $id: $fail\n") if $fail;
    ok( not($fail), "Indexing $id" );
}

sub erase_index_ok {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    eval { indexer()->delete_workspace($workspace) };
    diag("erase_index_ok: $@\n") if $@;
    ok( not($@), "============ ERASED INDEX =============" );

    # Create new searcher/indexer object instance, so we don't leak from one
    # test to the next; if either of those objects (or their attributes) has
    # internal state, it can pollute into the next test.
    make_searcher();
    make_indexer();
}

sub make_searcher {
    $SEARCHER = Socialtext::Search::Solr::Factory->create_searcher($workspace, @_);
}

sub make_indexer {
    $INDEXER = Socialtext::Search::Solr::Factory->create_indexer($workspace, @_);
}

sub indexer {
    return $INDEXER;
}

sub searcher {
    return $SEARCHER;
}

########################################################
#
# Machinery for testing for the prescense of $& and family.  
#
# We test for this by taking some code and running it in an external Perl
# program, one known to be free of any use of $& or its friends.  We record
# how long a certain regular expression takes to finish.  We then run the same
# test but via eval() in the current process and record how long this takes.
#
# The external run gives a baseline for the environment the test is running
# on, so we don't have to hard code in a certain number of seconds (which
# might be wrong for some computers).
#
# (Use BEGIN so the variables in the closure are evaluated right away).
BEGIN { # MACHINERY_FOR_DOLLAR_AMP_TIMING_TEST. 
    my $TIMELIMIT = 60*5;  # Five minutes should be an plenty of time.
    my $CODE = <<'PROG';
    use strict;
    use warnings;
    use Time::HiRes qw(gettimeofday tv_interval);
    $| = 1;

    my $str = "xy"x100_000;
    my $start = [gettimeofday];
    1 while $str =~ m/x/g;
    my $time = sprintf "%.04f", tv_interval($start);
    if (@ARGV) {  # For communicating back via an external program
        print $time;
        exit 0;
    } else {      # for communicating back via eval()
        $time;
    }
PROG

    sub run_time_test_internally {
        my $out;
        eval {
            local $SIG{ALRM} = sub { die "TIMELIMIT EXCEEDED" };
            alarm($TIMELIMIT);
            $out = eval $CODE;
            alarm(0);
            die "$@\n" if $@;
        };
        die "Failure evaling Perl program: $@\n" if $@;
        unless ( defined($out) and $out =~ /\d+\.\d+/ ) {
            die "Perl code did not return a value.\n";
        }
        return $out;
    }

    sub run_time_test_externally {
        my ( $out, $err );
        my $rv = run(
            [ "/usr/bin/env", "-i", "perl", "-e", $CODE, "1" ],
            \undef, \$out, \$err,
            timeout($TIMELIMIT)
        );
        unless ( defined($out) and $out =~ /\d+\.\d+/ ) {
            $err = "(no stderr)" unless defined $err;
            $out = "(no stdout)" unless defined $out;
            die "Failure running Perl program (exit=$rv).\n$out\n\n$err\n";
        }
        return $out;
    }
}
