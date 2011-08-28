# @COPYRIGHT@
#
package Socialtext::WikiFixture::HealthReport;
use strict;
use warnings;
use base 'Socialtext::WikiFixture::Socialtext';
use Test::More;
use Socialtext::URI;
use Cwd;


# mix-in some commands from the Socialtext fixture
# XXX move bodies to SocialBase?
{
    require Socialtext::WikiFixture::Socialtext;
    no warnings 'redefine';
    *st_admin = \&Socialtext::WikiFixture::Socialtext::st_admin;
    *st_config = \&Socialtext::WikiFixture::Socialtext::st_config;
}

=head1 NAME

Socialtext::WikiFixture::HealthReport - Fixture class that processes reports

=cut

=head2 init()

Initializes the object, and logs into the Socialtext server.

=cut

sub init {
    my ($self) = @_;
    $self->{mandatory_args} = [qw(username password)];
    $self->{workspace} ||= "test-data";
    $self->{_widgets}={};
    $self->SUPER::init;
}
                        

=head2 st_create_health_report 

Runs the appliance health batch job as super-user.  Will only work on a vz.

Sets the variables:

health_report_url: The url output of the call to the batch job that is the local report URL
health_name: the english pagename that will be set on local health reports workspace when the report is completed

=cut


sub st_create_health_report {
    my $self = shift();
    my $output = `sudo /usr/sbin/st-appliance-health-report --local-only --today`;
    $output=~s/\n//g;

    if ( ($output=~/Uploaded/) && ($output=~/_health.+\d\d\d\d.+\d+.+\d+$/)) {
        ok(1, 'output of st-appliance-health-report indicates the report was created');
        if ($output=~/Uploaded: (http.+\d\d\d\d\_\d+\_\d+$)/) {
            my $url = $1;
            $self->{health_report_url}=$1;
        } else {
            ok(0, "failed in match 1 of st_create_health_report: '$output'\n");
        }

        if ($output=~/(\d\d\d\d\_\d+\_\d+$)/) {
             my $date_stamp = $1;
             $date_stamp=~s/_/-/g;
             my $pagename = $ENV{WIKIEMAIL} . ' - Health - ' . $date_stamp;
             $self->{health_name} = $pagename;
         } else {
             ok(0, "failed in match 2 of st_create_health_report: '$output'\n");
         }
    } else {
         ok(0, 'output of st-appliance-health-report looks ... wrong' . "($output)");
    }
}

=head1 AUTHOR

Matthew Heusser << <matt.heusser at socialtext.com> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-socialtext-editpage at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Socialtext-WikiTest>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Socialtext::WikiFixture::HealthReport

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2011 Socialtext, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
