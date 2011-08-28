#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext tests => 16;

use Fcntl ':seek';
use File::Temp;
use IO::Scalar;
use Readonly;
use RTF::Parser;

fixtures('admin');

Readonly my $PAGE_NAME => 'Admin Wiki';
Readonly my $HUB       => new_hub('admin');

Readonly my $HYPERLINK_TEXT => 'hello http://www.burningchrome.com';

Readonly my $TABLE_TEXT => <<"EOF";
| 1a | 1b |
| 2a | *2b* |

hello
EOF

BEGIN { use_ok('Socialtext::RtfExportPlugin') }

with_control( '*foo*', b => 'foo', 'Bold bolds.' );
with_control( '_bar_', i => 'bar', 'Italics italicizes.' );
without_control( '*foo*', i => 'foo', "Bold doesn't italicize." );
without_control( '_bar_', b => 'bar', "Italics doesn't bold." );

without_control( '*foo* bar', b => 'bar', 'Bold turns off.' );
without_control( '_foo_ bar', i => 'bar', 'Italics turns off.' );

with_control( '_*foo*_', b => 'foo', 'Mixed bold/italics produces bold.' );
with_control( '_*foo*_', i => 'foo', 'Mixed bold/italics produces italcs.' );

control_count(
    $TABLE_TEXT, cell => 4,
    'Table has the right number of cells.'
);

control_count( 'foo', cell => 0, 'Non-table has no cells.' );


# HYPERLINK handling
control_count( $HYPERLINK_TEXT, field => 1, 'hyperlink has a field' );
control_count( $HYPERLINK_TEXT, fldinst => 1,
    'hyperlink has a field instance' );
control_count( $HYPERLINK_TEXT, fldrslt => 1, 'hyperlink has a field rslt' );
like rtf_for_wikitext($HYPERLINK_TEXT), qr{\\ul}, 'hyperlink has a ul control';
like rtf_for_wikitext($HYPERLINK_TEXT), qr{\\cf2},
    'hyperlink has a color foreground 2 control';

# I wanted to try to look for a pattern something like the reg expr below, but
# found, after much head banging, the RTF parsers and lexers to all be buggy,
# not recognizing control words as such, and so on.  I'm surprised they work
# for the other tests.
#
# Anyway, this note is here for future would-be hackers.  The below was my
# plan.
#
# ----
#
# We want to match something like the following regular expression
# { \trowd WORD* "1a" \cell WORD* "1b" WORD* }
# { \trowd WORD* "2a" \cell WORD* { \b "2b" } WORD* }
# Where {, } are RTF enter and leave, WORD means any control word, \foo is the
# control word "\foo", and anything in double quotes means plain text matching
# that.
#
# This could be done with a regex against the raw RTF, but it will be error
# prone.  Instead, we will transform the tokens of the given RTF into
# the following limited alphabet:
# ENTER                 {
# LEAVE                 }
# \trowd                T
# \cell                 C
# \b                    B
# other control words   W
# plain text            "the actual text"
#
# Given that alphabet, our regular expression becomes
# my $expected = qr/
#     { T W* "\s*1a\s*" C W* "\s*1b\s*" W* }
#     { T W* "\s*2a\s*" C W* { B "\s*2b\s*" } W* }
# /x;

# control_count(WIKITEXT, CONTROL, COUNT)
#
# Verify that WIKITEXT produces some RTF in which CONTROL occurs exactly COUNT
# times.
sub control_count {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my ( $wikitext, $control, $expected_count, $message ) = @_;
    my $count = 0;

    my $parser = TestParser->new;
    $parser->control_definition(
        {
            __DEFAULT__ => sub { },
            $control    => sub { ++$count }
        }
    );
    $parser->parse_string( rtf_for_wikitext($wikitext) );
    clean_symbol_table();

    is( $count, $expected_count, $message);
}

# without_control(WIKITEXT, CONTROL, TEXT)
#
# Tests that in the RTF corresponding to WIKITEXT, TEXT is encountered when
# CONTROL is inactive.
sub without_control {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    test_control_value( 0, @_ );
}

# with_control(WIKITEXT, CONTROL, TEXT)
#
# Tests that in the RTF corresponding to WIKITEXT, TEXT is encountered when
# CONTROL is active.
sub with_control {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    test_control_value( 1, @_ );
}

# test_control_value(WIKITEXT, CONTROL, TEXT, EXPECTED_VALUE)
sub test_control_value {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my ( $expected_value, $wikitext, $control, $text, $message ) = @_;
    $message ||= "'$wikitext' yields '$text' when '$control' is active.\n";

    my $rtf = rtf_for_wikitext($wikitext);

    my $parser = make_test_parser( $control, $text );
    $parser->parse_string($rtf);
    clean_symbol_table();
    is( $parser->flag, $expected_value, $message );
}

# This works around a bug in RTF::Parser.  RTF::Parser (at least up to 1.09)
# installs control handlers in the RTF::Action symbol table via AUTOLOAD.  If
# you try to use a parser after having already parsed something with a
# different parser, you get the first parser's methods.  See also
# RTF::Parser::_control_execute. -mml
#
# This loop removes those methods from the symbol table.
sub clean_symbol_table {
    for (keys %RTF::Action::) {
        no strict 'refs';
        undef *{"RTF::Action::$_"} unless $_ eq 'AUTOLOAD';
    }
}

# Returns an RTF string corresponding to the given wikitext.
sub rtf_for_wikitext {
    my ($wikitext) = @_;
    my $page = $HUB->pages->new_from_name($PAGE_NAME);
    $page->edit_rev;
    $page->content($wikitext);
    $page->store( user => $HUB->current_user );

    my $content;
    $HUB->rtf_export->export($PAGE_NAME, \$content);
    return $content;
}

# Returns a parser which will set a flag if it encounters the given text while
# the given control is set.
sub make_test_parser {
    my ( $control, $expected_text ) = @_;
    my $parser = TestParser->new;
    $parser->set_state(0);
    $parser->flag(0);
    $parser->control_definition(
        {
            __DEFAULT__ => sub { },
            $control    => sub { $_[0]->set_state(1) }
        }
    );
    $parser->text_callback(
        sub {
            my ( $self, $text ) = @_;
            $self->flag(1)
                if ( $text =~ /\Q$expected_text\E/ && $_[0]->state );
        }
    );
    return $parser;
}

sub get_rtf {
    my $content;
    $HUB->rtf_export->export($PAGE_NAME, \$content);
    return $content;
}

package TestParser;

use base 'RTF::Parser';

use Class::Field 'field';

BEGIN {
    field 'states', -init => '[]';
    field 'text_callback';
    field 'flag';
}

sub push_state {
    my ($self) = @_;
    my $states = $self->states;

    push @$states, $states->[$#$states];
}

sub pop_state {
    my ($self) = @_;
    
    return pop @{ $self->states };
}

sub state {
    my ($self) = @_;
    my $states = $self->states;

    return $states->[$#$states];
}

sub set_state {
    my ( $self, $new_state ) = @_;
    my $states = $self->states;

    if (@$states) {
        $states->[$#$states] = $new_state;
    }
    else {
        $self->states( [$new_state] );
    }
}

sub group_start { $_[0]->push_state }
sub group_end   { $_[0]->pop_state }

sub text {
    my $f = $_[0]->text_callback;

    goto &$f if $f;
}
