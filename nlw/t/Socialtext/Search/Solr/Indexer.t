#!perl
# @COPYRIGHT@
# -*- coding: utf-8 -*- vim:fileencoding=utf-8:
use utf8;
use strict;
use warnings;

use Test::Socialtext tests => 2;

BEGIN {
    use_ok("Socialtext::Search::Solr::Indexer");
    use_ok("Socialtext::Search::Solr::Factory");
}

