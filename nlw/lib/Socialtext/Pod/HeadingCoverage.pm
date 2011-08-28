package Socialtext::Pod::HeadingCoverage;
# @COPYRIGHT@

use strict;
use warnings;
use base 'Pod::Coverage';
use Pod::Find qw(pod_where);

###############################################################################
# Recommended headings, as outlined in "perlmodstyle".
our @required_headings = qw(
    NAME SYNOPSIS DESCRIPTION AUTHOR COPYRIGHT LICENSE
);

###############################################################################
# Gives the coverage as a value in the range 0 to 1
sub coverage {
    my $self = shift;

    # Get the POD for the current package
    my $pods = $self->_get_pods;

    # Get the list of required headings
    my @required = $self->{required_headings}
        ? @{$self->{required_headings}}
        : @required_headings;
    my %headings = map { $_ => 0 } @required;

    # Mark off those headings which we found in the POD
    foreach my $pod (keys %{$pods->{head1}}) {
        $headings{$pod} = 1 if exists $headings{$pod};
    }

    # Stash the results for later
    $self->{symbols} = \%headings;

    # Calculate the coverage for this package
    my $expected   = scalar keys %headings;
    my $documented = scalar grep { $_ } values %headings;
    return $documented / $expected;
}

###############################################################################
# Extract POD markers from the currently active package.
#
# Return a hashref or undef on fail
sub _get_pods {
    my $self    = shift;
    my $package = $self->{package};

    $self->{pod_from} ||= pod_where( { -inc => 1 }, $package );
    my $pod_from = $self->{pod_from};
    unless ($pod_from) {
        $self->{why_unrated} = "couldn't find pod";
        return;
    }

    my $pod = Pod::Coverage::HeadingsExtractor->new;
    $pod->{nonwhitespace} = $self->{nonwhitespace};
    $pod->parse_from_file($pod_from, '/dev/null');

    return $pod->headings();
}

###############################################################################
### Custom POD extractor, to get us *just* the headings.
###############################################################################
package Pod::Coverage::HeadingsExtractor;

use base 'Pod::Parser';

sub command {
    my ($self, $cmd, $para, $line) = @_;
    if ($cmd =~ /^head\d/) {
        $para =~ s/^\s*|\s*$//g;        # strip *ALL* leading/trailing WS
        $self->{headings}{$cmd}{$para} = '';
        $self->{curr_heading} = \$self->{headings}{$cmd}{$para};
    }
    else {
        $self->{curr_heading} = undef;
    }
}

sub _grab_paras {
    my ($self, $para, $line) = @_;
    if ($self->{curr_heading}) {
        ${$self->{curr_heading}} .= $para;
    }
}

sub verbatim  { _grab_paras(@_) }
sub textblock { _grab_paras(@_) }

sub headings {
    my $self = shift;
    return $self->{headings} || {};
}

1;

=head1 NAME

Socialtext::Pod::HeadingCoverage - subclass of Pod::Coverage that examines headings

=head1 SYNOPSIS

  # all in one invocation
  use Socialtext::Pod::HeadingCoverage package => 'Fishy';

  # straight OO
  use Socialtext::Pod::HeadingCoverage;
  my $pc = Pod::Coverage::HeadingCoverage->new( package => 'Fishy' );
  print "We rock!" if $pc->coverage == 1;

=head1 DESCRIPTION

C<Socialtext::Pod::HeadingCoverage> extends C<Pod::Coverage>, and B<only>
checks to make sure that you have included a recommended set of headings
within your Pod.

=head1 AUTHOR

Graham TerMarsch C<< <graham.termarsch@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright (C) 2009 Socialtext, Inc., All Rights Reserved.

=head1 SEE ALSO

L<Pod::Coverage>.

=cut
