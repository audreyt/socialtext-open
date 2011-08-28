package Test::Socialtext::Cookie;
# @COPYRIGHT@

use strict;
use warnings;
use CGI::Cookie;
use Socialtext::HTTP::Cookie;

sub BuildCookie {
    my $class = shift;
    my $value = Socialtext::HTTP::Cookie->BuildCookieValue(@_);
    my $name  = Socialtext::HTTP::Cookie->cookie_name();
    return join '=', $name, $value;
}

sub BuildCookieNeedingRenewal {
    my $class = shift;
    my $now   = time;
    return $class->BuildCookie(
        @_,
        'not-before'      => ($now - 3600),
        'renew-until'     => ($now - 1800),
        'not-on-or-after' => ($now + 86400),
    );
}

sub BuildExpiredCookie {
    my $class = shift;
    my $now   = time;
    return $class->BuildCookie(
        @_,
        'not-before'      => ($now - 3600),
        'renew-until'     => ($now - 1800),
        'not-on-or-after' => ($now -  300),
    );
}

1;

=head1 NAME

Test::Socialtext::Cookie - methods to manipulate cookies within tests

=head1 SYNOPSIS

  use Test::Socialtext::Cookie;

  # create a new Cookie (as a string)
  $cookie = Test::Socialtext::Cookie->BuildCookie(user_id => $user_id);

  # create a Cookie that needs to be renewed
  $cookie = Test::Socialtext::Cookie->BuildCookieNeedingRenewal(
      user_id => $user_id,
  );

  # create a Cookie that has already expired
  $cookie = Test::Socialtext::Cookie->BuildExpiredCookie(
      user_id => $user_id,
  );

=head1 DESCRIPTION

This module implements methods to assist with the creation and manipulation of
cookies from within test suites.

=head1 METHODS

=over

=item B<Test::Socialtext::Cookie-E<gt>BuildCookie(%values)>

Creates a new cookie based on the provided C<%values>, returning that cookie
back to the caller as a string.

=item B<Test::Socialtext::Cookie-E<gt>BuildCookieNeedingRenewal(%values)>

Creates a new cookie based on the provided C<%values>, that has already passed
its "soft limit" and is in need of renewal.  Cookie returned back to the
caller as a string.

=item B<Test::Socialtext::Cookie-E<gt>BuildExpiredCookie(%values)>

Creates an I<expired> cookie based on the provided C<%values>, returning that
cookie back to the caller as a string.

=back

=cut
