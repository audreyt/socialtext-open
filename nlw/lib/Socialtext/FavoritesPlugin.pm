# @COPYRIGHT@
package Socialtext::FavoritesPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

use Class::Field qw( const );
use Socialtext::l10n qw(loc __);

const class_id => 'favorites';
const class_title => __('class.favorites');

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add(preference => $self->which_page_pref);
    #$registry->add(action => 'favorites_html');
}

sub which_page_pref {
    my $self = shift;
    my $p = $self->new_preference('which_page');
    my $title = $self->class_title;
    my $message = __('notepad.set-title');
    $p->query($message);
    $p->size(30);
    $p->type('input');
    $p->default_for_input(sub {
        my $self = shift;
        return loc("notepad.title=user", $self->hub->current_user->best_full_name);
    });
    $p->layout_over_under(1);
    return $p;
}

sub my_favorites_title {
    my $self = shift;
    $self->preferences->which_page->value
}

sub has_set_their_preference {
    my $self = shift;
    defined $self->my_favorites_title ? 1 : undef
}


sub favorites_edit_path {
    my $self = shift;
    $self->has_set_their_preference
      ? $self->actual_favorites_edit_path
      : $self->preference_edit_path
}

sub actual_favorites_edit_path {
    my $self = shift;
    $self->hub->helpers->page_edit_path($self->my_favorites_title)
}

sub preference_edit_path {
    my $self = shift;
    $self->hub->helpers->preference_path(
        'favorites',
        'layout_over_under' => 1
    );
}

sub favorites_content {
    my $self = shift;
    $self->has_set_their_preference
      ? $self->actual_favorites_content
      : ''
}

sub actual_favorites_content {
    my $self = shift;
    $self->hub->pages->new_from_name($self->my_favorites_title)->to_html
}

1;

