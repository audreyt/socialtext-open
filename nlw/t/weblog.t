#!perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 15;
fixtures(qw( empty ));

use DateTime;
use Socialtext::Pages;
my $hub = new_hub('empty');

basics_and_ordering: { 
    my $first_post = Socialtext::Page->new( hub => $hub )->create(
        title      => 'Happy Y2K!',
        content    => 'No systems seemed to crash.',
        categories => ['Dot Com Blog'],
        date       => DateTime->new( year => 2000, month => 1, day => 1 ),
        creator    => $hub->current_user,
    );

    my $second_post = Socialtext::Page->new( hub => $hub )->create(
        title      => 'Going public tomorrow!',
        content    => 'We are all so excited to be changing the world /and/ getting rich!',
        categories => ['Dot Com Blog'],
        date       => DateTime->new( year => 2000, month => 2, day => 1 ),
        creator    => $hub->current_user,
    );

    my $third_post = Socialtext::Page->new( hub => $hub )->create(
        title      => 'Looking for job',
        content    => 'Anyone looking for an HTML programmer?  I got skills!',
        categories => ['Dot Com Blog'],
        date       => DateTime->new( year => 2000, month => 2, day => 4 ),
        creator    => $hub->current_user,
    );

    $second_post->edit_rev();
    $second_post->append("What happened to the going public thing?\n");
    $second_post->store();

    # Note that the following is actually testing a Socialtext::CategoryPlugin
    # method, but the blog is the only thing that uses the non-default right
    # now:

    my $dot_com = 'Dot Com Blog';
    my @update_order = ($second_post, $third_post, $first_post);
    assert_dot_com_order("'update' order", \@update_order, 10, 'update');
    assert_dot_com_order("default to 'update' order", \@update_order, 10);
    assert_dot_com_order("limit", [@update_order[0,1]], 2);

    my @create_order = ($third_post, $second_post, $first_post);
    assert_dot_com_order("'create' order", \@create_order, 10, 'create');
}

sub assert_dot_com_order {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $name       = shift;
    my $expected   = shift;
    my $limit      = shift;
    my $sort_style = shift;

    my @actual = $hub->category->get_pages_for_category(
        'Dot Com Blog', $limit, $sort_style
    ); 

    is scalar(@actual), scalar(@$expected), "counts were correct for $name";

    my @expected_ids = map { $_->id } @$expected;
    my @actual_ids   = map { $_->id } @actual;
    is join(',', @actual_ids), join(',', @expected_ids), $name;
}

compute_redirect: {
    my $page = $hub->pages->new_from_name('foo');
    my $page_uri = $page->uri;
    
    for my $case (
        {
            # (undefs for caller_action and category)
            expected => $page_uri,
        },  
        {
            caller_action => 'weblog_donkey',
            tag => 'Donkey Blog',
            expected => "index.cgi?action=blog_donkey;tag=Donkey%20Blog#$page_uri"
        },  
        {
            caller_action => 'blog_donkey',
            tag => 'Donkey Blog',
            expected => "index.cgi?action=blog_donkey;tag=Donkey%20Blog#$page_uri"
        },  
        {
            caller_action => 'weblog_donkey',
            category => 'Donkey Blog',
            expected => "index.cgi?action=blog_donkey;tag=Donkey%20Blog#$page_uri"
        },  
        {
            caller_action => 'i_do_not_begin_with_weblog',
            category => 'Some page',
            expected => "index.cgi?action=i_do_not_begin_with_weblog"
        },
    ) {
        my $actual = Socialtext::WeblogPlugin->compute_redirection_destination(
            page => $page,
            caller_action => $case->{caller_action},
            ($case->{tag}
                ? (tag      => $case->{tag})
                : (category => $case->{category})),
        );
        is $actual, $case->{expected}, 'compute_redirection_destination';
    }

    my $path = $hub->weblog->compute_redirection_destination_from_url(
        'http://foo.socialtext.com/bar/index.cgi?action=display;page_name=baz;caller_action=weblog_display;tag=buckle;js=show_edit_div#'
    );
    is $path, 'index.cgi?action=blog_display;tag=buckle#baz',
        'compute_redirection_destination_from_url';
    $path = $hub->weblog->compute_redirection_destination_from_url(
        'http://foo.socialtext.com/bar/index.cgi?action=display;page_name=baz;caller_action=blog_display;tag=buckle;js=show_edit_div#'
    );
    is $path, 'index.cgi?action=blog_display;tag=buckle#baz',
        'compute_redirection_destination_from_url';

}
