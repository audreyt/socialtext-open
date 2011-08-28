package Socialtext::WikiText::Emitter::Messages::Base;
# @COPYRIGHT@
use strict;
use warnings;
use base 'WikiText::Receiver';

sub init {
    my $self = shift;
    $self->{output} = '';
}

sub content {
    my $self = shift;
    my $content = $self->{output};
    $content =~ s/\s\s+/ /g;
    $content =~ s/\s+\z//;
    return $content;
}

sub insert {
    my $self = shift;
    my $ast = shift;

    my $type = $ast->{wafl_type};

    unless (defined $type) {
        my $output = $ast->{output};
        $output = '' unless defined $output;
        $self->{output} .= $output;
        return;
    }

    if ($self->{callbacks}{noun_link} &&
        $type =~ m{^(?:link|user|hashtag|hashmark|video)$})
    {
        # make hashmark look like hashtag to the callback.
        $ast->{wafl_type} = 'hashtag' if $type eq 'hashmark';
        $self->{callbacks}{noun_link}->($ast);
        $ast->{wafl_type} = $type if $type eq 'hashmark';
    }

    if ( $type eq 'link' ) {
        $self->{output} .= $self->msg_format_link($ast);
    }
    elsif ( $type eq 'user' ) {
        $self->{output} .= $self->msg_format_user($ast);
    }
    elsif ( $type eq 'hashmark') {
        # handled by markup_node; not actually a wafl
    }
    elsif ( $type eq 'hashtag' ) {
        $self->{output} .= $self->msg_format_hashtag($ast);
    }
    elsif ( $type eq 'video' ) {
        $self->{output} .= $self->msg_format_video($ast);
    }
    else {
        $self->{output} .= "{$type: $ast->{wafl_string}}";
    }

    return;
}

sub msg_markup_table { die 'subclass must override msg_markup_table' }
sub msg_format_user { die 'subclass must override msg_format_user' }
sub msg_format_link { die 'subclass must override msg_format_link' }
sub msg_format_hashtag { die 'subclass must override msg_format_hashtag' }
sub msg_format_video { die 'subclass must override msg_format_video' }

sub begin_node { my $self=shift; $self->markup_node(0,@_) }
sub end_node   { my $self=shift; $self->markup_node(1,@_) }

sub markup_node {
    my $self = shift;
    my $is_end = shift;
    my $ast = shift;

    my $markup = $self->msg_markup_table;
    
    return unless exists $markup->{$ast->{type}};
    my $output = $markup->{$ast->{type}}->[$is_end ? 1 : 0];
    if ($ast->{type} eq 'hyperlink') {
        $output =~ s/HREF/$ast->{attributes}{target}/;
        if (!$is_end and my $cb = $self->{callbacks}{href_link}) {
            $cb->($ast);
        }
    }
    $self->{output} .= $output;
}

sub text_node {
    my $self = shift;
    my $text = shift;
    return unless defined $text;
    $text =~ s/\n/ /g;
    $self->{output} .= $text;
}

1;
