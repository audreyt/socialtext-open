#!/usr/bin/env perl
use warnings;
use strict;
# @COPYRIGHT@
use Test::More tests => 5;
use Test::Output;

use ok 'Socialtext::TimestampedWarnings';

my $ts_re = qr/\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[-+]\d{4}\]/;

stderr_like {
    warn "without a newline";
} qr/^$ts_re without a newline at .+$/s, 'no newline';

stderr_like {
    warn "with a newline\n";
} qr/^$ts_re with a newline$/s, 'no newline';

stderr_like {
    warn "mul","ti","ple"," args";
} qr/^$ts_re multiple args at .+$/s, 'multi-args';


stderr_like {
    warn "embedded\nnewlines\n";
} qr/^$ts_re embedded\n$ts_re newlines$/s, 'embedded newlines';
