package Socialtext::Preferences;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::MockBase';

our $AUTOLOAD;
sub AUTOLOAD {
    $AUTOLOAD =~ s/.+:://;
    return Socialtext::MockPreference->new(value => $AUTOLOAD);
}

package Socialtext::MockPreference;
use strict;
use warnings;
use base 'Socialtext::MockBase';

sub value { 
    my $self = shift;
    my $pref = $self->{value};
    my $values = { 
        sidebox_changes_depth => 5,
        changes_depth => 5,
        locale => 'en',
        which_page => '',
    };
    warn "no such preference '$pref' in mocked preferences"
        unless exists $values->{$pref};
    return $values->{$pref};
}

sub value_label { $_[0]->{value} }

1;
