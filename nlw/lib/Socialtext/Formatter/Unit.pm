# @COPYRIGHT@
package Socialtext::Formatter::Unit;
use strict;
use warnings;

use base 'Socialtext::Base';

use Class::Field qw( const field );
use Socialtext::Authz;

const formatter_id     => '';
const html_start       => '';
const html             => '';
const html_end         => '';
const contains_blocks  => [];
const contains_phrases => [];

# stub 'pattern_start'; # XXX messes multiple inheritance
const pattern_end => qr/.*?/;

### These are the context used when units are turned to html

# XXX pulling these out so we can consider how to replace them
field template        => -init => '$self->hub->template';

field authz           => -init => 'Socialtext::Authz->new';

field current_workspace        => -init => '$self->hub->current_workspace';
field current_workspace_name   => -init => '$self->hub->current_workspace->name';
# used for workspace access permission
field current_user    => -init => '$self->hub->current_user';
# XXX would viewer->page_id be okay here?
field current_page_id => -init => '$self->hub->pages->current->id';
field url_prefix      => -init => '$self->hub->viewer->url_prefix';
###

field text             => '';
field units            => [];
field start_offset     => 0;
field start_end_offset => 0;

# XXX this field is never used
#field end_start_offset => 0;
field end_offset => 0;
field matched    => '';
field -weak      => 'next_unit';
field -weak      => 'prev_unit';

sub match {
    my $self = shift;
    my $text = shift;
    my $orig_text = $text;
    my $match = $text =~ $self->pattern_block;
    return unless $match;
    $self->set_match;
}

sub set_match {
    my $self = shift;
    my ( $text, $start, $end ) = @_;
    $text  = $1    unless defined $text;
    $text  = ''    unless defined $text;
    $start = $-[0] unless defined $start;
    $end   = $+[0] unless defined $end;
    $self->text($text);
    $self->start_offset($start);
    $self->end_offset($end);
    return 1;
}

sub text_filter      { $_[1] }
sub escape_html      { $_[0]->html_escape( $_[1] ) }

sub to_html_escaped_text {
    my $self = shift;
    $self->escape_html( $self->get_text )
}

sub get_text {
    my $self = shift;
    my $inner;
    if ( @{ $self->units } ) {
        $inner = join '',
            map { ref($_) ? ($_->get_text ? $_->get_text : $_->matched) : $_; }
            @{ $self->units };
    }
    else {
        $inner = $self->matched;
    }
    $self->text_start . $inner . $self->text_end;
}

# XXX should be a way to determine these rather than beat on it like this
sub text_start {
    my $self = shift;''}
sub text_end   {
    my $self = shift;''}

################################################################################
package Socialtext::Formatter::Container;

use base 'Socialtext::Formatter::Unit';

sub contains_blocks {
    my $self = shift;
    Socialtext::Formatter->all_blocks;
}

################################################################################
package Socialtext::Formatter::Top;

use base 'Socialtext::Formatter::Container';
use Class::Field qw( const );

const formatter_id => 'top';
const html_start   => qq{<div class="wiki">\n};
const html_end     => "</div>\n";

################################################################################
package Socialtext::Formatter::Line;

use base 'Socialtext::Formatter::Unit';
use Class::Field qw( const );

const formatter_id => 'hr';

sub match {
    my $self = shift;
    my $text = shift;
    return unless $text =~ /^(--+)[^\n\S]*\n/m;
    $self->set_match;
}

sub html {
    my $self = shift;
    my $text = $self->units->[0];
    # XXX the match is not consuming
    # don't traverse
    $self->units([]);
    length($text) == 2       ? qq{<hr class="rule-short" />\n}
        : length($text) == 3 ? qq{<hr class="rule-medium" />\n}
        : qq{<hr />\n};
}

################################################################################
package Socialtext::Formatter::List;

use base 'Socialtext::Formatter::Container';
use Class::Field qw( const field );

