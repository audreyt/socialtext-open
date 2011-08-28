# @COPYRIGHT@
package Socialtext::Formatter::Phrase;
use strict;
use warnings;

my $ALPHANUM = '\p{Letter}\p{Number}\pM';

use base 'Socialtext::Formatter::Unit';
use Socialtext::l10n qw( loc );

sub match {
    my $self = shift;
    my $text = shift;
    return unless $text =~ $self->pattern_start;
    $self->start_offset( $-[0] );
    $self->start_end_offset( $+[0] );
    $self->matched( substr( $text, $-[0], $+[0] - $-[0] ) );
    my $pattern_end = $self->pattern_end
        or return 1;
    my $end = substr( $text, $+[0] );
    $end =~ s/\n.*//s;
    return $end =~ $pattern_end;
}

sub contains_phrases {
    my $self = shift;
    my $id = $self->formatter_id;
    [ grep { $_ ne $id } @{ Socialtext::Formatter->all_phrases } ];
}

################################################################################
package Socialtext::Formatter::Teletype;

use base 'Socialtext::Formatter::Phrase';
use Class::Field qw( const );

const formatter_id  => 'tt';
const pattern_start => qr/(^|(?<=[^$ALPHANUM]))`(?=\S)/;
const pattern_end   => qr/`(?=[^$ALPHANUM]|\z)/;
const html_start    => "<tt>";
const html_end      => "</tt>";

sub contains_phrases { [] }

################################################################################
package Socialtext::Formatter::Strong;

use base 'Socialtext::Formatter::Phrase';
use Class::Field qw( const );

const formatter_id  => 'strong';
const pattern_start => qr/(^|(?<=[^{$ALPHANUM}\*]))\*(?=\S)(?!\*)/;
const pattern_end   => qr/(?<![\s\*])\*(?=[^{$ALPHANUM}\*]|\z)/;
const html_start    => "<strong>";
const html_end      => "</strong>";

################################################################################
package Socialtext::Formatter::Emphasize;

use base 'Socialtext::Formatter::Phrase';
use Class::Field qw( const );

const formatter_id  => 'em';
const pattern_start => qr/(^|(?<=[^{$ALPHANUM}_]))_(?=\S)(?!_)/;
const pattern_end   => qr/(?<![\s_])_(?=[^{$ALPHANUM}_]|\z)/;
const html_start    => "<em>";
const html_end      => "</em>";

################################################################################
package Socialtext::Formatter::Delete;

use base 'Socialtext::Formatter::Phrase';
use Class::Field qw( const );

const formatter_id  => 'del';
const pattern_start => qr/(^|(?<=[^${ALPHANUM}\-;:]))-(?=[^\s\-])/; # {bz: 3771}: Make ":-)" and ";-)" smileys non-huggy.
const pattern_end   => qr/(?<![\s\-])-(?=[^{$ALPHANUM}\-]|\z)/;
const html_start    => '<del>';
const html_end      => '</del>';

################################################################################
package Socialtext::Formatter::Asis;

use base 'Socialtext::Formatter::Phrase';
use Class::Field qw( const field );
use Socialtext::BrowserDetect ();

const formatter_id  => 'asis';
const pattern_start => qr/\{\{/;
# The extra space here is to work around the fact that IE innerHTML eats
# spaces after a SPAN which means in order to preserve the space after an asis
# we need to store it manually. ugly ugly ugly.
const pattern_end   => qr/\}\}( ?)/;
field 'asis_text';
field 'extra_space';

sub contains_phrases { [] }

sub get_text {
    my $self = shift;
    return $self->asis_text . $self->extra_space;
}

# Use our own match routine to properly consume the text instead of creating
# child units of contained text.
sub match {
    my $self = shift;
    my $text = shift;

    # Match the start, save the opening match tag
    return unless $text =~ $self->pattern_start;
    my $match_start = $+[0];
    $self->start_offset( $-[0] );
    $self->matched( substr( $text, $-[0], $+[0] - $-[0] ) );

    # Match the end, save matched body in the title field
    my $end = substr( $text, $+[0] );
    $end =~ s/\n.*//s;
    return unless $end =~ $self->pattern_end;
    Socialtext::BrowserDetect::ie()
        ? $self->extra_space( $1 ? "&nbsp;" : '' )
        : $self->extra_space( $1 || '' );
    $self->asis_text( substr( $text, $match_start, $-[0]) );
    $self->start_end_offset( $match_start + $-[0] );
    return 1;
}

