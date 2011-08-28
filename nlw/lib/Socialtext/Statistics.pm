# @COPYRIGHT@
package Socialtext::Statistics;
use warnings;
use strict;

use base 'Exporter';

our @EXPORT_OK = qw( stat_call );

use Fcntl qw( :seek :flock );
use Socialtext::AppConfig;
use Readonly;

BEGIN {
    if ($ENV{MOD_PERL}) {
        require Apache;
        import Apache ();
    }
}

Readonly my $LOG_NAME => 'nlw-stats.log';
Readonly my $LOG_PATH => $ENV{APACHE_LOG_DIR}
    ? "$ENV{APACHE_LOG_DIR}/$LOG_NAME"
    : $LOG_NAME;

our %Class = (
    formatter_cache_hit_rate => 'Socialtext::Statistic',
    formatter_to_html_et     => 'Socialtext::Statistic::ElapsedTime',
    heap_delta               => 'Socialtext::Statistic::HeapDelta',
    nlw_process_et           => 'Socialtext::Statistic::ElapsedTime',
    postprocs                => 'Socialtext::Statistic',
    template_process_et      => 'Socialtext::Statistic::ElapsedTime',
    text_to_parsed_et        => 'Socialtext::Statistic::ElapsedTime',
);

our %Stat;

our $Enabled = 1;

sub stat_call {
    my $stat_name = shift;
    my $method = shift;

    return unless $Enabled;

    unless (exists $Stat{$stat_name}) {
        return unless _is_enabled($stat_name);
        _init_stat($stat_name);
    }
    $Stat{$stat_name}->$method(@_);
}

sub _init_stat {
    my $stat_name = shift;

    return unless $Enabled;

    my $class = $Class{$stat_name};

    eval "use $class ()";
    $Stat{$stat_name} = $Class{$stat_name}->new
        or warn "$stat_name constructor failed";
}

sub report { join '', report_lines() }

sub disable { $Enabled = 0 };

sub report_lines {
    my @lines;

    while (my($name, $stat) = each %Stat) {
        push @lines,
            $name
            . ' (' . $stat->len . ')'
            . ' mu=' . $stat->mean
            . ' var=' . $stat->variance
            . ' min=' . $stat->min
            . ' max=' . $stat->max
            . "\n";
    }

    return @lines;
}

sub _is_enabled {
    my $stat_name = shift;

    return unless exists $Class{$stat_name};

    my $config = Socialtext::AppConfig->stats || '';
    return ($config eq 'ALL' or $config =~ /(^|,|\.)$stat_name(,|\.|$)/ );
}

sub write_report {
    return unless $Enabled;

    my @lines = report_lines;

    if (@lines) {
        my $stamp = time;

        open my $fh, '>>', $LOG_PATH or die "open $LOG_PATH: $!";
        flock $fh, LOCK_EX or die "flock $LOG_PATH: $!";
        seek $fh, 0, SEEK_END or die "seek $LOG_PATH: $!";
        print {$fh} "$stamp $$ $_" foreach @lines;
        close $fh;
    }
}

END { write_report() }

1;
