# @COPYRIGHT@
package Socialtext::HitCounterPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

use Class::Field qw( const );
use Socialtext::SQL qw/sql_singlevalue sql_execute/;

sub class_id { 'hit_counter' }

sub get_page_counter_value {
    my $self = shift;
    my $page = shift;

    return sql_singlevalue(
        "SELECT views FROM page WHERE workspace_id = ? AND page_id = ?",
        $self->hub->current_workspace->workspace_id, $page->id,
    );
}

sub hit_counter_increment {
    my $self = shift;
    my $action = $self->hub->action || '';

    return unless $action eq 'display' or $action eq 'display_page';

    sql_execute(
        "UPDATE page SET views=views+1 WHERE workspace_id = ? AND page_id = ?",
        $self->hub->current_workspace->workspace_id,
        $self->hub->pages->current->id,
    );
}

1;

