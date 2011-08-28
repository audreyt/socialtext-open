package Socialtext::Template::Plugin::encode_mailto;
# @COPYRIGHT@

use strict;
use warnings;

use Template::Plugin::Filter;
use base qw( Template::Plugin::Filter );
use Socialtext::l10n qw(system_locale);
use Encode qw(from_to);

sub init {
    my $self = shift;

    $self->{ _DYNAMIC } = 0;

    # first arg can specify filter name
    $self->install_filter($self->{ _ARGS }->[0] || 'encode_mailto');

    return $self;
}


sub filter {
    my $str = $_[1];
    if (system_locale() eq 'ja') {
        Encode::_utf8_off($str) if Encode::is_utf8($str);
        from_to($str, 'utf8', 'cp932');
        $str = url_encode($str);
    }
    return $str;
}

sub url_encode {
    my $str = shift;
    $str =~ s/([^\w ])/'%'.unpack('H2', $1)/eg;
    $str =~ tr/ /+/;
    return $str;
}


1;