const contains_blocks => [qw(li)];
field 'level';
field 'start_level';
field 'tag_stack' => [];
field 'nested_in';

sub match {
    my $self = shift;
    my $text = shift;
    my $bullet = $self->bullet;
    my $orig_text = $text;
    my $regex = qr/\A((?:^($bullet).*\n)(?:^\2(?!$bullet).*\n)*)[^\n\S]*/m;
    my $match = $text =~ $regex;
    return unless $match;
    $self->set_match;
    $self->level( length($2) );
    return 1;
}

sub html_start {
    my $self      = shift;
    my $next      = $self->next_unit;
    my $prev      = $self->prev_unit;
    my $tag_stack = $self->tag_stack;

    unless(ref($prev) and $prev->isa('Socialtext::Formatter::List')) {
        $self->nested_in($self->formatter_id);
        my ($last, $this) = ($self, $next);
        while(ref($this) and $this->isa('Socialtext::Formatter::List')) {
            if($this->level == 1) {
                $this->nested_in($this->formatter_id)
            } elsif($this->level >= $last->level) {
                $this->nested_in($last->nested_in)
            } else {
                $this->nested_in($this->formatter_id)
            }
            $last = $this;
            $this = $this->next_unit;
        }
    }

    $next->tag_stack($tag_stack)
        if ( ref($next) and $next->isa('Socialtext::Formatter::List') );
    my $level
        = defined $self->start_level ? $self->start_level : $self->level;

    push @$tag_stack, ( $self->html_end_tag ) x $level;

    return ( $self->html_start_tag x $level ) . "\n";
}

sub html_end {
    my $self = shift;
    my $tag_stack = $self->tag_stack;
    my $next      = $self->next_unit;
    my ( $end_number, $start_level, $newline );

    if ( ref($next) and $next->isa('Socialtext::Formatter::List') ) {
        if ( $self->level < $next->level ) {
            $end_number  = 0;
            $start_level = $next->level - $self->level;
            $newline     = "\n";
        }
        elsif ( $self->level == $next->level ) {
            $end_number  = 1;
            $start_level = 1;
            $newline     = "\n";
            if ( $next->nested_in ne $self->nested_in ) {
                # $end_number++;
            }
        }
        else {
            # $self->level > $next->level

            $end_number  = $self->level - $next->level;
            $start_level = 0;
            $newline     = "";
            if ( $next->nested_in ne $self->nested_in ) {
                $end_number++ if $end_number > 0;
                $start_level = 1;
            }
        }
        $next->start_level($start_level);
    }
    else {
        $end_number  = $self->level;
        $start_level = undef;
        $newline     = "\n";
    }

    return
        join( '',
        reverse splice( @$tag_stack, 0 - $end_number, $end_number ) )
        . $newline;
}

################################################################################
package Socialtext::Formatter::Ulist;

use base 'Socialtext::Formatter::List';
use Class::Field qw( const );

const formatter_id   => 'ul';
const html_start_tag => '<ul>';
const html_end_tag   => '</ul>';
const bullet         => '[\*\-\+]+(?=\ +|$)';

################################################################################
package Socialtext::Formatter::Olist;

use base 'Socialtext::Formatter::List';
use Class::Field qw( const );

const formatter_id   => 'ol';
const html_start_tag => '<ol>';
const html_end_tag   => '</ol>';
const bullet         => '\#+(?=\ +|$)';

################################################################################
package Socialtext::Formatter::Else;

use base 'Socialtext::Formatter::Container';
use Class::Field qw( const );

const formatter_id   => 'else';
const html_start_tag => '<p>';
const html_end_tag   => '</p>';
const pattern_block  => qr/^(.+)\n/;

################################################################################
package Socialtext::Formatter::Table;

use base 'Socialtext::Formatter::Container';
use Class::Field qw( const );

const formatter_id    => 'table';
const contains_blocks => [qw(tr)];
const pattern_block   => qr/\A(((^\|.*\| \n(?=\|))|(^\|.*\|  +\n)|(?s:^\|.*?\|\n))+)/m;

