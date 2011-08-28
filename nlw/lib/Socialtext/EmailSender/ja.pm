# @COPYRIGHT@
package Socialtext::EmailSender::ja;

use strict;
use warnings;

our $VERSION = '0.01';

use base 'Socialtext::EmailSender::Base';
use Email::Valid;
use Email::MessageID;
use Email::MIME;
use Email::MIME::Creator;
use Email::Send qw();
use Email::Send::Sendmail;
use Encode qw(decode_utf8);
use File::Basename ();
use File::Slurp    ();
use List::Util qw(first);
use Readonly;
use Socialtext::Exceptions qw( param_error );
use Socialtext::Validate
    qw( validate SCALAR_TYPE ARRAYREF_TYPE HASHREF_TYPE SCALAR_OR_ARRAYREF_TYPE BOOLEAN_TYPE );
use charnames ":full";

use Encode::Alias;
use Encode::Unicode::Japanese;
use Lingua::JA::Fold;
use Jcode;
use Unicode::Japanese;

$Email::Send::Sendmail::SENDMAIL = '/usr/sbin/sendmail';
our ($H2Z, %H2Z);



{

    # solve WAVE DASH problems
    define_alias( qr/iso-2022-jp$/i => '"unijp-jis"' );

    sub new {
        my $pkg = shift;
        bless {}, $pkg;
    }

    sub _h2z {
        my $self    = shift;
        my $text    = shift;
        $text = Unicode::Japanese->new($text)->h2zKana->get() || '';
        $text =~ s/($H2Z)/(exists $H2Z{$1} ? $H2Z{$1} : $1)/ego;
        return $text;
    }

    sub _encode_address {
        my $self    = shift;
        my $address = shift;
        
        $address = $self->_h2z($address);
        $address = Jcode->new($address,'utf8')->mime_encode;
        return $address;
    }

    sub _encode_subject {
        my $self    = shift;
        my $subject = shift;

        # Encode::MIME::Header will buggily add extra spaces when
        # encoding, so we only encode the subject, as that is the only
        # part we think will ever need it. Dave is working on fixing
        # the bug.
        if ( $subject =~ /[\x7F-\xFF]/ ) {
            $subject = Encode::encode( 'MIME-Header', $subject );
        }
        else {

            # This shuts up a "wide character in print" warning from
            # inside Email::Send::Sendmail.
            $subject = $self->_h2z($subject);

            # It's not known exactly why Encode::encode(
            # 'MIME-Header-ISO_2022_JP', $subject ) encodes to iso-2022-jp encoding,
            # not MIME-B encoding. So use Jcode.
            $subject = Jcode->new($subject,'utf8')->mime_encode;
        }

        return $subject;
    }

    sub _fold_body {
        my $self    = shift;
        my $body    = shift; 
        # fold line over 989bytes because some smtp server chop line over 989
        # bytes and this causes mojibake
        Encode::_utf8_on($body) unless Encode::is_utf8($body);

        my $folded_body;
        my $line_length;
        my @lines = split /\n/, $body;
        foreach my $line (@lines) {
            {
                use bytes;
                $line_length = length($line);
            }
            if($line_length > 988) {
                $line = fold( 'text' => $line, 'length' => 300 );
            }
            
            $folded_body .= $line;
            if(@lines > 1) {
                $folded_body .= "\n";
            }
        }
        $body = $folded_body;
        return $body; 
    }

    sub _text_body {
        my $self     = shift;
        my $body     = shift;
        my $encoding = shift;

        $body = $self->_h2z($body);
        $body = $self->_fold_body($body);

        # solve WAVE DASH problem
        $body =~ tr/[\x{ff5e}\x{2225}\x{ff0d}\x{ffe0}\x{ffe1}\x{ffe2}]/[\x{301c}\x{2016}\x{2212}\x{00a2}\x{00a3}\x{00ac}]/;

        $body = Encode::encode($encoding, $body);

        return $body;
    }

    sub _html_body {
        my $self     = shift;
        my $body     = shift;
        my $encoding = shift;

        $body = $self->_h2z($body);
        $body = $self->_fold_body($body);

        # solve WAVE DASH problem
        $body =~ tr/[\x{ff5e}\x{2225}\x{ff0d}\x{ffe0}\x{ffe1}\x{ffe2}]/[\x{301c}\x{2016}\x{2212}\x{00a2}\x{00a3}\x{00ac}]/;

        $body = Encode::encode($encoding, $body);
        return $body;
    }

    sub _encode_filename {
        my $self     = shift;
        my $filename = shift;

        Encode::_utf8_off($filename) if Encode::is_utf8($filename);

        $filename = $self->_uri_unescape($filename);

        # If filename is only ascii code, you do not encode fileme to MIME-B.
        # It's not known exactly why Encode::encode(
        # 'MIME-Header-ISO_2022_JP', $subject ) encodes to iso-2022-jp encoding,
        # not MIME-B encoding. So use Jcode.
        $filename = Jcode->new($filename,'utf8')->mime_encode;

        return $filename;
    }

    sub _get_encoding { 'iso-2022-jp' } # for Encode
    sub _get_charset  { 'ISO-2022-JP' } # for headers
    sub _get_content_transfer_encoding { '7bit' }

    sub _uri_unescape {
        my $self = shift;
        my $data = shift;
        $data = URI::Escape::uri_unescape($data);
        return $self->_utf8_decode($data);
    }

    sub _utf8_decode {
        my $self = shift;
        my $data = shift;
        $data = Encode::decode( 'utf8', $data )
            if defined $data
            and not Encode::is_utf8($data);
        return $data;
    }

}

