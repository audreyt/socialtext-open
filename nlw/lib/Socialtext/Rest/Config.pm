# @COPYRIGHT@
package Socialtext::Rest::Config;
use strict;
use warnings;
no warnings 'once';

use base 'Socialtext::Rest';
use YAML ();
use Socialtext::HTTP ':codes';
use Socialtext::Rest::Version;
use Socialtext::URI;
use Socialtext::JSON;
use Socialtext;
use Socialtext::AppConfig;
use Socialtext::Appliance::Config;
use Readonly;

Readonly my @PUBLIC_CONFIG_KEYS => qw(
    allow_network_invitation
    signals_size_limit
);

sub allowed_methods { 'GET' }

sub make_getter {
    my ( $type, $render ) = @_;
    return sub {
        my ( $self, $rest ) = @_;

        my $user = $rest->user;

        unless ($user->is_authenticated and !$user->is_deleted) {
            return $self->not_authorized();
        }

        my $appliance = Socialtext::Appliance::Config->new;

        $rest->header(-type => "$type; charset=UTF-8");

        my $config = {
            server_version => $Socialtext::VERSION,
            api_version => $Socialtext::Rest::Version::API_VERSION,
            desktop_update_url => $appliance->value('desktop_update_enabled')
                                    ? Socialtext::URI::uri( path => "/st/desktop/update" )
                                    : '',
            ( map { $_ => Socialtext::AppConfig->$_() } @PUBLIC_CONFIG_KEYS ),
        };

        $self->hub->pluggable->hook('nlw.get_rest_config', [$config]);

        # Get simple key/value pair without the "---" line
        local $YAML::UseHeader = 0;
        return $render->($config);
    };
}

*GET_text = make_getter( 'text/plain', \&YAML::Dump );
*GET_json = make_getter( 'application/json', \&encode_json );

1;
__END__

=head1 NAME

Socialtext::Rest::Config

=head1 SYNOPSIS

  GET /data/config

=head1 DESCRIPTION

Retrieves "public" config information from various parts of the application.

Supports C<text/plain> (which is actually YAML without the --- header) and
C<application/json> representations.

=cut
