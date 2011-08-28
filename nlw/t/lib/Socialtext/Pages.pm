package Socialtext::Pages;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::MockBase';
use unmocked 'Data::Dumper';
use unmocked 'Class::Field', 'field';
use Socialtext::Page;

field 'hub';

sub new_from_name {
    my $self = shift;
    my $title = shift || '';
    my $id = lc($title); # TODO: make this Socialtext::String::title_to_id
    my $page = $self->new_page($id);
    $page->title($title);
    return $page;
}

sub By_seconds_limit { [] }
sub all_ids { }

sub show_mouseover { 1 }

sub title_to_uri { return $_[1] }

field current => -init => '$self->new_page("welcome")';

{
    my %MockPages;
    sub StoreMocked {
        my $class = shift;
        my $page = shift;
        $MockPages{$page->id} = $page;
    }
    sub new_page {
        my $self = shift;
        my $id = shift;
        my $page = $MockPages{$id};
        if (!$page) {
            $page = Socialtext::Page->new(id => $id);
        }
        $page->{hub} = $self->hub;
        return $page;
    }
}

sub page_exists_in_workspace { 1 }

1;
