#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 23;
# Fixtures:
# - we're destructive; we create pages but don't clean up after ourselves.
fixtures(qw( admin_with_extra_pages destructive ));

my $hub = new_hub('admin');
my $pages = $hub->pages;
my $creator = Socialtext::User->new( username => 'devnull1@socialtext.com' );

{
    Socialtext::Page->new( hub => $hub )
        ->create(
            title   => 'simple', content => 'as can be',
            creator => $creator,
        );
    my $simple = $pages->new_from_name('simple');
    is $simple->content, "as can be\n", 'basic usage';
}

{
    Socialtext::Page->new( hub => $hub )->create(
        title      => 'basic usage',
        content    => 'with category',
        categories => ['test'],
        creator => $creator,
    );
    my $basic = $pages->new_from_name('basic usage');
    is $basic->tags->[0], 'test', 'category saved';
}

{
    my $sample = $hub->pages->new_from_name('FormattingTest');
    $sample->edit_rev;
    $sample->doctor_links_with_prefix('Foozle');
    like $sample->content, qr/\[FoozleFormattingToDo\]/,
        'doctor_links_with_prefix';
    like $sample->content, qr/\[wiki 101\]}/,
        'do not doctor interwiki links';
    $sample->doctor_links_with_prefix('Foozle');
    like $sample->content, qr/\[FoozleFormattingToDo\]/,
        'doctor_links_with_prefix refuses to double-prefix';

    for my $input ( Socialtext::File::all_directory_files('t/extra-pages') ) {
        my $content = Socialtext::File::get_contents("t/extra-pages/$input");
        $sample->content($content);
        $sample->doctor_links_with_prefix('');
        is $sample->content, $content,
            'doctor_links harmlessness ' . $input;
    }
}

{    # create time twiddling
    my $expected_date = DateTime->from_epoch(epoch => 1231231231);
    my $stringified_expected = '2009-01-06 08:40:31 GMT';
    Socialtext::Page->new( hub => $hub )->create(
        title   => 'dated',
        content => '(irrelevant)',
        date    => $expected_date,
        creator => $creator,
    );
    my $page = $hub->pages->new_from_name('dated');
    is $page->datetime_utc, $stringified_expected,
        'metadata date - needed for display';
}