const html_end => "</table>\n";

sub match {
    my $self = shift;
    $self->SUPER::match(@_) or return;
    $self->{options} = '';
    if ($self->{text} =~ s/^\|\| *([^\|\n]+?) *\n//) {
        $self->{options} = $1;
    }
    return 1;
}

sub options {
    my $self = shift;
    return $self->{option_hash} if $self->{option_hash};

    my %options = (
        border => 1,
    );
    for my $opt (split ' ', $self->{options}) {
        if ($opt =~ /^([^:=]+)[:=](.*)$/) {
            my ($key, $val) = ($1, $2);
            $val = 0 if $val eq 'off' or $val eq 'false';
            $options{$key} = $val;
        }
        else {
            $options{$opt} = 1;
        }
    }

    return $self->{option_hash} = \%options;
}

sub html_start {
    my $self = shift;
    my $opts = $self->options;
    my $class = 'formatter_table';
    $class .= ' sort' if $opts->{sort};
    $class .= ' borderless' unless $opts->{border};
    my $borders = $opts->{border} ? 'border="1"' : '';
    qq{<table $borders style="border-collapse:collapse" options="$self->{options}" class="$class">\n};
}

################################################################################
package Socialtext::Formatter::TableRow;

use base 'Socialtext::Formatter::Container';
use Class::Field qw( const );

const formatter_id    => 'tr';
const contains_blocks => [qw(td)];
const pattern_block   => qr/(^\|.*?\|(?:\n| \n(?=\|)|  +\n))/sm;
const html_start      => "<tr>\n";
const html_end        => "</tr>\n";

################################################################################
package Socialtext::Formatter::TableCell;

use base 'Socialtext::Formatter::Unit';
use Class::Field qw( const field );

const formatter_id    => 'td';
const table_blocks    => [qw(wafl_block hr hx wafl_p ol ul indent p empty_p)];
const table_single_line_blocks => [qw(hx ol ul indent)];
field contains_blocks => [];
field contains_phrases => [];

const html_start => '<td>';
const html_end   => "</td>\n";

sub table_phrases { Socialtext::Formatter->all_phrases }

sub _escape_pipes {
    my $text = shift;
    $text =~ s/\|/\x{FFFC}/g;
    return $text;
}

sub _unescape_pipes {
    my $text = shift;
    $text =~ s/\x{FFFC}/\|/g;
    return $text;
}

