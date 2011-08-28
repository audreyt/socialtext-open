#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 11;

use_ok("Socialtext::Search::Solr::QueryParser");

my $parser = new Socialtext::Search::Solr::QueryParser();

my $query = $parser->munge_raw_query_string('tag:welcome');
is $query, 'tag:welcome';

$query = $parser->munge_raw_query_string('tag: welcome');
is $query, 'tag:welcome';

$query = $parser->munge_raw_query_string('Tag:welcome');
is $query, 'tag:welcome';

$query = $parser->munge_raw_query_string('Tag: welcome');
is $query, 'tag:welcome';

$query = $parser->munge_raw_query_string('tag:   welcome');
is $query, 'tag:welcome';

$query = $parser->munge_raw_query_string('Tag:   welcome');
is $query, 'tag:welcome';


$query = $parser->parse("sametime:kensametime");
is $query, "sametime_sn_pf_s:kensametime";

$query = $parser->parse("sametime_sn_pf_s:kensametime");
is $query, "sametime_sn_pf_s:kensametime";

$query = $parser->parse("manager:bob");
is $query, "supervisor_pf_rt:bob";

$query = $parser->parse("foo:bar");
is $query, "foo bar";
