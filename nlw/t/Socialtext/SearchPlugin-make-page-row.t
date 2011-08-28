#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 5;
use Socialtext::SearchPlugin;
use Socialtext::Page;

fixtures(qw( db ));

my $hub = create_test_hub();

my $Singapore = join '', map { chr($_) } 26032, 21152, 22369;

my $regular_page = Socialtext::Page->new(hub=>$hub)->create(
    title   => 'Start Here',
    content => 'hello',
    creator => $hub->current_user,
);

my $utf8_page = Socialtext::Page->new(hub=>$hub)->create(
    title => $Singapore,
    content => 'hello',
    creator => $hub->current_user,
);

my $page_uri = $utf8_page->uri;

ok( keys(%{make_page_row($page_uri)}),
    'passing an encoded utf8 page uri returns hash with keys' );
ok( keys(%{make_page_row($Singapore)}),
    'passing utf8 string is mapped to a uri, returns the hash' );
ok( !keys(%{make_page_row('this page does not exist')}),
    'non existent page returns empty hash' );
ok( keys(%{make_page_row('start_here')}),
    'normal existing page returns hash with keys' );
# sigh, osx doesn't care about case in filenames as much as we might like...
ok( keys(%{make_page_row('Start Here')}),
    'existing page as name returns the hash');

sub make_page_row {
    my $uri_candidate = shift;
    my $output = $hub->search->_make_row(
        FakePageHit->new(
            $uri_candidate,
            $hub->current_workspace->name
        )
    );
    return $output;
}

package FakePageHit;

sub new {
    my ( $class, $page_uri, $workspace_name ) = @_;
    return bless { 
        page_uri => $page_uri, 
        workspace_name => $workspace_name, 
        snippet => "... I'm a snippet ...",
        hit => { score => 100 },
    }, $class;
}

sub page_uri {
    my $self = shift;
    return $self->{page_uri};
}

sub workspace_name {
    my $self = shift;
    return $self->{workspace_name};
}

sub snippet {
    my $self = shift;
    return $self->{snippet};
}

sub hit {
    my $self = shift;
    return $self->{hit};
}
1;