sub match {
    my $self = shift;
    my $text = shift;

    # Replace pipe characters in {{...}} with U+FFFC (Object Replacement)
    # characters, to avoid an extremely rare core dump. {bz: 3247}
    $text =~ s/{{(.*?)}}/'{{' . _escape_pipes($1) . '}}'/eg;
    return unless $text =~ /(\|(\s*.*?\s*)\| *)(.*)/sm;

    $self->start_offset( $-[1] );
    $self->end_offset( $3 eq "\n" ? $+[3] : $+[2] );

    # Now replace U+FFFC back with real | characters.
    my $new_text = $2;
    $new_text =~ s/{{(.*?)}}/'{{' . _unescape_pipes($1) . '}}'/eg;

    $new_text =~ s/^[ \t]*\n?(.*?)[ \t]*$/$1/s;
    $self->text($new_text);

    if ( $new_text =~ /\n/ ) {
        $self->text( $new_text . "\n" )
            unless $new_text =~ /\n\z/;
        $self->contains_blocks( $self->table_blocks );
    }
    elsif ($new_text =~ /^(?:\*+|#+|>+|\^+)\s/ ) {
        $self->text( $new_text . "\n" );
        $self->contains_blocks( $self->table_single_line_blocks );
    }
    else {
        $self->contains_phrases( $self->table_phrases );
    }

    return 1;
}

sub text_filter {
    return $_[1] =~ /\S/
        ? $_[1]
        : '<span style="padding:.5em">&nbsp;</span>';
}


1;

__END__

=head1 NAME

Socialtext::Formatter::Unit - A representation of a parsed chunk of wikitext

=head1 SYNOPSIS

    # parse some text and turn it into a tree of Units
    my $parser = Socialtext::Formatter::Parser->new(
        table = $hub->formatter->table,
        wafl_table = $hub->formatter->wafl_table,
    );
    my $units = $parser->text_to_parsed('Some text to parse');
    my $html = $hub->viewer->to_html($units, $hub);

=head1 DESCRIPTION

An Socialtext::Formatter::Unit performs three separate functions (suggesting
some room for change): a Unit contains the regular expressions and
other rules that allow the L<Socialtext::Formatter::Parser> to test a piece
of wikitext to see if it is of a certain type; if it is, a Unit is
created as a data object in a tree of Units; these units can then
be transformed into HTML with the help of L<Socialtext::Formatter::Viewer>
by calling to_html() with some node in the tree as an argument.

Generally a Unit is created by L<Socialtext::Formatter::Parser>, not by
application code.

Subclassing Unit is how one creates new wikitext syntax. See
SUBCLASSING below.

In this discourse WAFL is left, temporarily, as an exercise for
the reader.

When a Unit is created by the parser, text is sometimes within
the Unit that is further parsed. The type of a current Unit 
influences what the Parser expects or is allowed to find inside
the current Unit.

=head1 METHODS

=over 4

=item html

Generate the HTML that this unit should produce, plus the HTML
of any units it contains.

=item get_text

Retrieve the text contained by this unit and any units it contains,
turning this tree of units back into its original wikitext.
(This implementation is poorly tested.)

=back

=head1 STRUCTURE

All the fields in a Unit are methods, so each could be overridden
for dynamic effects. This doesn't mean you should.

Most Units are subclasses of Socialtext::Formatter::Block, or
Socialtext::Formatter::Phrase. Blocks are like paragraphs, phrases are
inside Blocks.

=head2 Parsing

=over 4

=item formatter_id

The identifier used for a particular Unit. When the Parser is parsing,
it traverses a list of candidate Unit formatter_ids for a match.

=item contains_blocks

If defined, a list of Socialtext::Formatter::Block units that can be found
insider the current Unit.

Constrains what the Parser will try to parse inside this Unit's text.

=item contains_phrases

If defined, a list of Socialtext::Formatter::Phrase units that can be found
insider the current Unit.

Constrains what the Parser will try to parse inside this Unit's text.

=item pattern_block

Used by Block Units to match the entire block in wikitext.

=item pattern_start

The regular expression that identifies the beginning of this Unit in
wikitext.

=item pattern_end

The regular expression that identifies the end of this Unit in
wikitext.

=back

=head2 Storing Data

=over 4

=item text

The text contained by this unit. For example, a paragraph Unit
will contain the text of the paragraph. This text may be further
subjected to parsing.

=item matched

The string representing what was matched to confirm this Unit is
the Unit it is. Not the same as text.

=item units

The Units contained by this Unit: those Units created by parsing
text. These may be references to other Units, or strings. You 
have to use ref to tell them apart :(.

=item next_unit

The Unit following this one in the parse tree. Useful for making
decisions based on what's next.

=item prev_unit

The Unit before this one in the parse tree. Useful for making
decisions based on what came before.

=back

=head2 Creating HTML

A Unit is turned into HTML when to_html is called in the
L<Socialtext::Formatter::Viewer>. The following methods impact what
that HTML will be.

=over 4

=item html_start

What comes first.

=item html

What happens in the middle. 

=item html_end

What comes last.

=back

=head1 SUBCLASSING

A new Unit is created by overriding the parsing and html creation
fields or methods. When considering a new Unit, first decide if it
will be a Block or a Phrase, then define the regular expressions 
that will allow the unit to be matched. For blocks use pattern_block,
for Phrases, use pattern_start and pattern_end.

Then adjust html as appropriate to get the desired output. See the
code for many many examples.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., All Rights Reserved.

=cut
