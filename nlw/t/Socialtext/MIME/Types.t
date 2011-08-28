#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::More tests => 1;
use Socialtext::MIME::Types;

###############################################################################
# TEST: calling semantics
calling_semantics: {
    my $file = 't/Socialtext/File/stringify_data/sample.docx';
    my $type = Socialtext::MIME::Types::mimeTypeOf($file);
    ok $type, 'able to do lookup and get MIME-Type';
}
