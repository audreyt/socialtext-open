#!perl
# @COPYRIGHT@
use Test::Socialtext;

use strict;
use warnings;

fixtures( 'db' );

BEGIN {
    eval 'use Test::MockObject';
    plan skip_all => 'This test requires Test::MockObject' if $@;
    plan tests => 5;
}

use Socialtext::Rest::Collection;

my @data = (
    { title => qq#Test's Workspace#, name => 'test'},
    { title => qq#Auth-to-edit Wiki#, name => 'auth-to-edit'},
    { title => qq#Foobar Workspace#, name => 'foobar'},
    { title => qq#Another of Test's Workspace#, name => 'tester'},
    { title => qq#Intel's Athelon Workspace#, name => 'athelon'},
    { title => qq#A Red Workspace#, name => 'red'},
    { title => qq#A Red Athelon Workspace#, name => 'athelon-2'},
);

my $rest = Test::MockObject->new();
my $query = Test::MockObject->new();
my $user = Test::MockObject->new();
$user->mock('user_id', sub { 1 });
$query->mock('param', sub { return undef; } );
$rest->mock('query', sub { return $query; } );
$rest->mock('user', sub { return $user; } );

ONE_FILTER: {
    my $collection = new Socialtext::Rest::Collection($rest,);

    is( scalar(keys(%{$collection->filter_spec()})), 3, 'Collection has three filter specs' );
}

CREATE_FILTER_NO_FILTERS: {
    my $collection = new Socialtext::Rest::Collection($rest,);

    my $filter = $collection->create_filter;

    my @results = &$filter(@data);

    is( scalar(@results), 7, 'Got the correct number of unfiltered entries' );
}

CREATE_FILTER_1_FILTER: {
    my $query = Test::MockObject->new();
    $query->mock('param', 
        sub { return $_[1] eq 'name_filter' ? 'tester' : undef } );
    $rest->mock('query', sub { return $query; } );

    my $collection = new Socialtext::Rest::Collection($rest,);

    my $filter = $collection->create_filter;

    my @results = &$filter(@data);

    is( scalar(@results), 1, 'Only one workspace with name tester' );
}

CREATE_FILTER_1_FILTER_3_MATCHES: {
    my $query = Test::MockObject->new();
    $query->mock('param', sub { return '\ba'; } );
    $query->mock('param', 
        sub { return $_[1] eq 'name_filter' ? '\ba' : undef } );
    $rest->mock('query', sub { return $query; } );

    my $collection = new Socialtext::Rest::Collection($rest,);

    my $filter = $collection->create_filter;

    my @results = &$filter(@data);

    is( scalar(@results), 3, 'Three workspaces starting with a' );
}

CREATE_FILTER_2_FILTERS: {
    my $query = Test::MockObject->new();
    $query->mock('param', sub { 
        return $_[1] eq 'filter' ? '\ba' : 'Intel'; 
    } );
    $rest->mock('query', sub { return $query; } );

    my $collection = new Socialtext::Rest::Collection($rest,);
    $collection->{FilterParameters} = {
        'filter' => 'name',
        'filter_title' => 'title',
    };

    my $filter = $collection->create_filter;
    my @results = &$filter(@data);
    is( scalar(@results), 1, 'Only one workspace with a name starting with a and Intel in the title' );
}
