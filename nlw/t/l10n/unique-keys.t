#!perl -w
# @COPYRIGHT@
use strict;
use warnings;
use Test::More tests => 1;
use FindBin '$RealBin';

chdir "$RealBin/../..";

# The count will be 1 for the initial lexicon entry: msgid ""
is int(`msgcat share/l10n/en/*.po |grep '#, fuzzy' | wc -l`), 1, "All keys in share/l10n/en/*.po are unique";
