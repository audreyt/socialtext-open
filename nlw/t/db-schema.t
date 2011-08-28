#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 6;
use Test::Socialtext::SQL;

fixtures(qw( db ));

###############################################################################
# TEST: "recent" Signals tables match their counterparts
recent_signals: {
    local $Test::Socialtext::SQL::Normalizer = sub {
        my $name = shift;
        $name =~ s/^recent_//;
        $name =~ s/^ix_recent_/ix_/;
        return $name;
    };

    db_columns_match_ok(qw(signal recent_signal));
    db_indices_match_ok(qw(signal recent_signal));

    db_columns_match_ok(qw(signal_user_set recent_signal_user_set));
    db_indices_match_ok(qw(signal_user_set recent_signal_user_set));
}

###############################################################################
# TEST: Events "archive" tables match their counterparts
events_archive: {
    local $Test::Socialtext::SQL::Normalizer = sub {
        my $name = shift;
        $name =~ s/_archive//;
        return $name;
    };

    db_columns_match_ok(qw(event event_archive));
}

# TEST: Events "view" table match their counterparts
events_archive: {
    local $Test::Socialtext::SQL::Normalizer = sub {
        my $name = shift;
        $name =~ s/view_//;
        return $name;
    };

    db_columns_match_ok(qw(event view_event));
}