sub html {
    my $self = shift;
    my $text = $self->asis_text;
    my $space = $self->extra_space;
    # Avoid two { or } chars in a row, it screws up xgettext.pl
    $self->hub->wikiwyg->generate_widget_image("{"."{$text}"."}");
    my $escaped_text = $self->escape_html( $text );
    my $commented_text = $text;
    $commented_text =~ s/-/-=/g;
    return qq(<span class="nlw_phrase">$escaped_text<!-- wiki: {) . qq({$commented_text}) .  qq(} --></span>$space);
}

################################################################################
package Socialtext::Formatter::FreeLink;

use base 'Socialtext::Formatter::Phrase';
use Class::Field qw( const field );

const formatter_id  => 'wiki';
const pattern_start =>
    qr/(?:"([^"]*)"\s*)?(?:^|(?<=[^$ALPHANUM]))\[(?=[^\s\[\]])/;
const pattern_end => qr/\](?=[^$ALPHANUM]|\z)/;
field 'label';
field 'title';

sub contains_phrases { [] }

sub get_text {
    my $self = shift;
    return $self->label || $self->title;
}

# Use our own match routine to properly consume the text instead of creating
# child units of contained text.
sub match {
    my $self = shift;
    my $text = shift;
    my $rt_19458_hack;  

    # Match the start, save the opening match tag
    return unless $text =~ $self->pattern_start;
    my $match_start = $+[0];
    $self->start_offset( $-[0] );
    $self->label($1) if $1;
    $self->matched( substr( $text, $-[0], $+[0] - $-[0] ) );

    # Match the end, save matched body in the title field
    my $end = substr( $text, $match_start );
    $end =~ s/\n.*//s;
    return unless $end =~ $self->pattern_end;
    $text = $rt_19458_hack = $text; # To work around a Perl bug, see {rt 19458}
    my $title = substr( $text, $match_start, $-[0] );
    $self->start_end_offset( $-[0] + $match_start );
    $title =~ s/^index\.cgi\?//; # Migrating pages affected by {bz: 4987}
    $self->title( $title );
    return 1;
}

sub html {
    my $self = shift;
    my $label      = $self->label;
    my $page_title = $self->title;

    my ( $page_disposition, $page_uri )
        = $self->hub->pages->title_to_disposition($page_title);

    if ($page_uri) {
        my $page = defined $label ? $page_title : '';
        $label = $page_title unless defined $label;

        $self->_freelink_url($page_uri, $page_disposition, $label, $page);
    }
    else {
        return $page_title;
    }
}

sub _freelink_url {
    my $self = shift;
    my $page_uri = shift;
    my $page_disposition = shift;
    my $label = shift;
    my $page = shift;

    my $link = $self->hub->viewer->link_dictionary->format_link(
        link => 'free',
        page_uri => $page_uri,
        url_prefix => $self->url_prefix,
        workspace => $self->current_workspace_name, # for page inclusion
    );
    my $escaped_page = $self->html_escape($page);
    my $page_attr = qq{ wiki_page="$escaped_page" };
    my $escaped_label = $self->html_escape($label);
    
    return qq{<a href="$link"$page_attr $page_disposition>$escaped_label</a>};
}

################################################################################
package Socialtext::Formatter::HyperLink;

use base 'Socialtext::Formatter::Phrase';
use Class::Field qw( const );
use Socialtext::l10n qw( loc );

