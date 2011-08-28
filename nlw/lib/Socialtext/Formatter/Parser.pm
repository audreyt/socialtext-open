# @COPYRIGHT@
package Socialtext::Formatter::Parser;
use strict;
use warnings;

use Class::Field qw( const field );
use File::Path ();
use Socialtext::AppConfig;
use Socialtext::Formatter::Unit;
use Socialtext::Formatter::Block;
use Socialtext::Formatter::Phrase;
use Socialtext::Log qw( st_log );
use Socialtext::Statistics 'stat_call';
use Socialtext::Timer qw/time_scope/;
use Encode ();
use Digest::MD5 ();
use Storable;

const top_class    => 'Socialtext::Formatter::Top';

field 'table';
field 'wafl_table';

sub new {
    my $class = shift;
    $class = ref($class) || $class;

    my $self = bless {}, $class;
    while ( my ( $field, $value ) = splice @_, 0, 2 ) {
        $self->$field($value)
            if $self->can($field);
    }

    return $self;
}

sub text_to_parsed {
    # using numbered parameters means less copying
    # my ($self, $content_or_ref) = @_;
    my $self = $_[0];
    my $t = time_scope 'text_to_parsed';
    my $parsed = $self->_parse(
        # body may be a ref; de-ref it before it's copied and munged
        $self->top_class->new(text => (ref($_[1]) ? ${$_[1]} : $_[1]))
    );
    return $parsed;
}

# empty for hooking
sub unit_match { }

sub _parse {
    my $self = shift;
    my $unit = shift;
    $self->_parse_blocks($unit);
    my $units = $unit->units;

    if (    @$units == 1
        and not ref $units->[0]
        and @{ $unit->contains_phrases } ) {

        $unit->text( shift @$units );
        $unit->start_offset(0);
        $unit->end_offset(0);

        $self->_parse_phrases($unit);
    }
    return $unit;
}

sub _parse_blocks {
    my $self = shift;
    my $unit = shift;
    my $text = $unit->text;
    $unit->text(undef);
    my $units    = $unit->units;
    my $table    = $self->table;

    my $contains = $unit->contains_blocks;
    while ( defined $text and length $text ) {
        my $match = $self->_match_format_id( $contains, $table, $text );
        if ( not defined $match ) {
            push @$units, $text;
            last;
        }
        push @$units, substr( $text, 0, $match->start_offset )
            if $match->start_offset;
        $text = substr( $text, $match->end_offset );
        $self->unit_match($match);
        $self->_bless_wafl_class($match) if $match->{method};
        push @$units, $match;
    }
    $self->_link_units($units);
    $self->_parse($_) for grep ref($_), @{ $unit->units };
}

sub _bless_wafl_class {
    my $self = shift;
    my $unit = shift;
    my $class   = $self->wafl_table->{ $unit->method }
        or return;
    bless $unit, ref $class ? ref $class : $class;
    return 1;
}

sub _link_units {
    my $self = shift;
    my $units = shift;
    for ( my $i = 0; $i < @$units; $i++ ) {
        next unless ref $units->[$i];
        $units->[$i]->next_unit( $units->[ $i + 1 ] );
        $units->[$i]->prev_unit( $units->[ $i - 1 ] ) if $i;
    }
}

sub _parse_phrases {
    my $self = shift;
    my $unit = shift;
    my $text = $unit->text;
    $unit->text(undef);
    my $units    = $unit->units;
    my $table    = $self->table;
    my $contains = $unit->contains_phrases;
    while ( defined $text and length $text ) {
        my $match = $self->_match_format_id( $contains, $table, $text );
        if ( $unit->start_end_offset ) {
            if ( $text =~ $unit->pattern_end ) {
                if ( not defined $match or $-[0] < $match->start_offset ) {
                    push @$units, substr( $text, 0, $-[0] );
                    return substr( $text, $+[0] );
                }
            }
            else {
                $unit->end_offset( length $text );
                push @$units, $text;
                return '';
            }
        }
        if ( not defined $match ) {
            push @$units, $text;
            return '';
        }
        push @$units, substr( $text, 0, $match->start_offset )
            if $match->start_offset;
        $text = substr( $text, $match->start_end_offset );
        $match->text($text);
        $text = $self->_parse_phrases($match);
        $self->unit_match($match);
        $self->_bless_wafl_class($match) if $match->{method};
        push @$units, $match;
    }

    # XXX sometimes we fall through, we need
    # to explicitly return void so setting
    # text gets what we expect, otherwise
    # text gets set to 0
    return;
}

