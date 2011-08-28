package Socialtext::l10n::DevUtils;
use 5.12.0;
use parent 'Exporter';
our @EXPORT = qw( trim gettext_to_maketext str_to_regex is_key outs $po_revision_date );

use DateTime;
my $now = DateTime->now;
our $po_revision_date = $now->ymd . ' ' . $now->hms . '+0000';

sub trim {
    my $str = shift;
    $str =~ s/^msg(?:str|id) "(.*)"/$1/;
    $str =~ s/^"(.*)"$/$1/gem;
    $str =~ s/\n//g;
    return $str;
}

sub gettext_to_maketext {
    my $str = shift;
    chomp $str;
    $str =~ s/\\(.)/$1/g;
    $str =~ s{
        ([%\\]%)                        # 1 - escaped sequence
    |
        %   (?:
                ([A-Za-z#*]\w*)         # 2 - function call
                    \(([^\)]*)\)        # 3 - arguments
            |
                ([1-9]\d*|\*)           # 4 - variable
            )
    }{
        $1 ? $1
           : $2 ? "\[$2,"._unescape($3)."]"
                : "[_$4]"
    }egx;
    return $str;
}

sub str_to_regex {
    my $str = shift;
    $str =~ s/\\n/\x{FFFC}/g;
    $str = gettext_to_maketext($str);

    my $qm1 = quotemeta($str);
    $qm1 =~ s/\x{FFFC}/(?:\n|\\\\n)/g;
    $qm1 =~ s/\\'/(?:'|\\\\')/g;
    $qm1 =~ s/\\"/(?:"|\\\\")/g;

    my $qm2 = quotemeta($str);
    $qm2 =~ s/(\\.|.)\K/(?:['"]\\s*\\.\\s*['"])?/g;
    $qm2 =~ s/\x{FFFC}/(?:\n|\\\\n)/g;
    $qm2 =~ s/\\'/(?:'|\\\\')/g;
    $qm2 =~ s/\\"/(?:"|\\\\")/g;

    return(qr/(?:loc|__)\(\s*["']\K$qm1(?=["']\s*[,\)])/, qr/(?:loc|__)\(\s*["']\K$qm2(?=["']\s*[,\)])/);
}

sub is_key {
    my $str = shift;
    return 0 if $str =~ /\bexample\.com"/;
    return($str =~ /^msg(?:id|str) "(?:###-)?(?:XXX|[a-z][a-z\d]+)\.[^~\[\]\sA-Z]+"/);
}

sub _unescape {
    join(',', map {
        /\A(\s*)%([1-9]\d*|\*)(\s*)\z/ ? "$1_$2$3" : $_
    } split(/,/, $_[0]));
}


sub outs {
    my $para = shift;
    $para =~ s/\n*$/\n/;
    print $para;
}

1;
__END__

=head1 NAME

Socialtext::l10n::DevUtils - Utility functions for l10n scripts under dev-bin/

=head1 SYNOPSIS

    use Socialtext::l10n::DevUtils;

    my $str = trim($msgstr);
    my $bool = is_key($msgid);
    my $re = str_to_regex("Some %1 string");
    outs("Some text");

=head1 DESCRIPTION

This module defines a few common functions used by dev-bin/l10n-* scripts.

=cut
