# @COPYRIGHT@
package Socialtext::Revision::WikitextSideBySideDiff;

use strict;
use warnings;

use Algorithm::Diff::XS;

use base 'Socialtext::Revision::SideBySideDiff';

sub diff_rows {
    my $self = shift;
    return $self->compare(
        $self->before_page->to_wikitext,
        $self->after_page->to_wikitext
    );
}

sub compare {
    my $self = shift;
    my $before = shift;
    my $after = shift;

    my @chunks = $self->split_into_diffable_divs($before, $after);

    my @sections;
    for my $chunk (@chunks) {
        push @sections, {
            before => $self->compare_chunk($chunk->[0], $chunk->[1], 'before'),
            after => $self->compare_chunk($chunk->[0], $chunk->[1], 'after'),
        };
    };
    return \@sections;
}

sub split_into_diffable_divs {
    my $self = shift;
    my @sdiffs = Algorithm::Diff::XS::sdiff(
        [ $self->split_into_escaped_lines(shift) ],
        [ $self->split_into_escaped_lines(shift) ],
    );
    my @divs;
    my @accumulation = ('','');
    for (0..$#sdiffs) {
        my $row = $sdiffs[$_];
        my $flag = $row->[0];
        my ($left, $right) = @{$row}[1,2];
        $accumulation[0] .= $left;
        $accumulation[1] .= $right;
        if ('u' eq $flag or $_ == $#sdiffs) {
            push @divs, [ @accumulation ];
            @accumulation = ('','');
        }
    }
    return @divs
}

sub split_into_escaped_lines {
    my $self = shift;
    return split /$/m, Socialtext::String::html_escape($_[0]);
}

sub compare_chunk {
    my $self = shift;
    my $before = shift;
    my $after = shift;
    my $desired_output = shift;

    my @before = $self->split_into_words($before);
    my @after = $self->split_into_words($after);

    # Turn off SvUTF8 flag as Algorithm::Diff::XS doesn't do Unicode.
    Encode::_utf8_off($_) for @before;
    Encode::_utf8_off($_) for @after;

    my @cdiffs = Algorithm::Diff::XS::compact_diff(\@before, \@after);
    my $html   = '';

    # some roughness to deal with the terse structure returned by compact_diff:
    for ( my $ii = 0; $ii + 3 <= $#cdiffs; $ii += 2 ) {
        if ($ii % 4) {
            if ('before' eq $desired_output) {
                my @slice = $cdiffs[$ii] .. $cdiffs[ $ii + 2 ] - 1;
                $html .= enspan_old( @before[ @slice ] );
            }
            elsif ('after' eq $desired_output) {
                my @slice = $cdiffs[ $ii + 1 ] .. $cdiffs[ $ii + 3 ] - 1;
                $html .= enspan_new( @after[ @slice ] );
            }
            else {
                warn "Uhh.... something's super wrong.";
            }
        }
        else {
            $html .= join '', @before[ $cdiffs[$ii] .. $cdiffs[ $ii + 2 ] - 1 ];
        }
    }

    # Now put the SvUTF8 flag back on.
    $html = Socialtext::Encode::ensure_is_utf8($html);

    # XXX need to refactor this (and add a unit test - not necessarily in that
    # order)
    if ($html =~ /^\s+$/m) {
        $html =~ s/\n/<br\/>\n/gsm;
    } else {
        $html =~ s/(.)\n/$1<br\/>\n/gsm;
    }
    return Socialtext::String::double_space_harden($html);
}

sub split_into_words { split /\b/, $_[1] }

sub enspan_old {
    return @_
      ? join '', "<span class='st-revision-compare-old'>", @_, "</span>"
      : '';
}

sub enspan_new {
    return @_
      ? join '', "<span class='st-revision-compare-new'>", @_, "</span>"
      : '';
}

1;

=head1 NAME

Socialtext::Revision::WikitextSideBySideDiff - Wikitext Revision Compare

=head1 SYNOPSIS

  package Socialtext::Revision::WikitextSideBySideDiff;
  my $differ = Socialtext::Revision::WikitextSideBySideDiff->new(
    before_page => $before_page,
    after_page => $new_page,
    hub => $hub,
  );
  my $rows = $differ->diff_rows;

=head1 DESCRIPTION

Compare the wikitext from two revisions.

=cut
