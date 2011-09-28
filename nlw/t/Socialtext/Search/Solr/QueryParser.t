#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 77;

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

valuelookup: {
    my @tests = (
        [
            q!"Hello there"!,
            q!"Hello there"!,
            q!"Hello there"!,
        ],
        [
            q!abc AND def AND colour=blue OR lyz!,
            qq!abc AND def AND annotation:["socialtext","colour","blue"] OR lyz!,
            qq!abc AND def AND annotation:socialtext|colour|blue OR lyz!,
        ],
          [
              q!abc AND def AND acolour="is red" OR lyz!,
              qq!abc AND def AND annotation:["socialtext","acolour","is red"] OR lyz!,
              qq!abc AND def AND annotation:"socialtext|acolour|is red" OR lyz!,
          ],
         [
             q!abc AND def AND "the colour"=blue OR lyz!,
             qq!abc AND def AND annotation:["socialtext","the_colour","blue"] OR lyz!,
             qq!abc AND def AND annotation:socialtext|the_colour|blue OR lyz!,
         ],
         [
             q!abc AND def AND "a colour"="is red" OR lyz!,
             qq!abc AND def AND annotation:["socialtext","a_colour","is red"] OR lyz!,
             qq!abc AND def AND annotation:"socialtext|a_colour|is red" OR lyz!,
         ],
         [
             q!abc AND def AND "a colour"="is \"a\" red" OR lyz!,
             q!abc AND def AND annotation:["socialtext","a_colour","is \"a\" red"] OR lyz!,
             q!abc AND def AND annotation:"socialtext|a_colour|is \"a\" red" OR lyz!,
         ],
         [
             q!abc AND def AND "quote \"colour\""="is red" OR lyz!,
             q!abc AND def AND annotation:["socialtext","quote_colour","is red"] OR lyz!,
             q!abc AND def AND annotation:"socialtext|quote_colour|is red" OR lyz!,
         ],
         [
             q!abc AND def AND "tude \"colour"="is purple" OR lyz!,
             q!abc AND def AND annotation:["socialtext","tude_colour","is purple"] OR lyz!,
             q!abc AND def AND annotation:"socialtext|tude_colour|is purple" OR lyz!,
         ],
         [
             q!abc AND def AND "how about a"="is \"purple" OR lyz!,
             q!abc AND def AND annotation:["socialtext","how_about_a","is \"purple"] OR lyz!,
             q!abc AND def AND annotation:"socialtext|how_about_a|is \"purple" OR lyz!,
         ],
         [
             q!abc AND def AND "tude \"colour"="is \"purple" OR lyz!,
             q!abc AND def AND annotation:["socialtext","tude_colour","is \"purple"] OR lyz!,
             q!abc AND def AND annotation:"socialtext|tude_colour|is \"purple" OR lyz!,
         ],
         [
             q!abc AND def AND "colour one"="is red" OR lyz AND colourtwo=green!,
             q!abc AND def AND annotation:["socialtext","colour_one","is red"] OR lyz AND annotation:["socialtext","colourtwo","green"]!,
             q!abc AND def AND annotation:"socialtext|colour_one|is red" OR lyz AND annotation:socialtext|colourtwo|green!,
         ],
         [
             q!abc AND def AND "colour one"="is \"the\" red" OR lyz AND colourtwo=green!,
             q!abc AND def AND annotation:["socialtext","colour_one","is \"the\" red"] OR lyz AND annotation:["socialtext","colourtwo","green"]!,
             q!abc AND def AND annotation:"socialtext|colour_one|is \"the\" red" OR lyz AND annotation:socialtext|colourtwo|green!,
         ],
         [
             q!abc AND def AND "colour one"="is red" OR lyz AND "colour two"="was green"!,
             q!abc AND def AND annotation:["socialtext","colour_one","is red"] OR lyz AND annotation:["socialtext","colour_two","was green"]!,
             q!abc AND def AND annotation:"socialtext|colour_one|is red" OR lyz AND annotation:"socialtext|colour_two|was green"!,
         ],
         [
             q!"A bunch of text" AND "colour one"="is red" OR lyz!,
             q!"A bunch of text" AND annotation:["socialtext","colour_one","is red"] OR lyz!,
             q!"A bunch of text" AND annotation:"socialtext|colour_one|is red" OR lyz!,
         ],
        [
            q!abc AND title="my job" AND acolour="is red"!,
            q!abc AND annotation:["socialtext","title","my job"] AND annotation:["socialtext","acolour","is red"]!,
            q!abc AND annotation:"socialtext|title|my job" AND annotation:"socialtext|acolour|is red"!,
        ],
        [
            q!abc AND title="my job" AND acolour="is red" OR fish = minnow!,
            q!abc AND annotation:["socialtext","title","my job"] AND annotation:["socialtext","acolour","is red"] OR fish minnow!,
            q!abc AND annotation:"socialtext|title|my job" AND annotation:"socialtext|acolour|is red" OR fish minnow!,
        ],
        [
            q!abc AND title="my job" AND acolour="is red" OR fish= minnow!,
            q!abc AND annotation:["socialtext","title","my job"] AND annotation:["socialtext","acolour","is red"] OR fish minnow!,
            q!abc AND annotation:"socialtext|title|my job" AND annotation:"socialtext|acolour|is red" OR fish minnow!,
        ],
         [
             q!abc AND title="my job" AND acolour="is red" OR fish =minnow!,
             q!abc AND annotation:["socialtext","title","my job"] AND annotation:["socialtext","acolour","is red"] OR fish title:minnow!,
             q!abc AND annotation:"socialtext|title|my job" AND annotation:"socialtext|acolour|is red" OR fish title:minnow!,
         ],
         [
             q!abc AND funky="value with = in it" AND acolour="is red" OR fish =minnow!,
             q!abc AND annotation:["socialtext","funky","value with = in it"] AND annotation:["socialtext","acolour","is red"] OR fish title:minnow!,
             q!abc AND annotation:"socialtext|funky|value with = in it" AND annotation:"socialtext|acolour|is red" OR fish title:minnow!,
         ],
         [
             q!="The Title" AND funky="value with = in it" AND acolour="is red"!,
             q! title:"The Title" AND annotation:["socialtext","funky","value with = in it"] AND annotation:["socialtext","acolour","is red"]!,
             q! title:"The Title" AND annotation:"socialtext|funky|value with = in it" AND annotation:"socialtext|acolour|is red"!,
         ],
         [
             q!funky="value with = in it" AND ="The Title"!,
             q!annotation:["socialtext","funky","value with = in it"] AND title:"The Title"!,
             q!annotation:"socialtext|funky|value with = in it" AND title:"The Title"!,
         ],
          [
              q!="The Title" AND ns:funky="value with = in it" AND acolour="is red"!,
              q! title:"The Title" AND annotation:["ns","funky","value with = in it"] AND annotation:["socialtext","acolour","is red"]!,
              q! title:"The Title" AND annotation:"ns|funky|value with = in it" AND annotation:"socialtext|acolour|is red"!,
          ],
         [
             q!="The Title" AND ns:with_colon:funky="value with = in it" AND acolour="is red"!,
             q! title:"The Title" AND annotation:["ns_with_colon","funky","value with = in it"] AND annotation:["socialtext","acolour","is red"]!,
             q! title:"The Title" AND annotation:"ns_with_colon|funky|value with = in it" AND annotation:"socialtext|acolour|is red"!,
         ],
         [
             q!"A bunch of text" AND "colour \"one"="is red" OR lyz!,
             q!"A bunch of text" AND annotation:["socialtext","colour_one","is red"] OR lyz!,
             q!"A bunch of text" AND annotation:"socialtext|colour_one|is red" OR lyz!,
         ],
         [
             q!"na:key with [] in it"=value!,
             q!annotation:["na","key_with_in_it","value"]!,
             q!annotation:na|key_with_in_it|value!,
         ],
         [
             q!"na:key"="value with [] in it"!,
             q!annotation:["na","key","value with [\] in it"]!,
             q!annotation:"na|key|value with [] in it"!,
         ],
         [
             q!annotation:["namespace","key","value"]!,
             q!annotation:["namespace","key","value"]!,
             q!annotation:namespace|key|value!,
         ],
         [
             q!"just a quote"!,
             q!"just a quote"!,
             q!"just a quote"!,
         ],
         [
             q!"a quote" AND stuff!,
             q!"a quote" AND stuff!,
             q!"a quote" AND stuff!,
         ],
         [
             q!annotation:["namespace","key"]!,
             q!annotation:["namespace","key"]!,
             q!annotation:namespace|key|*!,
         ],
         [
             q!annotation:["namespace"]!,
             q!annotation:["namespace"]!,
             q!annotation:namespace|*!,
         ],
         [
             q!"just a quote" "and another quote"!,
             q!"just a quote" "and another quote"!,
             q!"just a quote" "and another quote"!,
         ],
         [
             q!"just a quote" AND "and another quote"!,
             q!"just a quote" AND "and another quote"!,
             q!"just a quote" AND "and another quote"!,
         ],
    );

    foreach my $test (@tests) {
        $query = $parser->munge_raw_query_string($test->[0]);
        is $query, $test->[1], "Row munge: $test->[0]";
        $query = $parser->parse($test->[0]);
        is $query, $test->[2], "Parse: $test->[0]";
    }

}

