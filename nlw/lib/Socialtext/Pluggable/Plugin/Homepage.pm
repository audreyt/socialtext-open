package Socialtext::Pluggable::Plugin::Homepage;
use Moose;
use Socialtext::HTTP qw(:codes);
use URI::Escape;
use namespace::clean -except => 'meta';

extends 'Socialtext::Pluggable::Plugin';

use constant scope => 'always';
use constant hidden => 1;
use constant paid => 0;

sub register {
    my $class = shift;
    $class->add_hook('action.homepage' => 'homepage');
}

sub homepage {
    my $self = shift;

    my $wksp = $self->current_workspace;
    my $blog = $self->current_workspace->homepage_weblog;
    my $redirect = '';

    if (!$wksp || !$wksp->real()) {
        $redirect = '/';
    }
    elsif ($blog) {
        $redirect = '?action=blog_display;category='
            . URI::Escape::uri_escape_utf8($blog);
    }
    else {
        my $title = $wksp->title;
        $redirect = $self->hub->pages->new_from_name($title)->full_uri;
    }

    $self->redirect($redirect);
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0 );
1;
