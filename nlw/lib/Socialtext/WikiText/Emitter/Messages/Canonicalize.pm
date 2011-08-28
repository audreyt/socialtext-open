package Socialtext::WikiText::Emitter::Messages::Canonicalize;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::WikiText::Emitter::Messages::Base';
use Socialtext::l10n qw/loc/;
use Readonly;

Readonly my %markup => (
    asis => [ '{{', '}}' ],
    b    => [ '*',  '*' ],
    i    => [ '_',  '_' ],
    del  => [ '-',  '-' ],
    hyperlink => [ '"',  '"<HREF>' ],
    hashmark => [ '{hashtag: ', '}' ],
    video => [ '{video: ', '}' ],
);

sub msg_markup_table { return \%markup }

sub msg_format_link {
    my $self = shift;
    my $ast = shift;

    # Handle the "Named"{link: ws [page]} case.
    if (length $ast->{text} and $ast->{wafl_string} =~ /\[(.*)\]/) {
        my $page_id = $1;
        if ($ast->{text} ne $page_id) {
            return qq("$ast->{text}"{$ast->{wafl_type}: $ast->{wafl_string}});
        }
    }

    return "{$ast->{wafl_type}: $ast->{wafl_string}}";
}

sub msg_format_hashtag {
    my $self = shift;
    my $ast = shift;
    return "{hashtag: $ast->{text}}";
}

sub msg_format_video {
    my $self = shift;
    my $ast = shift;
    if ($ast->{text} ne $ast->{href}) {
        return qq("$ast->{text}"{video: $ast->{href}});
    }
    return "{video: $ast->{href}}";
}

sub msg_format_user {
    my $self = shift;
    my $ast = shift;
    if ($self->{callbacks}{decanonicalize}) {
        return $self->user_as_username( $ast );
    }
    else {
        return $self->user_as_id( $ast );
    }
}

sub user_as_id {
    my $self = shift;
    my $ast  = shift;

    my $user = eval{ Socialtext::User->Resolve( $ast->{user_string} ) };
    return loc('user.unknown') unless $user;

    my $user_id = $user->user_id;
    return "{user: $user_id}";
}

sub user_as_username {
    my $self = shift;
    my $ast  = shift;
    my $account_id = $self->{callbacks}{account_id};

    my $user = $self->_ast_to_user($ast);
    return "{user: $ast->{user_string}}" unless $user;

    if ($user->primary_account_id == $account_id) {
        my $username = $user->username;
        return "{user: $username}";
    }
    else {
        return $user->best_full_name;
    }
}

sub _ast_to_user {
    my $self = shift;
    my $ast = shift;
    return eval{ Socialtext::User->Resolve( $ast->{user_string} ) };
}

1;