sub _match_format_id {
    my $self = shift;
    my ( $contains, $table, $text ) = @_;
    my $match;
    for my $format_id (@$contains) {
        my $class = $table->{$format_id} or next;
        my $unit = $class->new();
        $unit->match($text) or next;
        $self->_unit_is_bad_wafl($unit) and next;
        $match = $unit
            if not defined $match
            or $unit->start_offset < $match->start_offset;
        last unless $match->start_offset;
    }
    return $match;
}

sub _unit_is_bad_wafl {
    my $self = shift;
    my $unit = shift;
    return ($unit->can('method') and !$self->wafl_table->{ $unit->method });
}

sub cache_dir {
    my $self = shift;
    my $ws_id = shift;
    use Carp qw/confess/;
    confess 'no ws_id' unless defined $ws_id;

    # XXX Do we need to check available disk space?
    # XXX Do we use Cache::Cache?

    my $cache_dir = Socialtext::AppConfig->formatter_cache_dir . "/$ws_id";
    File::Path::mkpath($cache_dir) unless -d $cache_dir;
    return $cache_dir;
}

sub get_cached_tree {
    my ($self, $text_ref, $page) = @_;

    my $page_id = $page->id;
    my $cache_dir = $self->cache_dir($page->workspace_id);
    # TODO: chunk up text and feed into a md5 object to avoid creating huge
    # copy of the text. Encoding is necessary for md5_hex() to not croak.
    my $text_md5 = $$text_ref
        ? Digest::MD5::md5_hex(Encode::encode_utf8($$text_ref)) : '';
    my $cache_file = "$cache_dir/$text_md5" . '_' . $page_id;
    my $parsed;

    # Added test for size of $cache_file in order to stop
    # application errors based on 0 size cached files
    if (    -f $cache_file
        and -s _
        and ( ( stat _ )[9] > $page->modified_time ) )
    {
        stat_call( formatter_cache_hit_rate => 'observe', 0 );
        # return here so it's an lvalue
        $parsed = Storable::retrieve($cache_file);
    }
    else {
        stat_call( formatter_cache_hit_rate => 'observe', 1 );
        $parsed = $self->text_to_parsed($text_ref);
        {
            # This hides known warnings when we try to serialize CODE and GLOB
            # objects.
            local $SIG{__WARN__} = sub { };
            eval { Storable::nstore( $parsed, $cache_file ) };
            st_log( error => $@ ) if $@;
        }
    }
    return $parsed;
}


1;

__END__

=head1 NAME

Socialtext::Formatter::Parser - The NLW Wikitext Parser

=head1 SYNOPSIS

    # parse some text and turn it into a tree of Units
    my $parser = Socialtext::Formatter::Parser->new(
        table = $hub->formatter->table,
        wafl_table = $hub->formatter->wafl_table,
    );
    my $units = $parser->text_to_parsed('Some text to parse');
    my $html = $units->to_html;

=head1 DESCRIPTION

The NLW Wikitext parser creates a tree of L<Socialtext::Formatter::Unit> objects
from provided wikitext. The units can then be transformed into some
other format, usually HTML.

A Unit provides the regular expressions for identifying a unit and the
rules for turning that unit into HTML when the parse tree is traversed.

=head1 METHODS

=over 4

=item new

Creates a new parser. No arguments are required, but without any,
parsing is essentially a noop. The optional arguments are:

=over 4

=item table

A hash of formatter identifiers and the L<Socialtext::Formatter::Unit> classes
that provide the regular expressions required for parsing.

=item wafl_table

A hash similar to table that identifies those L<Socialtext::Formatter::Wafl>
classes that are available to the system.

=back

Example:

Create a parser aware of all the Units listed in L<Socialtext::Formatter>.

    my $formatter = $self->hub->formatter;
    my $parser = Socialtext::Formatter::Parser->new(
        table = $formatter->table,
        wafl_table = $formatter->wafl_table,
    );

=item text_to_parsed

Given witkitext, return the a reference to the unit at the top of
the parse tree. The parsing process will link the units together
so they may be self-traversed (traversal described in
L<Socialtext::Formatter::Unit>).

=item unit_match

A noop method available for overrides and hooking. When the parser
has made a sure match to a particular L<Socialtext::Formatter::Unit> class,
unit_match is called. This can be used to do things like calculate
the number of links on a page, build table of contents, and other
side-effecty sorts of things.

=item get_cached_tree

A caching version of text_to_parsed, for L<Socialtext::Pages>. If the
cache is not stale, returned the pre-parsed page, otherwise
parse the page, write the cache, and return the tree.

=back

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., All Rights Reserved.

=cut
