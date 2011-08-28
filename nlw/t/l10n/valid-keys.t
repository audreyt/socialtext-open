#!perl -w
# @COPYRIGHT@
use strict;
use warnings;
use Test::More tests => 1;
use FindBin '$RealBin';

chdir "$RealBin/../..";

is system("./dev-bin/l10n-check-po share/l10n/en/*.po"), 0, "All keys in share/l10n/en/*.po are valid";
