package Socialtext::CGI::User;
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::User;
use Socialtext::CredentialsExtractor::Client::Sync;

use base 'Exporter';
our @EXPORT_OK = qw/get_current_user/;

# Note: A parallel version of this code lives in Socialtext::Apache::User
# so if this mechanism changes, we need to change the CGI version too
# (or merge them together).
#
# This one is used by reports and the appliance console

sub get_current_user {
    my $client = Socialtext::CredentialsExtractor::Client::Sync->new();
    # XXX: We really want *more than* just ENV, but we're a CGI script and as
    # a result *don't* have access to any additional HTTP headers.
    my $creds  = $client->extract_credentials(\%ENV);
    return unless ($creds->{valid});
    return if ($creds->{user_id} == Socialtext::User->Guest->user_id);

    my $user_id = $creds->{user_id};
    return Socialtext::User->new(user_id => $user_id);
}

1;

=head1 NAME

Socialtext::CGI::User - Extract Socialtext user information from a CGI request

=head1 SYNOPSIS

  use Socialtext::CGI::User qw(get_current_user);

  $user = get_current_user();

=head1 DESCRIPTION

C<Socialtext::CGI::User> provides some helper methods to get information on
the current User.  B<Only> to be used in CGI scripts; use
C<Socialtext::Apache::User> if you are running under Mod_perl.

B<NOTE:> a parallel version of this code lives in C<Socialtext::Apache::User>.
If this mechanism changes, we need to change the Apache version too.
Eventually we'd like to merge them together into a single API, but we haven't
gotten there yet.

=head1 METHODS

=over

=item B<get_current_user()>

Returns a C<Socialtext::User> object for the currently authenticated User.

=back

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Socialtext, Inc. All Rights Reserved.

=cut
