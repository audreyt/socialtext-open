package Socialtext::UUID;
use warnings;
use strict;
use base 'Exporter';
use Data::UUID ();

our @EXPORT    = qw(new_uuid);
our @EXPORT_OK = qw(new_uuid);

my $uuid;

sub new_uuid () {
    $uuid ||= Data::UUID->new;
    return lc $uuid->create_str;
}

1;
__END__

=head1 NAME

Socialtext::UUID - Random (v4) UUID generator

=head1 SYNOPSIS

    use Socialtext::UUID;
    my $uuid = new_uuid;

=head1 DESCRIPTION

Generates random UUIDs (v4).  Guaranteed to be lowercase.

=cut
