#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext tests => 18;
use Socialtext::RevisionPlugin;

my @before_tags = qw( aaa bbb ccc );
my @after_tags = qw( aaa ccc );

my $diff = Socialtext::SideBySideDiff->new();

my $text = $diff->_tag_diff(
    old_tags => \@before_tags,
    new_tags => \@after_tags,
    highlight_class => 'before',
);
is $text, 'aaa, ccc', 'missing tag does not show up'; 

$text = $diff->_tag_diff(
    new_tags => \@before_tags,
    old_tags => \@after_tags,
    highlight_class => 'after',
);
is 
    $text, 
    "aaa, <span class='after'>bbb</span>, ccc", 
    'deleted tag highlighted properly'; 

run {
    my $case = shift;

    is(
        Socialtext::WikitextSideBySideDiff->compare_chunk(
            $case->before, $case->after, 'before'
        ),
        $case->left,
        $case->name . ' - left'
    );

    is(
        Socialtext::WikitextSideBySideDiff->compare_chunk(
            $case->before, $case->after, 'after'
        ),
        $case->right,
        $case->name . ' - right'
    );

    my $html = Socialtext::WikitextSideBySideDiff->compare(
        $case->before,
        $case->after
    );
    ok $html ne '', "makes sure compare() is not totally dumb";

    my @split = Socialtext::WikitextSideBySideDiff->split_into_diffable_divs(
        $case->before,
        $case->after
    );
    ok scalar(@split), "make sure split_into_diffable_divs isn't totally dumb";
};

sub incidental_html {
    my $text = shift;
    chomp $text;
    $text =~ s/\n/<br\/>\n/g;
    Socialtext::String::double_space_harden($text)
}

__DATA__
=== Typo fix
--- before: Tdoay I went to the store
--- after: Today I went to the store
--- left incidental_html
<span class='st-revision-compare-old'>Tdoay</span> I went to the store
--- right incidental_html
<span class='st-revision-compare-new'>Today</span> I went to the store

=== Sentence add
--- before: Today I went to the store.
--- after: Today I went to the store.  I bought some milk.
--- left incidental_html: Today I went to the store.
--- right incidental_html: Today I went to the store<span class='st-revision-compare-new'>.  I bought some milk</span>.

=== Paragraph swapout
--- before
Abc

Def
--- after
Abc

Ghi
--- left
Abc<br/>

<span class='st-revision-compare-old'>Def</span><br/>
--- right
Abc<br/>

<span class='st-revision-compare-new'>Ghi</span><br/>

=== Lost everything
--- before: seven sons, three daughters, seven thousand sheep, three thousand camels, five hundred yoke of oxen, and five hundred she-asses, and very many servants
--- after: 
--- left incidental_html
<span class='st-revision-compare-old'>seven sons, three daughters, seven thousand sheep, three thousand camels, five hundred yoke of oxen, and five hundred she-asses, and very many servants</span>
--- right incidental_html:

--- Note
We could test more, but at the moment, they're feeling more tedious than
helpful.
