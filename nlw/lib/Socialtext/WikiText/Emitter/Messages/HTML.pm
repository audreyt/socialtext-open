package Socialtext::WikiText::Emitter::Messages::HTML;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::WikiText::Emitter::Messages::Base';
use Socialtext::l10n qw/loc/;
use Socialtext::Formatter::AbsoluteLinkDictionary;
use Socialtext::String;
use Readonly;

Readonly my %markup => (
    asis => [ '',                '' ],
    b    => [ '<b>',             '</b>' ],
    i    => [ '<i>',             '</i>' ],
    del  => [ '<del>',           '</del>' ],
    hyperlink => [ '<a href="HREF">', '</a>' ],
    hashmark  => undef, # handled by overriding markup_node()
    video     => undef, # handled by overriding markup_node()
);

sub link_dictionary {
    my $self = shift;
    $self->{callbacks}{link_dictionary} ||=
        Socialtext::Formatter::AbsoluteLinkDictionary->new;
    return $self->{callbacks}{link_dictionary};
}

sub msg_markup_table { return \%markup }

sub msg_format_link {
    my $self = shift;
    my $ast = shift;
    my @args = (
        url_prefix => $self->{callbacks}{baseurl} || "",
        link => 'interwiki',
        workspace => $ast->{workspace_id},
        page_uri => Socialtext::String::uri_escape($ast->{page_id}),
    );
    if (defined $ast->{section} && length($ast->{section})) {
        my $section = Socialtext::String::title_to_id(
            Socialtext::String::uri_unescape(
                $ast->{section}
            )
        );
        push @args, section => "#$section";
    }
    my $url = $self->link_dictionary->format_link(@args);
    return qq{<a href="$url">$ast->{text}</a>};
}

sub msg_format_hashtag {
    my $self = shift;
    my $ast = shift;
    my $is_end = shift;

    my $hashtag = Socialtext::String::uri_escape(qq["$ast->{text}"]);
    my $url = $self->link_dictionary->format_link(
        url_prefix => $self->{callbacks}{baseurl} || "",
        link => 'signal_hashtag',
        hashtag => $hashtag,
    );

    my $prefix = qq{#<a href="$url">};

    if (defined $is_end) {
        # is_end is only defined when called for rendering a hashmark
        return $is_end ? "</a>" : $prefix;
    }
    return "$prefix$ast->{text}</a>";
}

sub msg_format_video {
    my $self = shift;
    my $ast = shift;
    my $is_end = shift;
    my $url = Socialtext::String::html_escape($ast->{href});
    my $text = Socialtext::String::html_escape($ast->{text});

    my $prefix = qq{<a href="$url">};
    if (defined $is_end) {
        return $is_end ? "</a>" : $prefix;
    }
    return "$prefix$text</a>";
}

sub msg_format_user {
    my $self = shift;
    my $ast = shift;
    my $userid = $ast->{user_string};
    my $viewer = $self->{callbacks}{viewer};

    my $user = eval { Socialtext::User->Resolve($userid) };
    unless ($user) {
        return loc("user.unknown");
    }

    my $url = $self->link_dictionary->format_link(
        url_prefix => $self->{callbacks}{baseurl} || "",
        link => 'people_profile',
        user_id => $user->user_id,
    );
    return qq{<a href="$url">} . $user->guess_real_name . '</a>';
}

sub markup_node {
    my $self = shift;
    my $is_end = shift;
    my $ast = shift;

    if ($ast->{type} && $ast->{type} eq 'hashmark') {
        $self->{output} .= $self->msg_format_hashtag($ast,$is_end);
        return;
    }
    elsif ($ast->{type} && $ast->{type} eq 'video') {
        $self->{output} .= $self->msg_format_video($ast,$is_end);
        return;
    }
    return $self->SUPER::markup_node($is_end,$ast,@_);
}

sub text_node {
    my $self = shift;
    my $text = shift;
    return unless defined $text;
    $text =~ s/\s{2,}/ /g;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $self->{output} .= $text;
}

1;