# These are all stolen from URI.pm
my $reserved   = q{;/?:@&=+$,[]#};
my $mark       = q{-_.!~*'()};
my $unreserved = "A-Za-z0-9\Q$mark\E";
my $uric       = quotemeta($reserved) . $unreserved . "%";

const formatter_id  => 'hyper';
const pattern_start => qr{ (?:http|https|ftp|irc|file):
        (?://)?       # this is optional to allow things like http:base/docs/search.png
        [$uric]+
        [A-Za-z0-9/#] # we expect links to end with a slash or some alphanumeric, not punctuation
      }x;

sub html {
    my $self = shift;
    my $match  = $self->matched;
    my $target =
        $self->current_workspace->external_links_open_new_window
        ? qq{target="_blank"}
        : '';

    my $wrap_start  = '';
    my $wrap_finish = '';
    if ( $match =~ m{^\w+:(?!//)} ) {
        my $original = $match;
        $match = $self->_special_http_link($match);

        # XXX need to figure out if we can remove this and let
        # Socialtext::Formatter::WaflPhrase::wikiwyg_to_html take care of it
        $wrap_start  = '<span class="nlw_phrase">';
        $wrap_finish = "<!-- wiki: $original --></span>";
    }

    my $href = $self->html_escape($match);
    my $output =
        $match =~ /\.(gif|jpg|jpeg|jpe|png|pbm|bmp)(?:\?\S+)?$/i
        ? qq{<img alt="$href" src="$href" border="0" />}
        : $match =~ /^irc:/
        ? "<a title=\"(" . loc('link.irc') . ")\" href=\"$href\">$href</a>"
        : "<a $target rel=\"nofollow\" title=\"(" . loc('link.external') . ")\" href=\"$href\">$href</a>";


    return $wrap_start . $output . $wrap_finish;
}

sub _special_http_link {
    my $self = shift;
    my $match = shift;
    $self->hub->wikiwyg->generate_widget_image($match);
    $match =~ s/^\w+://;
    return $self->hub->viewer->link_dictionary->format_link(
        link => 'special_http',
        arg1 => $match,
        url_prefix => $self->url_prefix,
        workspace => $self->current_workspace_name,
    );
}

################################################################################
package Socialtext::Formatter::BracketHyperLink;

use base 'Socialtext::Formatter::HyperLink';
use Class::Field qw( const );
use Socialtext::l10n qw( loc );

const formatter_id  => 'b_hyper';
const pattern_start => qr{("[^"]*"\s*)?<(?:http|https|ftp|irc|file):.+?>};

sub html {
    my $self = shift;
    my $match = $self->matched;
    $match =~ s/<([^>]*)>$/$1/;

    my $text = $match;
    
    if ($match =~ s/^"(.*?)"\s*//) {
        my $quoted = $1;
        $text = $quoted;
    }

    my $target =
        $self->current_workspace->external_links_open_new_window
        ? qq{target="_blank"}
        : '';

    my $wrap_start  = '';
    my $wrap_finish = '';
    if ( $match =~ m{^\w+:(?!//)} ) {
        my $original = $match;
        $match = $self->_special_http_link($match);

        $wrap_start  = '<span class="nlw_phrase">';
        $wrap_finish = '<!-- wiki: ' . $self->matched . ' --></span>';
    }
    my $href = $self->html_escape($match);
    my $escaped_text = $self->html_escape($text);
    my $output =
        $match =~ /\.(gif|jpg|jpeg|jpe|png|pbm|bmp)$/i
        ?  ( $text ? qq{<a href="$href">$text</a>} : qq{<img alt="$escaped_text" src="$href" border="0" />} )
        : $match =~ /^irc:/
        ? "<a title=\"(" . loc('link.irc') . "\" href=\"$href\">$escaped_text</a>"
        : "<a $target rel=\"nofollow\" title=\"(" . loc('link.external') .')" '
        . qq{href="$href">$escaped_text</a>};
    return $wrap_start . $output . $wrap_finish;
}

################################################################################
package Socialtext::Formatter::IMLink;

use base 'Socialtext::Formatter::Phrase';
use Class::Field qw( const );

const formatter_id => 'im';

my %im_types = (
    yahoo  => 'yahoo',
    ymsgr  => 'yahoo',
    callto => 'callto',
    skype  => 'callto',
    callme => 'callto', 
    aim    => 'aim',
);
my $im_re = join '|', keys %im_types;
const pattern_start => qr/\b(?:$im_re)\:[^\s\>\)]+/;

sub html {
    my $self = shift;
    my $match = $self->matched;

    my ( $scheme, $recipient ) = $match =~ /\b($im_re):([^\s\>\)]+)/;

    my $method = "_$im_types{$scheme}_link";

    # {bz: 2041}: This can happen when a cached parsetree containing removed
    # im_type was cached on disk.
    return $match unless $self->can($method);

    $self->_enspan_nlw_link(
        $scheme,
        $recipient,
        $self->$method( $self->escape_html($recipient), $match ),
    );
}

# XXX other option here is to canonicalize these things
# to wafl, which seems fishy and leaves out http:base/foo/bar.png
sub _enspan_nlw_link {
    my $self = shift;
    my $scheme = shift;
    my $recipient = shift;
    my $text = shift;
    my $link = "$scheme:$recipient";
    $self->hub->wikiwyg->generate_widget_image($link);
    qq{<span class="nlw_phrase">$text<!-- wiki: $link --></span>};
}

sub _yahoo_link {
    my $self = shift;
    return
        qq{<a href="ymsgr:sendIM?$_[0]"><img alt="$_[0]" src="http://opi.yahoo.com/online?u=$_[0]&amp;f=.gif" border="0" />$_[0]</a>};
}

sub _aim_link {
    my $self = shift;
    return
        qq{<a href="aim:goim?screenname=$_[0]&amp;message=hello"><img alt="$_[0]" src="http://big.oscar.aol.com/$_[0]?on_url=http://www.aim.com/remote/gr/MNB_online.gif&amp;off_url=http://www.aim.com/remote/gr/MNB_offline.gif" border="0" width="11" height="13" />$_[0]</a>};
}

sub _msn_link {
    my $self = shift;
    $self->escape_html( $_[1] );
}

sub _callto_link {
    my $self = shift;
    return
        qq{<a href="callto:$_[0]"><img alt="$_[0]" src="http://goodies.skype.com/graphics/skypeme_btn_small_green.gif" border="0" />$_[0]</a>};
}

################################################################################
package Socialtext::Formatter::MailLink;

use base 'Socialtext::Formatter::Phrase';
use Class::Field qw( const );

const formatter_id  => 'mail';
const pattern_start => qr/[\w+%\-\.]+@(?:[\w\-]+\.)+[\w\-]+/;

sub html {
    my $self = shift;
    my $email_address = $self->matched;
    my $href = $email_address;
    $href =~ s/\%/\%25/g;

    '<a href="mailto:' . $href . '">' . $email_address . '</a>';
}

################################################################################
package Socialtext::Formatter::BracketMailLink;

use base 'Socialtext::Formatter::Phrase';
use Class::Field qw( const );

const formatter_id => 'b_mail';

# XXX this should reuse the regexp from MailLink, rather than copy
const pattern_start =>
    qr/("[^"]*"\s*)?<mailto:[\w+%\-\.]+@(?:[\w\-]+\.)+[\w\-]+>/;

sub html {
    my $self = shift;
    my $match = $self->matched;
    $match =~ s/<mailto:(.*)>$/$1/;
    my $text = ( $match =~ s/^"(.*?)"\s*// ) ? $1 : $match;
    '<a href="mailto:' . $match . '">' . $text . '</a>';
}

################################################################################
package Socialtext::Formatter::FileLink;

use base 'Socialtext::Formatter::Phrase';
use Class::Field qw( const );

const formatter_id  => 'file';
const pattern_start => qr/("[^"]*")?<\\\\[^\s\>\)]+>/;

sub html {
    my $self = shift;
    my $match = $self->matched;
    $match =~ s/<(\\\\.*)>$/$1/;
    my $text = ( $match =~ s/^"(.*?)"// ) ? $1 : $match;
    $match =~ s/^\\\\//;
    qq{<a target="_blank" title="(network resource)" href="file://$match">$text</a>};
}


1;
