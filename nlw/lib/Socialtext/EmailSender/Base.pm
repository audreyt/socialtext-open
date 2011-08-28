# @COPYRIGHT@
package Socialtext::EmailSender::Base;

use strict;
use warnings;

our $VERSION = '0.01';

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
use Socialtext::MIME::Types;
use Socialtext::Validate
    qw( validate SCALAR_TYPE ARRAYREF_TYPE HASHREF_TYPE SCALAR_OR_ARRAYREF_TYPE BOOLEAN_TYPE );
use vars qw[$SendClass];

$Email::Send::Sendmail::SENDMAIL = '/usr/sbin/sendmail';
$SendClass                       = 'Sendmail';

{
    Readonly my $spec => {
        to   => SCALAR_OR_ARRAYREF_TYPE,
        cc   => SCALAR_OR_ARRAYREF_TYPE( optional => 1 ),
        from => SCALAR_TYPE(
            default => 'Socialtext Workspace <noreply@socialtext.com>'
        ),
        subject     => SCALAR_TYPE,
        text_body   => SCALAR_TYPE( optional => 1 ),
        html_body   => SCALAR_TYPE( optional => 1 ),
        attachments => SCALAR_OR_ARRAYREF_TYPE( default => [] ),

        # default max size is 5MB
        max_size => SCALAR_TYPE( default => 1024 * 1024 * 5 ),
    };

    sub get_send_class {
        if (my $file = $ENV{ST_EMAIL_TO_FILE}) {
            require Email::Send::IO;
            @Email::Send::IO::IO = ($file);
            return 'IO';
        }

        return $SendClass;
    }

    sub _text_body {
        my $self     = shift;
        my $body     = shift;
        my $encoding = shift;
        return Encode::encode( $encoding, $body );
    }

    sub _html_body {
        my $self     = shift;
        my $body     = shift;
        my $encoding = shift;
        return Encode::encode( $encoding, $body );
    }

    sub _attachment_part {
        my $self = shift;
        my $file_or_attach = shift;
        my ($file, $filename, $ct);
        
        if (ref($file_or_attach)) {
            my $attach = $file_or_attach;
            $attach->ensure_stored;
            $file = $attach->disk_filename;
            $filename = $attach->clean_filename;
            $ct = $attach->mime_type;
        }
        else {
            $file = $file_or_attach;
            $filename = File::Basename::basename($file);
            $ct = Socialtext::MIME::Types::mimeTypeOf($file),
        }

        my $content_id = $filename;
        $filename = $self->_encode_filename($filename);

        return Email::MIME->create(
            header     => [ 'Content-Id' => $content_id ],
            attributes => {
                content_type => $ct,
                charset      => '',
                disposition  => 'attachment',
                encoding     => 'base64',
                filename     => $filename,
            },
            body => scalar File::Slurp::read_file($file),
        );
    }

    sub send {
        my $self = shift;
        my %p    = validate( @_, $spec );

        unless ( $p{text_body} or $p{html_body} ) {
            param_error
                'You must provide a text or HTML body when calling Socialtext::EmailSender::send()';
        }

        my $to = ref $p{to} ? join ', ', @{ $p{to} } : $p{to};
        my $cc = ref $p{cc} ? join ', ', @{ $p{cc} } : $p{cc};

        $to = $self->_encode_address( $to );
        $cc = $self->_encode_address( $cc );
        $p{from} = $self->_encode_address( $p{from} );

        $p{subject} = $self->_encode_subject( $p{subject} );
        my $encoding = $self->_get_encoding();
        my %headers  = (
            From         => $p{from},
            To           => $to,
            Subject      => $p{subject},
            'Message-ID' => '<' . Email::MessageID->new . '>',
            'X-Sender'   => "Socialtext::EmailSender v$VERSION",
            'Content-Transfer-Encoding' =>
                $self->_get_content_transfer_encoding($encoding),
        );
        $headers{Cc} = $cc if $cc;

        my $text_body_part;
        my $html_body_part;
        my $charset = $self->_get_charset($encoding);
        if ( $p{text_body} ) {

            # Fix charset: to upper case
            $text_body_part = Email::MIME->create(
                attributes => {
                    content_type => 'text/plain',
                    disposition  => 'inline',
                    charset      => $charset,
                },
                body => $self->_text_body( $p{text_body}, $encoding ),
            );
        }

        if ( $p{html_body} ) {
            $html_body_part = Email::MIME->create(
                attributes => {
                    content_type => 'text/html',
                    disposition  => 'inline',
                    charset      => $charset,
                },
                body => $self->_html_body( $p{html_body}, $encoding ),
            );

            my %basenames;
            if (@{$p{attachments}} and ref($p{attachments}->[0])) {
                %basenames =
                    map { $_->clean_filename => $_ }
                    grep { !$_->is_deleted }
                    @{ $p{attachments} };
            }
            else {
                # Assume they are filenames
                %basenames =
                    map { File::Basename::basename($_) => $_ }
                    grep {-f} @{ $p{attachments} };
            }

            my %cids;
            while ( $p{html_body} =~ /\G.*?src="cid:([^"]+)"/gs ) {
                $cids{$1} = 1
                    if $basenames{$1};
            }

            if ( keys %cids ) {
                my @image_parts
                    = map { $self->_attachment_part( $basenames{$_} ) }
                    keys %cids;

                # The structure will be:
                #
                # multipart/related
                #  - text/html body
                #  - image cid 1
                #  - image cid 2
                #  - etc
                $html_body_part = Email::MIME->create(
                    header => [
                        'Content-Type' =>
                            'multipart/related; type="text/html"'
                    ],
                    parts => [ $html_body_part, @image_parts ],
                );

                $p{attachments}
                    = [ grep { !$cids{ File::Basename::basename($_) } }
                        @{ $p{attachments} } ];
            }
        }

        my $body;
        if ( $text_body_part and $html_body_part ) {
            $body = Email::MIME->create(
                header => [ 'Content-Type'   => 'multipart/alternative' ],
                parts  => [ $text_body_part, $html_body_part ],
            );
        }
        else {
            $body = first {defined} $text_body_part, $html_body_part;
        }

        my @attachments;
        my $total_size = 0;
        for my $attach ( @{ $p{attachments} } ) {
            # could be an object or filename
            next unless ref($attach) || -f $attach;

            my $att_size = ref($attach)
                ? $attach->content_length
                : -s $attach;

            next if $p{max_size} and $total_size + $att_size > $p{max_size};

            push @attachments, $self->_attachment_part($attach);

            $total_size += $att_size;
        }
        my $email;
        if (@attachments) {

            # The goal here is to produce an email of this structure
            #
            # multipart/mixed
            #  - multipart/alternative
            #    - text/plain
            #    - text/html
            #  - attachment 1
            #  - attachment 2
            #  - etc
            #
            # I tested this type in both Pine and Thunderbird, and it
            # displays the HTML part by default, and the file
            # attachments are viewable/downloadable as appropriate.
            $email = Email::MIME->create(
                header => [
                    %headers,
                    'Content-Type' => 'multipart/mixed',
                ],
                parts => [ $body, @attachments ],
            );
        }
        else {

            # If there's no attachments we already have an appropriate
            # top-level structure with the $body part we created
            # earlier, we just need to add the appropriate headers.
            $email = $body;

            $email->header_set( $_ => $headers{$_} ) for keys %headers;
        }

        Email::Send->new( { mailer => $self->get_send_class } )->send($email);
    }

}

1;

__END__

=head1 NAME

Socialtext::EmailSender::Base - A base class for sending email

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS/FUNCTIONS

