package Socialtext::DevEnvPlugin;

use strict;
use warnings;
use Socialtext::AppConfig;
use Socialtext::String;
use base 'Socialtext::Plugin';

sub class_id {'devenv'}

sub register {
    my $self     = shift;
    my $registry = shift;

    # we *ONLY* register ourselves in a dev-env; *NEVER* register on an actual
    # Appliance.
    unless (Socialtext::AppConfig->is_appliance) {
        $registry->add(action => 'dump_environment_vars');
    }
}

sub dump_environment_vars {
    my $self = shift;

    # create an HTML table with all of the ENV vars in it
    my $env_vars = "<table>\n";
    foreach my $key (sort keys %ENV) {
        my $elem_id = 'env_' . lc($key);
        my $escaped = Socialtext::String::html_escape($ENV{$key});
        $env_vars .= qq{
            <tr>
                <th>$key</th>
                <td id="$elem_id">$escaped</td>
            </tr>
        };
    }
    $env_vars .= "</table>\n";

    # build up the HTML and return that back to the caller.
    my $html = "<html><body>$env_vars</body></html>";
    return $html;
}

1;

=head1 NAME

Socialtext::DevEnvPlugin - Actions/Wafls for use in a development environment

=head1 DESCRIPTION

C<Socialtext::DevEnvPlugin> provides additional actions/wafls for use in a
B<development environment> (they are B<NOT> enabled on a production
Appliance).

=head1 ACTIONS

=over

=item B<dump_environment_vars>

Displays an HTML table-ized dump of all available environment variables.

Value cells in the HTML table have an Element Id that contains the name of the
environment variable, prefixed with C<env_> (e.g. the "HTTP_HOST" environment
variable can be found in the "env_http_host" HTML Element).  This I<may> turn
out to be useful for building test suites that need to check the value of
environment variables.

=back

=head1 WAFLS

No additional Wafls have been implemented at this time.

=head1 AUTHOR

Socialtext, Inc.  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
