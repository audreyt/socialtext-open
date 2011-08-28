# @COPYRIGHT@
package Socialtext::Formatter::Viewer;
use strict;
use warnings;

use base 'Socialtext::Base';

use Class::Field qw( const field );
use Socialtext::Formatter::LinkDictionary;
use Socialtext::Formatter::Parser;
use Socialtext::Statistics 'stat_call';
use Socialtext::Timer qw/time_scope/;
use Readonly;
use Socialtext::l10n qw(loc __);

const class_id => 'viewer';
const class_title  => __('class.viewer');
use constant NO_PARAGRAPH => 1;
use constant WITH_PARAGRAPH => 0;

field page_id         => '';
field url_prefix      => '';

field parser => -init =>
    'Socialtext::Formatter::Parser->new(table=>$self->hub->formatter->table,wafl_table=>$self->hub->formatter->wafl_table);';
field link_dictionary => -init =>
    'Socialtext::Formatter::LinkDictionary->new()';

Readonly my $MAX_SIZE => 500_000;

our $in_paragraph = 0;
sub text_to_html {
    my $self = $_[0];
    my $text = ref($_[1]) ? $_[1] : \$_[1];
    $in_paragraph = 0;
    $self->to_html( $self->parser->text_to_parsed($text), $self->hub );
}

sub text_to_non_wrapped_html {
    my $self = $_[0];
    my $text = ref($_[1]) ? $_[1] : \$_[1];
    my $paragraph = $_[2] || WITH_PARAGRAPH;

    $in_paragraph = 0;
    my $html = $self->to_non_wrapped_html(
        $self->parser->text_to_parsed($text), $self->hub );
    if ($paragraph) {
        $html =~ s/^<p>//;
        $html =~ s/<\/p>\s*$//;
    }
    return $html;
}

sub SELF () { 0 }
sub TREE () { 1 }
sub HUB  () { 2 }

# XXX the variable assignments happening here make this sub 
# less performant than it could be
sub to_non_wrapped_html {
    my $html = $_[TREE]->html();

    if ($_[TREE]->formatter_id eq 'p') {
        $in_paragraph = 1;
    }
    # get the internal units
    for my $unit ( @{ $_[TREE]->units } ) {
        if ( ref ($unit) ) {
            $unit->{hub} = $_[HUB];
            $html .= $_[SELF]->to_html($unit, $_[HUB]);
        }
        else {
            $html .= $_[TREE]->escape_html($unit);
        }
    }

    $html = $_[TREE]->text_filter($html);
    $in_paragraph = 0;
    return $html;
}

# XXX the variable assignments happening here make this sub 
# less performant than it could be
sub to_html {
    my $html = $_[TREE]->html();

    if ($_[TREE]->formatter_id eq 'p') {
        $in_paragraph = 1;
    }
    # get the internal units
    for my $unit ( @{ $_[TREE]->units } ) {
        if ( ref ($unit) ) {
            $unit->{hub} = $_[HUB];
            $html .= $_[SELF]->to_html($unit, $_[HUB]);
        }
        else {
            $html .= $_[TREE]->escape_html($unit);
        }
    }

    $html = $_[TREE]->html_start()
        . $_[TREE]->text_filter($html)
        . $_[TREE]->html_end();
    $in_paragraph = 0;
    return $html;
}

sub to_text {
    my $self = shift;
    my $tree = shift;
    $tree->get_text;
}

# special
sub process {
    my $self = $_[0];
    my $text = ref($_[1]) ? $_[1] : \$_[1];
    my $page = $_[2];

    my $timer = time_scope('viewer_process');
    my $large_formatted = $self->_large_check($text);
    return $large_formatted if $large_formatted;

    $self->page_id($page->page_id) if $page;

    my $parsed = $page
        ? $self->parser->get_cached_tree($text, $page)
        : $self->parser->text_to_parsed($text);

    # Return values are optimized-for heavily in Perl; do not assign this
    # result to anything before returning.
    return $self->to_html($parsed, $self->hub);
}

sub _detab {
    my $self = shift;
    my $text = shift;
    $text
        =~ s/(?mi:^tsv:\s*\n)((.*(?:\t| {3,}).*\n)+)/$self->_detab_table($1)/eg;
    $text;
}

sub _detab_table {
    my $self = shift;
    my $text = shift;

    $text =~ s/(\t| {3,})/|/g;
    $text =~ s/^/|/gm;
    $text =~ s/\n/|\n/gm;

    return $text;
}

sub _large_check {
    my $self = shift;
    my $text_ref = shift;
    my $length = length $$text_ref;
    return if $length < $MAX_SIZE;

    my $html = $self->html_escape( $$text_ref );
    $html =~ s/\n/<br \/>\n/g;

    my $size_str = _commafy_number($MAX_SIZE);
    return join '',
        qq{<p style="color:red">Text not formatted. Exceeds $size_str characters. ($length)</p>\n},
        $html;
}

# EXTRACT: this probably belongs in a Helper, Number or String-type class
sub _commafy_number {
    my $number = shift;

    1 while $number =~ s/(\d)(\d\d\d)(,|$)/$1,$2$3/;

    return $number;
}

1;

__END__

=head1 NAME

Socialtext::Formatter::Viewer - Transform a tree of Units into HTML

=head1 SYNOPSIS

    # text_to_html
    my $html = $hub->viewer->text_to_html($wiki_text);

    # parsed tree to html
    my $parser = Socialtext::Formatter::Parser->new(
        table = $hub->formatter->table,
        wafl_table = $hub->formatter->wafl_table,
    );
    my $units = $parser->text_to_parsed('Some text to parse');
    my $html = $hub->viewer->to_html($units);

=head1 DESCRIPTION

A viewer tranforms a tree of L<Socialtext::Formatter::Unit> into other
forms. At this point it only transforms into HTML.

=head1 METHODS

(TODO)

=over 4

=item text_to_html

Turn some wikitext into HTML, hiding the details.

=item to_html

Turn a tree of L<Socialtext::Formatter::Unit> into HTML.

=item process

Utilize caching while turning an L<Socialtext::Page> into HTML.

=back

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., All Rights Reserved.

=cut
