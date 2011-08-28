#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext tests => 3;

BEGIN {
    use_ok('Socialtext::Log', 'st_log');
}

use Readonly;

fixtures( 'base_layout' );

Readonly my $LEVEL         => 'emergency';
Readonly my $MESSAGE       => 'fnord';
Readonly my @EXPECTED_ARGS => ( 'EMERG', "[$>] $MESSAGE" );

my @last_syslog_args;

{
    no warnings 'redefine';
    local *Sys::Syslog::syslog = sub { @last_syslog_args = @_ };

    {
        st_log->$LEVEL($MESSAGE);

        is_deeply( \@last_syslog_args, \@EXPECTED_ARGS, 'Arrow syntax works.' );
    }

    {
        @last_syslog_args = ();
        st_log($LEVEL, $MESSAGE);

        is_deeply( \@last_syslog_args, \@EXPECTED_ARGS, 'List syntax works.' );
    }
}