BEGIN {
    my $normalize_table = {
                "\342\221\240" => '(1)',
        	"\342\221\241" => '(2)',
        	"\342\221\242" => '(3)',
        	"\342\221\243" => '(4)',
        	"\342\221\244" => '(5)',
		"\342\221\245" => '(6)',
		"\342\221\246" => '(7)',
		"\342\221\247" => '(8)',
		"\342\221\250" => '(9)',
		"\342\221\251" => '(10)',
		"\342\221\252" => '(11)',
		"\342\221\253" => '(12)',
		"\342\221\254" => '(13)',
		"\342\221\255" => '(14)',
		"\342\221\256" => '(15)',
		"\342\221\257" => '(16)',
		"\342\221\260" => '(17)',
		"\342\221\261" => '(18)',
		"\342\221\262" => '(19)',
		"\342\221\263" => '(20)',
		"\342\205\240" => 'I',
		"\342\205\241" => 'II',
		"\342\205\242" => 'III',
		"\342\205\243" => 'IV',
		"\342\205\244" => 'V',
		"\342\205\245" => 'VI',
		"\342\205\246" => 'VII',
		"\342\205\247" => 'VIII',
		"\342\205\250" => 'IX',
		"\342\205\251" => 'X',
		"\342\205\260" => 'i',
		"\342\205\261" => 'ii',
		"\342\205\262" => 'iii',
		"\342\205\263" => 'iv',
		"\342\205\264" => 'v',
		"\342\205\265" => 'iv',
		"\342\205\266" => 'vii',
		"\342\205\267" => 'viii',
		"\342\205\270" => 'ix',
		"\342\205\271" => 'x',
		"\343\215\211" => 'ミリ',
		"\343\214\224" => 'キロ',
		"\343\214\242" => 'センチ',
		"\343\215\215" => 'メートル',
		"\343\214\230" => 'グラム',
		"\343\214\247" => 'トン',
		"\343\214\203" => 'アール',
		"\343\214\266" => 'ヘクタール',
		"\343\215\221" => 'リットル',
		"\343\215\227" => 'ワット',
		"\343\214\215" => 'カロリー',
		"\343\214\246" => 'ドル',
		"\343\214\243" => 'セント',
		"\343\214\253" => 'パーセント',
		"\343\215\212" => 'ミリバール',
		"\343\214\273" => 'ページ',
		"\343\216\234" => 'mm',
		"\343\216\235" => 'cm',
		"\343\216\236" => 'km',
		"\343\216\216" => 'mg',
		"\343\216\217" => 'kg',
		"\343\217\204" => 'cc',
		"\343\216\241" => 'm2',
		"\343\215\273" => '平成',
		"\342\204\226" => 'No.',
		"\343\217\215" => 'K.K.',
		"\342\204\241" => 'TEL',
		"\343\212\244" => '(上)',
		"\343\212\245" => '(中)',
		"\343\212\246" => '(下)',
		"\343\212\247" => '(左)',
		"\343\212\250" => '(右)',
		"\343\210\261" => '(株)',
		"\343\210\262" => '(有)',
		"\343\210\271" => '(代)',
		"\343\215\276" => '明治',
		"\343\215\275" => '大正',
		"\343\215\274" => '昭和',
    };


    while (my ($key, $val) = each %$normalize_table) {
        $H2Z{$key} = $val;
        $H2Z .= (defined $H2Z ? '|' : '') . quotemeta($key);
    }
}

1;

__END__

=head1 NAME

Socialtext::EmailSender::ja - An API for sending email

=head1 SYNOPSIS

Perhaps a little code snippet.

  use Socialtext::EmailSender;

  Socialtext::EmailSender->send( ... );

=head1 DESCRIPTION

This module provides a high-level API for sending emails. It can send
emails with text and/or HTML parts, as well as attachments.

It uses C<Email::Send::Sendmail> to actually send mail, and it tells
the sender to find the F<sendmail> program at F</usr/bin/sendmail>.

=head1 METHODS/FUNCTIONS

This module has the following methods:

=head2 send( ... )

This method accepts a number of parameters:

=over 4

=item * to - required

A scalar or array reference of email addresses.

=item * cc - optional

A scalar or array reference of email addresses.

=item * from - has default

The default from address is "Socialtext Workspace
<noreply@socialtext.com>".

=item * text_body - optional

The email's body in text format.

=item * html_body - optional

The email's body in HTML format.

If this body contains C<< <img> >> tags where the "src" attribute's
URI uses the "cid:" scheme, it looks for the references image in the
attachments. If the image is present, generated email should cause the
image to display in clients that display the HTML body. This means
that the image will I<not> show up in the list of attachments for that
email.

=item * attachments - optional

A scalar or array reference of filenames, which will be attached to
the email.

=item * max_size - defaults to 5MB (5 * 1024 * 1024)

The maximum total size in bytes of all attachments for the email. If
an attachment would cause this size to be exceeded, it is not
attached.

To allows an unlimited size, set this to 0.

=back

While both "text_body" and "html_body" are optional, I<at least one>
of them must be provioded.


=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005-2006 Socialtext, Inc., All Rights Reserved.

=cut
