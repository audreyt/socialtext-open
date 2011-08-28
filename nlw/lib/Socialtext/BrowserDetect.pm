package Socialtext::BrowserDetect;

# @COPYRIGHT@

use strict;
use warnings;

sub _ua () { lc($ENV{HTTP_USER_AGENT}||'') }

=head1 NAME

Socialtext::BrowserDetect - Determine the Web browser from an HTTP user agent string

=head1 FUNCTIONS

=head2 ie()

Tell if the user agent is MSIE of some kind or another.

=cut

sub ie {
    my $ua = _ua;
    return (index($ua,'msie') != -1) || (index($ua,'microsoft internet explorer') != -1);
}

=head2 safari()

Tell if the user agent is Safari.

=cut

sub safari {
    my $ua = _ua;
    return (index($ua,'safari') != -1) || (index($ua,'applewebkit') != -1);
}

=head2 adobe_air()

Tell if the user agent is Adobe AIR.

=cut

sub adobe_air {
    my $ua = _ua;
    return (index($ua,'adobeair') != -1);
}

=head2 is_mobile()

Tell if the user agent is some sort of mobile browser.

=cut

sub is_mobile {
    # this ENV var should be set by Apache, if it detects a mobile browser
    return $ENV{NLW_MOBILE_BROWSER};
}

# Strings taken from HTTP::BrowserDetect, but boy it's a lot smaller now.

1;
