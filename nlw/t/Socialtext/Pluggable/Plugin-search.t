#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 3;
use Socialtext::Jobs;
use Socialtext::Search::AbstractFactory;
use Test::Differences;

fixtures(qw( admin no-ceq-jobs ));

use_ok 'Socialtext::Pluggable::Plugin';

my $hub = new_hub('admin');

Socialtext::Search::AbstractFactory->GetFactory->create_indexer('admin')
    ->index_workspace('admin');
ceqlotron_run_synchronously();

my $plug = Socialtext::Pluggable::Plugin->new;
$plug->hub($hub);

#search
my $pages = $plug->search(
    search_term => 'tag:welcome',
    sortby => 'title',
);

# 'central_page_templates' maybe got removed?
my $expected = join "\n", qw(
advanced_getting_around
can_i_change_something
central_page_important_links
congratulations_you_know_how_to_use_a_workspace
conversations
document_library_template
documents_that_people_are_working_on
expense_report_template
how_do_i_find_my_way_around
how_do_i_make_a_new_page
how_do_i_make_links
learning_resources
lists_of_pages
meeting_agendas
meeting_minutes_template
member_directory
people
project_plans
project_summary_template
quick_start
);

my $results = join "\n", sort map { $_->{page_id} } @{$pages->{rows}};
eq_or_diff $results, $expected, "tag search returned the right page results";
