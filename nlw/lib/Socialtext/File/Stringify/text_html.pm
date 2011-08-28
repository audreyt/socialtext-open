# @COPYRIGHT@
package Socialtext::File::Stringify::text_html;
use warnings;
use strict;

use Socialtext::File::Stringify::Default;
use Socialtext::System ();
use Socialtext::Log qw/st_log/;
use Socialtext::AppConfig;

use File::Slurp 'slurp';
use HTML::Parser ();
use HTML::HeadParser ();
use HTML::Entities qw/decode_entities/;
use File::Temp qw/tempfile/;
use Encode ();
use Encode::Guess ();
use POSIX ();
use Guard;
use List::MoreUtils qw/firstidx/;

our $DEFAULT_OK = 1;

sub to_string {
    my ( $class, $buf_ref, $filename, $mime ) = @_;

    return if $class->stringify_html($buf_ref, $filename, $mime);
    if ($DEFAULT_OK) {
        st_log()->error($@) if $@;
        Socialtext::File::Stringify::Default->to_string(
            $buf_ref,$filename,$mime);
    }
    else {
        die $@ if $@;
    }
    return;
}

our $temp_fh;
our $limit;

sub stringify_html {
    my ( $class, $buf_ref, $filename, $mime ) = @_;

    my ($charset) = ($mime =~ /charset=(.+);?/);

    my $temp_filename;
    local $temp_fh;
    local $limit = Socialtext::AppConfig->stringify_max_length;
    ($temp_fh, $temp_filename) = tempfile(
        "/tmp/htmlstringify-$$-XXXXXX", UNLINK => 0);
    # Anonymize the tempfile. Reduces the likelyhood of other procs reading it
    # and to automagically cleans up the storage once we drop the file-handle.
    unlink $temp_filename;

    binmode $temp_fh, ':utf8';

    my $pid = fork;
    die "can't fork html stringifier: $!" unless defined $pid;
    if ($pid) { # parent
        my $g = guard { kill -9, $pid; waitpid $pid, POSIX::WNOHANG(); };
        scope_guard { unlink "$temp_filename.err" };
        eval {
            local $SIG{ALRM} = sub { die 'Command Timeout' };
            alarm $Socialtext::System::TIMEOUT;
            waitpid $pid, 0; # wait until timeout or process exit
            alarm 0;
        };
        my $rv = $? >> 8;
        if ($rv) {
            $@ ||= "code $rv";
            my $err = '';
            $err = slurp("$temp_filename.err") if -s "$temp_filename.err";
            $@ = "HTML stringifier failed: $@ $err (code: $rv)";
            return;
        }
        else {
            $g->cancel;
        }
    }
    else { # kid
        scope_guard { POSIX::_exit(1) }; # kill the process on exceptions

        open STDERR, '>', "$temp_filename.err";
        select STDERR; $|=1; select STDOUT;

        # XXX: this doesn't work when Test::Socialtext is used?!
        Socialtext::System::_vmem_limiter();

        eval { _run_stringifier($filename, $charset); };
        if ($@) { warn $@; die $@ }

        $temp_fh->flush or die "can't flush: $!";
        close $temp_fh or die "can't close: $!";
        POSIX::_exit(0);
    }

    # turn utf8 layer off so we can slurp with max efficiency!
    seek $temp_fh, 0, 0; # rewind
    binmode $temp_fh, ':mmap';
    $$buf_ref = do { local $/; <$temp_fh> };
    close $temp_fh;

    # And because it just wrote the file as utf8 so we can safely just switch
    # the flag on.
    Encode::_utf8_on($$buf_ref);

    return 1;
}

our $parser;
our $count;

sub _run_stringifier {
    my ($filename, $charset) = @_;

    my $enc;
    if ($charset) {
        $charset = lc($1).lc($2) if ($charset =~ /^(utf|ucs)-?(.+)$/);
        $enc = Encode::find_encoding($charset);
    }

    unless ($charset && $enc && ref($enc)) {
        $charset = _detect_charset($filename);
        $enc = Encode::find_encoding($charset) if $charset;
    }

    undef $enc unless ref($enc);
    $enc ||= Encode::find_encoding('ISO-8859-1');

    # Could use a PerlIO layer and ->parse_file, but we want un-decodable
    # characters converted into HTML entities as a fallback mode.
    open my $fh, '<:mmap', $filename or die "Can't open $filename: $!";
    # if it's really big, limit it; parser seems to do just fine with
    # truncated HTML
    my $doc;
    {
        my $to_read = 8*$limit;
        my $in = do { local $/ = \$to_read; <$fh> };
        $doc = $enc->decode($in, Encode::FB_WARN|Encode::FB_HTMLCREF);
    }
    close $fh;

    local $count = 0;
    local $parser = HTML::Parser->new(
        ignore_elements => [qw(style script)],
        text_h  => [\&_got_text,  'text'], # *not* dtext
        start_h => [\&_got_start, 'tagname, @attr'],
        utf8_mode => 0, # we do our own decoding of charsets
        attr_encoded => 1, # do our own decoding of attr entities
        case_sensitive => 0, # lowercase tags and attrs
    );
    $parser->parse($doc);
    $parser->eof();
    return;
}

sub _detect_charset {
    my $filename = shift;
    my $hp = HTML::HeadParser->new();
    $hp->parse_file($filename);

    my $charset = $hp->header('Content-Type');
    if ($charset) {
        my ($cs) = ($charset =~ /charset=(.+);?/);
        $charset = $cs ? $cs : undef;
    }
    else {
        $charset = $hp->header('X-Meta-Charset');
    }

    # Check if the file seems to be one of the Unicode charsets.  UTF-16 foils
    # HTML::HeadParser.
    unless ($charset) {
        my $first_1k = do { local (@ARGV) = ($filename); local $/ = \1024; <> };
        Encode::Guess->set_suspects(
            qw/UTF-32LE UTF-16LE UTF-32BE UTF-16BE UTF-8/);
        my $guess = Encode::Guess->guess($first_1k);
        $charset = $guess->name if ($guess && ref($guess));
    }

    $charset ||= 'UTF-8';
    return $charset;
}

sub _got_text {
    my $txt = shift;
    decode_entities($txt);
    $txt =~ s/\s+/ /smg;
    return if ($txt eq ' ' || $txt eq '');
    $txt .= ' ';
    $count += length($txt);
    print $temp_fh $txt;
    $parser->eof if $count > $limit;
}

sub _got_start {
    my $tag = shift;
    my $txt;
    if ($tag eq 'a') {
        my $i = firstidx { $_ eq 'href' } @_;
        $txt = $_[$i+1] if ($i >= 0 && $i <= $#_);

        # don't emit relative links or links missing a scheme (e.g. http:)
        if ($txt and $txt =~ m#^/# || $txt !~ m#^[a-z]+:#i) {
            undef $txt;
        }
    }
    elsif ($tag eq 'meta') {
        my %attr = @_;
        if (my $name = $attr{name}) {
            $txt = $attr{content}
                if ($name =~ /^(?:keywords|description|author)$/i);
        }
    }

    return unless defined $txt;
    decode_entities($txt);
    $txt .= ' ';
    $count += length($txt);
    print $temp_fh $txt;
    $parser->eof if $count > $limit;
}

1;
__END__

=head1 NAME

Socialtext::File::Stringify::text_html - Stringify HTML documents

=head1 CLASS METHODS

=over

=item to_string($filename)

Extracts the stringified content from C<$filename>, an HTML document.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT

Copyright 2006-2010 Socialtext, Inc., all rights reserved.

=cut
