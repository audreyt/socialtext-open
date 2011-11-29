package Socialtext::Pluggable::Plugin::Default;
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::l10n qw(loc __);
use Socialtext::BrowserDetect;
use Socialtext::Workspace;

use base 'Socialtext::Pluggable::Plugin';
use Class::Field qw(const field);

sub scope { 'always' }

sub register {
    my $class = shift;

    # Priority 99 indicates these hooks should be loaded last.

    # Socialtext People Hooks
    $class->add_hook(
        'template.user_avatar.content' => 'user_name',
        priority                       => 99,
    );
    $class->add_hook(
        'template.user_href.content' => 'user_href',
        priority                     => 99,
    );
    $class->add_hook(
        'template.user_name.content' => 'user_name',
        priority                     => 99,
    );
    $class->add_hook(
        'template.user_small_photo.content' => 'user_photo',
        priority                            => 99,
    );
    $class->add_hook(
        'template.user_photo.content' => 'user_photo',
        priority                      => 99,
    );
    $class->add_hook(
        'wafl.user' => 'user_name',
        priority    => 99,
    );
}

sub user_name {
    my ($self, $username) = @_;
    return $self->best_full_name($username);
}

sub user_href { '' }
sub user_photo { '' }

1;
