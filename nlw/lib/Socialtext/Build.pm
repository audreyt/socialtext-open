# @COPYRIGHT@
package Socialtext::Build;

use strict;
use warnings;
use base 'Exporter';
use File::Spec;
use File::Basename qw(dirname);

our @EXPORT_OK = qw(get_build_setting get_prefixed_dir);
our %Settings;

eval {
    no warnings;
    require Socialtext::Build::ConfigureValues;
    %Settings = %{ $Socialtext::Build::ConfigureValues::VAR1 || {} };
};
load_defaults() if keys(%Settings) == 0;

sub get_build_setting {
    my $key = shift || "";
    return $Settings{$key};
}

sub get_prefixed_dir {
    my $key = shift;
    return File::Spec->catdir(
        get_build_setting("prefix"),
        get_build_setting($key),
    );
}

sub load_defaults {
    my $defaults_pl = defaults_pl();
    if ($defaults_pl) {
        my $VAR1;
        my $defs = eval `$defaults_pl`;
        for my $key ( sort keys %$defs ) {
            $Settings{$key} = $defs->{$key}->{value};
        }
    } else {
        die "Could not find any suitable settings:\n" . 
            "   * Socialtext::Build::ConfigureValues failed to load.\n" .
            "   * build/defaults.pl not found\n";
    }
}

sub defaults_pl {
    my $up = File::Spec->updir;
    my $file = File::Spec->catfile(
        dirname(__FILE__), $up, $up, 'build', 'defaults.pl'
    );
    return $file if -f $file and -r _;
    return "";
}

1;

__END__

=pod

=head1 NAME

Socialtext::Build

=head1 SUMMARY

This module provides build-time settings as passed to F<./configure>.

=cut
