# @COPYRIGHT@
package Socialtext::BreadCrumbsPlugin;
use strict;
use warnings;

use base 'Socialtext::Query::Plugin';

use Class::Field qw( const );
use File::Basename ();
use File::Path ();
use Socialtext::l10n qw(loc __);
use Socialtext::SQL qw/get_dbh sql_execute sql_txn/;
use Socialtext::Pages;
use Socialtext::Timer qw/time_scope/;
use Try::Tiny;

const class_id => 'breadcrumbs';
const class_title => __('class.breadcrumbs');
const cgi_class   => 'Socialtext::BreadCrumbs::CGI';

my $HOW_MANY = 25;

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add(action => 'breadcrumbs_html');
    $registry->add(action => 'breadcrumbs_list');
}

sub display_as_box {
    my $self = shift;
    my $p = $self->new_preference('display_as_box');
    $p->query(__('wiki.show-breadcrumbs-sidebox?') );
    $p->default(1);
    return $p;
}

sub how_many {
    my $self = shift;
    my $p = $self->new_preference('how_many');
    $p->query(__('wiki.sidebox-number-of-breadcrumbs?'));
    $p->type('pulldown');
    my $choices = [
        3 => 3,
        5 => 5,
        7 => 7,
        10 => 10,
        15 => 15,
    ];
    $p->choices($choices);
    $p->default(7);
    return $p;
}

sub box_on {
    my $self = shift;
    $self->preferences->display_as_box->value;
}

sub breadcrumbs_list {
    my $self = shift;

    my %sortdir = %{ $self->sortdir };

    $self->display_results(
        \%sortdir,
        display_title => loc('page.breadcrumbs'),
        unplug_uri    => "?action=unplug;breadcrumbs=1",
        unplug_phrase => loc('info.unplug-breadcrumbs'),
        hide_sort_widget => 1,
    );
}

# Don't use a cached result since the set always quite small.
sub read_result_set { return $_[0]->default_result_set; }
sub write_result_set { 1 }

sub default_result_set {
    my $self = shift;
    $self->result_set($self->new_result_set);
    $self->push_result($_) for ($self->breadcrumb_pages());
    $self->result_set->{hits} = @{$self->result_set->{rows}};
    return $self->result_set;
}

sub breadcrumb_pages {
    my $self        = shift;
    return  @{ $self->_load_trail };
}

sub new_result_set {
    my $self = shift;
    my $rs = $self->SUPER::new_result_set();
    $rs->{predicate} = 'action=breadcrumbs_list';
    return $rs;
}

sub breadcrumbs_html {
    my $self = shift;
    $self->template_process('breadcrumbs_box_filled.html',
        breadcrumbs => $self->get_crumbhash,
    );
}

sub get_crumbhash {
    my $self = shift;

    return [
        map {
            {
                page_title => $_->title,
                page_uri   => $_->uri,
                page_full_uri => $_->full_uri,
            }
        } @{ $self->_load_trail }
    ];
}

sub drop_crumb {
    my $self = shift;
    my $page = shift;
    return unless $page->exists;

    my $t = time_scope 'drop_crumb';
    my $user_id = $self->hub->current_user->user_id;
    my $wksp_id = $self->hub->current_workspace->workspace_id;
    my $page_id = $page->id;
    sql_txn {
        my $sth = sql_execute(q{
            UPDATE breadcrumb SET last_viewed = 'now'::timestamptz
              WHERE viewer_id = ? AND workspace_id = ? AND page_id = ?
        }, $user_id, $wksp_id, $page_id);
        if ($sth->rows == 0) {
            sql_execute(q{
                INSERT INTO breadcrumb VALUES (?,?,?,'now'::timestamptz)
            }, $user_id, $wksp_id, $page_id);
            sql_execute(q{
                DELETE FROM breadcrumb
                  WHERE viewer_id = $1 AND workspace_id = $2 
                    AND page_id NOT IN (
                        SELECT page_id FROM breadcrumb
                         WHERE viewer_id = $1 AND workspace_id = $2
                         ORDER BY last_viewed DESC
                         LIMIT $3
                    )
            }, $user_id, $wksp_id, $HOW_MANY);
        }
    };
}

sub _load_trail {
    my $self = shift;

    my $t = time_scope 'load_crumbs';
    my $hub = $self->hub;
    my $ws_id = $hub->current_workspace->workspace_id;
    my $sth = sql_execute(q/
       SELECT /.Socialtext::Page::SELECT_COLUMNS_STR.q/
         FROM page 
         JOIN "Workspace" USING (workspace_id)
         JOIN breadcrumb  USING (workspace_id, page_id)
        WHERE workspace_id = ?
          AND viewer_id = ?
          AND NOT page.deleted
        ORDER BY last_viewed DESC
    /, $ws_id, $hub->current_user->user_id);
    return [
        map { Socialtext::Page->_new_from_row($_) }
        map { $_->{hub} = $hub; $_ }
        @{ $sth->fetchall_arrayref({}) }
    ];
}

######################################################################
package Socialtext::BreadCrumbs::CGI;
       
use base 'Socialtext::Query::CGI';
use Socialtext::CGI qw( cgi );

1;
