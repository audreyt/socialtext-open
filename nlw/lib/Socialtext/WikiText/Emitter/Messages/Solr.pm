package Socialtext::WikiText::Emitter::Messages::Solr;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::WikiText::Emitter::Messages::Canonicalize';
use Socialtext::l10n qw/loc/;
use Readonly;

Readonly my %markup => (
    asis => [ '', '' ],
    b    => [ '',  '' ],
    i    => [ '',  '' ],
    del  => [ '',  '' ],
    hyperlink => [ '"',  '"<HREF>' ],
    hashmark  => ['',''],
    video     => ['',''],
);

sub msg_markup_table { return \%markup }

sub msg_format_link {
    my $self = shift;
    my $ast = shift;

    # Handle the "Named"{link: ws [page]} case.
    if (length $ast->{text} and $ast->{wafl_string} =~ /\[(.*)\]/) {
        my $page_id = $1;
        if ($ast->{text} ne $page_id) {
            return qq("$ast->{text}" $ast->{wafl_string});
        }
    }

    return $ast->{wafl_string};
}


sub msg_format_user {
    my $self = shift;
    my $ast = shift;
    return $self->user_as_username( $ast );
}

sub msg_format_hashtag {
    my $self = shift;
    my $ast = shift;
    return "#$ast->{text}";
}

sub msg_format_video {
    my $self = shift;
    my $ast = shift;
    if ($ast->{text} ne $ast->{href}) {
        return qq("$ast->{text}" $ast->{href});
    }
    return $ast->{href};
}

sub user_as_username {
    my $self = shift;
    my $ast  = shift;

    my $user = $self->_ast_to_user($ast);
    return '' unless $user;
    return $user->best_full_name;
}

sub markup_node {
    my $self = shift;
    my $is_end = shift;
    my $ast = shift;

    if ($ast->{type} eq 'hyperlink' and $is_end) {
        my $output = $self->msg_markup_table->{$ast->{type}}->[$is_end];
        if (($ast->{text}||'') eq $ast->{attributes}{target}) {
            $output =~ s/<HREF>//;
        }
        else {
            $output =~ s/HREF/$ast->{attributes}{target}/;
        }
        $self->{output} .= $output;
        return;
    }
    $self->SUPER::markup_node($is_end, $ast);
}

1;

=head1 NAME

Socialtext::WikiText::Emitter::Messages::Solr

=head1 SYNOPSIS

    use Socialtext::WikiText::Emitter::Messages::Solr

    my $parser = Socialtext::WikiText::Parser::Messages->new(
        receiver => Socialtext::WikiText::Emitter::Messages::Solr->new(),
    );
    my $body = $parser->parse($signal->body);

=head1 DESCRIPTION

Emit messages that can be passed to Solr for indexing.

=cut
