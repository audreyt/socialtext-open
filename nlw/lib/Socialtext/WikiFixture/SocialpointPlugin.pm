# @COPYRIGHT@
package Socialtext::WikiFixture::SocialpointPlugin;
use strict;
use warnings;
use base 'Socialtext::WikiFixture::SocialRest';
use Socialtext::SQL qw/sql_singlevalue/;
use Socialtext::Pluggable::Plugin::Socialpoint;
use Test::More;

sub sp_password_is {
    my $self = shift;
    my $workspace_name = shift;
    my $expected_pw = shift;

    my $user_set_id = Socialtext::Workspace->new(name => $workspace_name)->user_set_id;
    my $crypted_pw = sql_singlevalue(<<EOT, $user_set_id);
SELECT value FROM user_set_plugin_pref
    WHERE user_set_id = ?
      AND plugin = 'socialpoint'
      AND key = 'password'
EOT

    my $plugin = Socialtext::Pluggable::Plugin::Socialpoint->new;
    my $got_pw = $plugin->decrypt_hex($crypted_pw);
    is $got_pw, $expected_pw, 'socialpoint password';
}

1;
