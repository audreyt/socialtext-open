# @COPYRIGHT@
package Socialtext::WeblogArchive;
use strict;
use warnings;

use base 'Socialtext::WeblogPlugin';
use Socialtext::l10n qw(loc __);
use Socialtext::Timer qw/time_scope/;
use Socialtext::SQL qw/sql_execute/;

use Class::Field qw( const );

const class_id => 'weblog_archive';
const class_title => __('class.weblog_archive');

sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add(action => 'weblog_archive_html');
}

sub weblog_archive_html {
    my $self = shift;
    my $blog_category = shift;
    $blog_category ||= $self->current_blog;
    my $archive = $self->assemble_archive($blog_category);

    $self->template_process(
        'weblog_archive_box_filled.html',
        archive  => $archive,
        category => $self->current_blog_escape_uri,
    );
}

sub assemble_archive {
    my $self = shift;
    my $t = time_scope 'assemble_archive';
    my $blog_category = shift;


    my %archive;
    my $by_create = $self->hub->current_workspace->sort_weblogs_by_create;
    my $entries = $self->_get_entries_faster($blog_category, $by_create);
    foreach my $entry_number (0 .. $#{$entries}) {
        my $entry = $entries->[$entry_number];
        my $date  =   $by_create
                    ? $self->get_date_of_create($entry)
                    : $self->get_date_of_update($entry);
        my $month = $archive{$date->{year}}->{$date->{month}} ||= {};
        $month->{name}  ||= $date->{month_name};
        $month->{start} = $entry_number if not defined $month->{start};
        $month->{limit}++;
    }
    return \%archive;
}

sub _get_entries_faster {
    my ($self, $blog, $by_create) = @_;
    my $t = time_scope '_get_entries_faster';
    my $ws_id = $self->hub->current_workspace->workspace_id;
    my $sth;
    my $order_by = $by_create ? 'create_time' : 'last_edit_time';
    if (lc $blog eq 'recent changes') {
        $sth = sql_execute(qq{
            SELECT create_time, last_edit_time
              FROM page
             WHERE workspace_id = ?
               AND NOT deleted
             ORDER BY $order_by DESC
             }, $ws_id);
    }
    else {
        $sth = sql_execute(qq{
            SELECT create_time, last_edit_time
              FROM page
              JOIN page_tag USING (page_id, workspace_id)
             WHERE workspace_id = ?
               AND NOT deleted
               AND LOWER(page_tag.tag) = LOWER(?)
             ORDER BY $order_by DESC
             }, $ws_id, $blog);
    }
    my $pages = $sth->fetchall_arrayref();
    my @entries;
    for my $page (@$pages) {
        push @entries, {
            create_time    => $page->[0],
            last_edit_time => $page->[1],
        }
    }
    return \@entries;
}

sub get_date_of_update {
    my $self = shift;
    my $entry = shift;
    my ($year, $month) = split /-/, $entry->{last_edit_time};
    return $self->_date($year, $month);
}

sub get_date_of_create {
    my $self = shift;
    my $entry = shift;
    my ($year, $month) = split /-/, $entry->{create_time};
    return $self->_date($year, $month);
}

{
    my @month_names = qw[
        date.january date.february date.march
        date.april   date.may      date.june
        date.july    date.august   date.september
        date.october date.november date.december
    ];
    sub _date {
        my ($self, $year, $month) = @_;
        $month =~ s/^0//;
        my $date = {
            year       => $year,
            month      => $month,
            month_name => loc($month_names[$month - 1]),
        };
        return $date;
    }
}

sub box_title { 'Blog Archive' }

1;
