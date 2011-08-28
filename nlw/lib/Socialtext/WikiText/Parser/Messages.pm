package Socialtext::WikiText::Parser::Messages;
# @COPYRIGHT@
use strict;
use warnings;

use base 'WikiText::Socialtext::Parser';

use Socialtext::String ();
use Scalar::Util qw/weaken/;

my $url_scheme = qr{(?:http|https|ftp|irc|file):(?://)?};
my $reserved   = q{;/?:@&=+$,[]#};
my $mark       = q{-_.!~*'()};
my $unreserved = "A-Za-z0-9\Q$mark\E";
my $uric       = quotemeta($reserved) . $unreserved . "%";

my $url_re      = qr/$url_scheme [$uric]+/x;
my $simple_re   = qr/() (?<![<"]) ($url_re) (?![>"])/x;
my $labelled_re = qr/(?:"([^"]*)"\s*)? < ($url_re) >/x;

sub create_grammar {
    my $self = shift;
    my $grammar = $self->SUPER::create_grammar();
    my $blocks = $grammar->{_all_blocks};
    @$blocks = ('line');
    my $phrases = $grammar->{_all_phrases};

    my %huggy = (
        b   => q{\*},
        i   => q{\_},
        del => q{\-},
    );

    while (my ($rule, $char) = each %huggy) {
        $grammar->{$rule} = {
            match => re_huggy($char),
            phrases => $grammar->{_all_phrases},
        };
    }

    # Fix {bz: 4496} using ([^"]+) instead of (.+?) in quoted strings.
    $grammar->{waflphrase}{match} = qr/
        (?:^|(?<=[\s\-]))
        (?:"([^"]+)")?
        \{
        ([\w-]+)
        (?=[\:\ \}])
        (?:\s*:)?
        \s*(.*?)\s*
        \}
        (?=[^A-Za-z0-9]|\z)
    /x;

    # NOTE: if you add phrases here, be sure to update %markup in
    # ST::WT::Emitter::Canonicalize. Order matters
    @$phrases = ('a', 'waflphrase', 'asis', 'b', 'i', 'del', 'hashmark');
    $grammar->{line} = {
        match => qr/^(.*)$/s,
        phrases => $phrases,
        filter => sub {
            chomp;
            s/\n/ /g; # Turn all newlines into spaces
        }
    };

    # avoid circular reference in the filter sub closure.
    weaken(my $weakself = $self);
    $grammar->{hashmark} = {
        # Only match after a space or beginning-of-line
        match => qr/(?<!\S)#(\p{IsWord}+)/,
        filter => sub {
            $_ =~ s/^#//;
            $weakself->{receiver}->insert({
                wafl_type => 'hashmark',
                text => $_[0]{text},
            });
        },
    };

    # see sub match_a below.
    delete $grammar->{a}{match};

    $grammar->{asis}{filter} = sub {
        my $node = shift;
        $_ = $node->{1} . $node->{2};
    };

    return $grammar;
}

sub match_a {
    my $self = shift;

    my ($simple, $labelled);
    if ($self->{input} =~ $simple_re) {
#         warn "FOUND SIMPLE:   '$1'<$2>\n";
        $simple = $-[0];
    }

    if ($self->{input} =~ $labelled_re) {
#         warn "FOUND LABELLED: '$1'<$2>\n";
        $labelled = $-[0];
    }

    # Calling matched_phrase expects $1, $2, $3, $-[0] and $+[0] to be set so
    # make sure that the one we want (simple or labelled) is the last-run
    # regexp.  The one we want is the *closest* match, preferring labelled
    # (if we have "http://foo.com"<http://foo.com> that should be one and not
    # two a-phrases)

    my $i;
    if (defined $simple and defined $labelled) {
        $i = ($labelled < $simple) ? 1 : 0;
    }
    elsif (defined $simple) {
        $i = 0;
    }
    elsif (defined $labelled) {
        $i = 1;
    }
    else {
        return;
    }

#     warn "labelled: $labelled, simple: $simple, choice: ".($i==0 ? 'simple' : 'labelled') ."\n";
    $self->{input} =~ (($i == 0) ? $simple_re : $labelled_re);
#     warn "FINAL: '$1' '$2'\n";
    return $self->matched_phrase;
}

sub re_huggy {
    my $brace1 = shift;
    my $brace2 = shift || $brace1;
    my $ALPHANUM = '\p{Letter}\p{Number}\pM';

    # {bz: 3771}: Make ":-)" and ";-)" smileys non-huggy.
    my $PRE_ALPHANUM = $ALPHANUM;
    $PRE_ALPHANUM .= ';:' if $brace1 eq q{\-};

    qr/
        (?:^|(?<=[^{$PRE_ALPHANUM}$brace1]))$brace1(?=\S)(?!$brace2)
        (.*?)
        (?<![\s$brace2])$brace2(?=[^{$ALPHANUM}$brace2]|\z)
    /x;
}

sub handle_waflphrase {
    my $self = shift;
    my $match = shift; 
    return unless $match->{type} eq 'waflphrase';
    my $length = $match->{end} - $match->{begin};
    if ($match->{2} eq 'link') {
        my $options = $match->{3};
        if ($options =~ /^\s*([\w\-]+)\s*\[(.*)\]\s*(.*?)\s*$/) {
            my ($workspace_id, $page_id, $section) = ($1, $2, $3);
            my $text = $match->{text} || $page_id;
            $page_id =~ tr/\//_/; # don't produce illegal URLs
            $page_id =
                Socialtext::String::title_to_display_id($page_id, 'no-escape');
            $section =
                Socialtext::String::uri_escape($section) if $section;
            $self->{receiver}->insert({
                wafl_type => 'link',
                workspace_id => $workspace_id,
                page_id => $page_id,
                section => $section,
                text => $text,
                wafl_string => $options,
                wafl_length => $length
            });
            return;
        }
    }
    elsif ($match->{2} eq 'user') {
        my $options = $match->{3};
        $self->{receiver}->insert({
            wafl_type   => 'user',
            user_string => $options,
            wafl_length => $length
        });
        return;
    }
    elsif ($match->{2} eq 'hashtag') {
        $self->{receiver}->insert({
            wafl_type   => $match->{2},
            text => $match->{3},
            wafl_length => $length
        });
        return;
    }
    elsif ($match->{2} eq 'video') {
        $self->{receiver}->insert({
            wafl_type   => $match->{2},
            href => $match->{3},
            text => $match->{1} || $match->{3},
            wafl_length => $length
        });
        return;
    }

    $self->unknown_wafl($match);
}

sub unknown_wafl {
    my $self = shift;
    my $match = shift; 
    my $func = $match->{2};
    my $args = $match->{3};
    my $output = "{$func";
    $output .= ": $args" if $args;
    $output .= '}';
    $self->{receiver}->insert({output => $output});
}

1;
