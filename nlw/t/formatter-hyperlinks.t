#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext;

fixtures(qw( empty ));

filters { regexps => [qw'lines chomp make_regexps'] };
plan tests => 1 * (map { ($_->regexps) } blocks);

###############################################################################
# Get the Workspace that we're testing with/against.
my $ws = Test::Socialtext::main_hub->current_workspace();

###############################################################################
# Track this setting, so we can set it back when we're done testing.
our $external_links_open_new_window = $ws->external_links_open_new_window();
END {
    if (defined $external_links_open_new_window) {
        $ws->update( external_links_open_new_window => $external_links_open_new_window );
    }
}

###############################################################################
# Test once, with external links opening in a new window
external_links_open_in_new_window: {
    $ws->update( external_links_open_new_window => 1 );
    run {
        my $test = shift;
        return if $test->target;
        perform_test($test);
    };
}

###############################################################################
# Test again, with external links *NOT* opening in a new window
external_links_open_in_same_window: {
    $ws->update( external_links_open_new_window => 0 );
    run {
        my $test = shift;
        return unless $test->target;
        perform_test($test);
    };
}

sub perform_test {
    my $test = shift;
    my $text = $test->text;
    for my $re ($test->regexps) {
        formatted_like $text, $re, "$text =~ $re";
    }
}

sub make_regexps { map { eval } @_ }

__DATA__

===
--- text: http://foo.example.com/
--- regexps
qr{\Qtitle="(external link)"\E}
qr{\Qtarget="_blank"\E}
qr{\Qhref="http://foo.example.com/"\E}

===
--- text: https://bar.example.com/
--- regexps
qr{\Qtitle="(external link)"\E}
qr{\Qtarget="_blank"\E}
qr{\Qhref="https://bar.example.com/"\E}

===
--- text: ftp://ftp.example.com/
--- regexps
qr{\Qtitle="(external link)"\E}
qr{\Qtarget="_blank"\E}
qr{\Qhref="ftp://ftp.example.com/"\E}

===
--- text: irc://irc.example.com
--- regexps
qr{\Qtitle="(start irc session)"\E}
qr{\Qhref="irc://irc.example.com"\E}

===
--- text: file://server/filename.txt
--- regexps
qr{\Qtitle="(external link)"\E}
qr{\Qhref="file://server/filename.txt"\E}

===
--- text: http://foo.example.com/path/page.html
--- regexps
qr{\Qtitle="(external link)"\E}
qr{\Qtarget="_blank"\E}
qr{\Qhref="http://foo.example.com/path/page.html"\E}

===
--- text: http://foo.example.com/path/image.png
--- regexps
qr{\Qsrc="http://foo.example.com/path/image.png"\E}

===
--- text: http:path/image.png
--- regexps
qr{\Qsrc="path/image.png"\E},

===
--- text: *"hello"<http://example.com/thing.html>*
--- regexps
qr{\Qhref="http://example.com/thing.html"\E}
qr{\Q<strong><a target\E}
qr{\Qhello\E}
qr{\Q</a></strong>\E}

===
--- text: *"hello"<http:index.cgi?ass_page>*
--- regexps
qr{\Qhref="index.cgi?ass_page"\E}
qr{\Q<strong><span class="nlw_phrase"><a\E}
qr{\Q<!-- wiki: "hello"<http:index.cgi?ass_page> --></span></strong>\E}

===
--- text: "hello"<http:index.cgi?ass_page>
--- regexps
qr{\Qhref="index.cgi?ass_page"\E}
qr{\Qhello</a>\E}

===
--- target: 1
--- text: http://foo.example.com/
--- regexps
qr{\Qtitle="(external link)"\E}
qr{<a\s+rel="nofollow"\s+title}
qr{\Qhref="http://foo.example.com/"\E}

===
--- target: 1
--- text: https://bar.example.com/
--- regexps
qr{\Qtitle="(external link)"\E}
qr{<a\s+rel="nofollow"\s+title}
qr{\Qhref="https://bar.example.com/"\E}

===
--- target: 1
--- text: ftp://ftp.example.com/
--- regexps
qr{\Qtitle="(external link)"\E}
qr{<a\s+rel="nofollow"\s+title}
qr{\Qhref="ftp://ftp.example.com/"\E}

