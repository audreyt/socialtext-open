# @COPYRIGHT@
package Socialtext::EmailSender::en;

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
use Encode         ();
use File::Basename ();
use File::Slurp    ();
use List::Util qw(first);
use Readonly;
use Socialtext::Exceptions qw( param_error );
use Socialtext::Validate
    qw( validate SCALAR_TYPE ARRAYREF_TYPE HASHREF_TYPE SCALAR_OR_ARRAYREF_TYPE BOOLEAN_TYPE );

$Email::Send::Sendmail::SENDMAIL = '/usr/sbin/sendmail';

{

    sub new {
        my $pkg = shift;
        bless {}, $pkg;
    }

    sub _encode_address {
        my $self    = shift;
        my $address = shift;
        return Encode::encode('utf8' => $address);
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
            $subject = Encode::encode( 'utf8', $subject );
        }
        return $subject;
    }

    sub _encode_filename {
        my $self     = shift;
        my $filename = shift;
        return $filename;
    }

    sub _get_encoding { 'utf8' }  # for Encode
    sub _get_charset  { 'UTF-8' } # for headers
    sub _get_content_transfer_encoding { '8bit' }
}
1;

__END__

=head1 NAME

Socialtext::EmailSender::en

=head1 SYNOPSIS

  use Socialtext::EmailSender::Factory;
  my $locale = 'en'; # or 'ja'
  $email_sender = Socialtext::EmailSender::Factory->create($locale);
  $email_sender->send( ... );

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
