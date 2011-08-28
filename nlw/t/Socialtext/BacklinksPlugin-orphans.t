#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Socialtext::User;
use Socialtext::Page;
use Test::Socialtext tests => 6;

fixtures(qw( db ));

=head1 DESCRIPTION

Test that orphans are correctly discovered and correctly not
displayed when they are deleted.

=cut

my $hub = create_test_hub();
my $backlinks = $hub->backlinks;
my $pages = $hub->pages;

my $page_one = Socialtext::Page->new( hub => $hub )->create(
    title   => 'backlink sampler',
    content =>
        "Hello\nthis is a [smartass5] page to [admin wiki]\nyou\n\nHello ",
    creator => $hub->current_user,
);

{
    my $orphan_pages = $backlinks->get_orphaned_pages;

    my @backlinks = $backlinks->all_backlink_pages_for_page(
        $pages->new_from_name( 'backlink sampler' )
    );

    ok scalar(@backlinks) == 0, 'no backlinks for backlink sampler';
    ok scalar @$orphan_pages, 'there are some orphans';
    ok grep({ $_->id =~ /^backlink_sampler$/ } @$orphan_pages),
       "The orphan pages contains backlink sampler";
}

{
    my @calling_pages = $backlinks->all_backlink_pages_for_page(
        $pages->new_from_name( 'smartass5' )
    );
    
    ok grep({ $_->id =~ /^backlink_sampler$/ } @calling_pages),
        "The smartass5 page has a caller of backlink sampler";
}

{
    $page_one->delete( user => $hub->current_user );
    my $orphan_pages = $backlinks->get_orphaned_pages;
    ok(! grep(/^backlink_sampler$/, map {$_->id} @$orphan_pages),
        "The orphan pages does not contain backlink sampler");
}

{
    my $orphan = Socialtext::Page->new( hub => $hub )->create(
        title   => 'Orphan Page',
        content => 'Orphan',
        creator => Socialtext::User->SystemUser,
    );

    my $sortdir = $backlinks->sortdir;
    my $pages = $backlinks->get_orphaned_pages();
    $backlinks->_make_result_set( $sortdir, $pages );
    my $results = $backlinks->result_set;
    
    is($results->{rows}[0]->{Subject}, 'Orphan Page',
        'orphan pages are sorted by Date.');
}
