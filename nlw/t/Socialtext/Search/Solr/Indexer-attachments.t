#!perl
# @COPYRIGHT@
use strict;
use warnings;

BEGIN {
    $ENV{NLW_APPCONFIG} = 'search_factory_class=Socialtext::Search::Solr::Factory';
}

use Test::Socialtext;
use Test::Socialtext::Search;
use Socialtext::File;

###############################################################################
# Fixtures: db no-ceq-jobs
# - we're an indexer test, so make sure there are *NO* Ceq jobs kicking around
#   that could cause things to get indexed
fixtures(qw( db no-ceq-jobs ));

my $wvtext_path = check_for_file_in_path('wvText');
if ( !$wvtext_path ) {
    plan skip_all => 'wvText is not installed.  Word attachments cannot be indexed, or tested.';
}

my $elinks_path = check_for_file_in_path('elinks');
if ( !$elinks_path ) {
    plan skip_all => 'elinks is not installed.  Word attachments cannot be or tested.';
}

plan tests => (scalar blocks) * 12;

my $hub = create_test_hub();
Test::Socialtext->main_hub($hub);

# test adding and indexing an attachment
run {
    my $case = shift;
    my $filename = $case->filename;
    my $filepath = 't/attachments/' . $filename;
    create_and_confirm_page('a test page',
        "a simple page containing a funkity string");

    open my $fh, $filepath or die "unable to open $filepath: $!";
    my $attachment = $hub->attachments->create(
        page_id => 'a_test_page',
        filename => $filename,
        fh => $fh,
        creator => $hub->current_user,
    );

    search_for_term('funkity');

    search_for_term_in_attach($case->term, $filename);

    # purge the page for cleanliness
    my $page = $hub->pages->new_from_name('a test page');
    $page->purge();
};

# non-portable, but better than 'which' or some of the other
# options
sub check_for_file_in_path {
    my $file  = shift;
    my @paths = split( ':', $ENV{PATH} );

    foreach my $path (@paths) {
        return $path if (-x Socialtext::File::catfile($path, $file));
    }

    return 0;
}



__DATA__
=== text
--- filename: foo.txt
--- term: backporterd

=== unknown
--- filename: foo
--- term: "do our bedroom too"

=== unknown with implicit bool
--- filename: foo
--- term: "do our bedroom too" installed

=== html
--- filename: foo.htm
--- term: srvc

=== word
--- filename: revolts.doc
--- term: poverty

=== word2
--- filename: revolts.doc
--- term: Tocqueville Marx

=== ppt
--- filename: indext.ppt
--- term: "Indexing Things"
