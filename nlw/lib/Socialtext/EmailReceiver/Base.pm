# @COPYRIGHT@
package Socialtext::EmailReceiver::Base;
use 5.12.0;
use warnings;

our $VERSION = '0.01';

use Readonly;
require bytes;
use DateTime;
use Email::Address;
use Email::MIME;
use Email::MIME::ContentType ();
use Email::MIME::Modifier;    # provides walk_parts()
use Fcntl qw( SEEK_SET );
use HTML::TreeBuilder ();
use Text::Flowed ();
use DateTime::Format::Mail;
use HTML::WikiConverter ();
use IO::Scalar;
use Filesys::DfPortable ();

use Socialtext::Authz;
use Socialtext::CategoryPlugin;
use Socialtext::Exceptions qw( auth_error system_error data_validation_error );
use Socialtext::Log qw( st_log );
use Socialtext::Permission qw( ST_EMAIL_IN_PERM );
use Socialtext::User ();
use Socialtext::Page ();
use Socialtext::String ();
use Socialtext::File;
use Socialtext::l10n qw(loc system_locale);
use Socialtext::Validate
    qw( validate SCALAR_TYPE HANDLE_TYPE WORKSPACE_TYPE );

sub _new {
    my $class     = shift;
    my $email     = shift;
    my $workspace = shift;

    return bless {
        email          => $email,
        workspace      => $workspace,
        body           => \'',
        attachments    => [],
        categories     => ['Email'],
        body_placement => $workspace->incoming_email_placement(),
    }, $class;
}

sub receive {
    my $self = shift;

    $self->_clean_email();

    $self->{from}
        = ( Email::Address->parse( $self->{email}->header('From') ) )[0];

    unless ( $self->{from} ) {
        auth_error
            'Socialtext does not accept email from unidentified senders.';
    }

    my $email_address = $self->{from}->address();

    $self->_require_email_in_permission( $email_address );
    $self->_get_user_for_address( $email_address );
    $self->_load_hub();
    $self->_get_page_for_subject();
    $self->_lock_check();
    $self->_save_body_and_strip_attachments();
    $self->_get_email_body();
    $self->_save_html_bodies_as_attachments();

    # Must be done after we get the email body, because there may be
    # "category: ..." commands in the body.
    $self->_set_page_categories();

    $self->_update_page_body();
}

sub _clean_email {
    my $self = shift;

    my $encoding = $self->{email}->header('Content-Transfer-Encoding');

    # We have an email in our test corpus with an encoding of "8-bit",
    # which is not RFC-compliant, but it'd be nice to not blow up on
    # simple mistakes like that.
    if ( $encoding and $encoding =~ s/([78])-bit/${1}bit/ ) {

        # Cannot call ->encoding_set() since that calls ->body()
        # internally _before_ changing the encoding, which blows up
        # because of the bogus encoding.
        $self->{email}
            ->header_set( 'Content-Transfer-Encoding' => $encoding );
    }
}

sub _require_email_in_permission {
    my $self          = shift;
    my $email_address = shift;

    my $user = Socialtext::User->new( email_address => $email_address );

    my $authz = Socialtext::Authz->new();

    my $has_perm = 0;
    if (
        $user
        and $authz->user_has_permission_for_workspace(
            user       => $user,
            permission => ST_EMAIL_IN_PERM,
            workspace  => $self->{workspace},
        )
        ) {
        $has_perm = 1;
    }

    # We do things this way because we don't want to insert a user
    # into the DBMS just to find out that the newly created user does
    # not have permission to email_in to the workspace.
    #
    # We were doing this briefly on prod and added approximately 6,500
    # users in one week, which is obviously a problem over the long
    # term.
    elsif (
        $self->{workspace}->permissions->role_can(
            permission => ST_EMAIL_IN_PERM,
            role       => Socialtext::Role->Guest(),
        )
        ) {
        $has_perm = 1;
    }

    auth_error "You do not have permission to send email to the "
        . $self->{workspace}->name()
        . ' workspace.'
        unless $has_perm;
}

sub _lock_check {
    my $self = shift;
    my $page = $self->{page};

    auth_error 'You do not have permission to overwrite the ' .
    $page->title . ' page in the ' . $self->{workspace}->name . ' workspace.' 
        unless $self->{hub}->checker->can_modify_locked( $page );
}

sub _get_user_for_address {
    my $self          = shift;
    my $email_address = shift;

    my $user = Socialtext::User->new( email_address => $email_address );

    $user ||= Socialtext::User->create(
        username      => $email_address,
        email_address => $email_address,
    );

    $self->{user} = $user;
}

sub _load_hub {
    my $self = shift;

    my $main = Socialtext->new();
    $main->load_hub(
        current_user      => $self->{user},
        current_workspace => $self->{workspace},
    );

    $self->{hub} = $main->hub;
}

sub _get_page_for_subject {
    my $self = shift;

    my $subject = $self->_clean_subject();
    if (length Socialtext::String::uri_escape($subject) 
        > Socialtext::String::MAX_PAGE_ID_LEN ) {
        data_validation_error loc("error.page-title-too-long");
        return;
    }

    my $page = $self->{hub}->pages()->new_from_name($subject);
    if (! defined($page) ) {
        data_validation_error loc("error.page-title-too-long");
        return;
    }
    $page->edit_rev();
    $self->{page} = $page;
}

sub _clean_subject {
    my $self = shift;

    my $subject = $self->{email}->header('Subject');

    if ( defined $subject ) {
        $subject =~ s/^\s*(?:(?:fwd|re|fw):\s*)*//ig;
        $subject =~ s/^\s+|\s+$//g;
    }

    unless ( defined $subject and length $subject ) {
        my $sender =
              $self->{from}->name
            ? $self->{from}->name
            : $self->{from}->address;

        my $date = $self->{email}->header('Date');

        $subject = "Mail from $sender, $date";
    }

    return $subject;
}

sub _save_body_and_strip_attachments {
    my $self = shift;

    # This is similar to how Email::MIME::Stripper::Attachments works,
    # except that we simply throw away parts that are neither
    # attachments nor text/*. We ignore "container" type parts like
    # "multipart/alternative" or "multipart/mixed".
    my @body_parts;
    $self->{email}->walk_parts(
        sub {
            return if $self->_get_body_part( $_[0], \@body_parts );

            $self->_save_attachment_from_part( $_[0] );
        }
    );

    $self->{body_parts} = \@body_parts;
}

sub _get_body_part {
    my $self       = shift;
    my $part       = shift;
    my $body_parts = shift;

    my $disp = $part->header('Content-Disposition') || 'inline';

    return unless $disp =~ /inline/i;

    my $ct = Email::MIME::ContentType::parse_content_type(
        $part->content_type() );

    return unless $ct->{discrete} eq 'text';

    push @$body_parts, $part;

    return 1;
}

sub _save_attachment_from_part {
    my $self        = shift;
    my $part        = shift;
    my $ignore_disp = shift;
    my $no_wafl     = shift;

    unless ($ignore_disp) {
        return if $self->_part_is_inline($part);
    }

    # REVIEW - do we need to make sure this is just a filename
    # (without a path)?
    my $filename = $part->filename('force_filename');
    my $page = $self->{page};
    my $body_io = new IO::Scalar \$part->body();

    return unless $self->_has_free_temp_space_for_attachment(
        bytes::length(${$body_io->sref}),
        $filename,
    );

    my $attachment = $page->hub->attachments->create(
        fh => $body_io,
        filename => $filename,
        page => $page,
        user => $self->{user},
    );

    push @{ $self->{attachments} }, $attachment;

    if ( $part->header('Content-ID') ) {
        my $cid = $part->header('Content-ID');
        $cid =~ s/^<//;
        $cid =~ s/>$//;

        $self->{content_id}{$cid} = $filename;
    }

    $self->{no_wafl}{$filename} = 1
        if $no_wafl;
}

sub _part_is_inline {
    my $self = shift;
    my $part = shift;

    my $type = $part->content_type();
    my $disp = $part->header('Content-Disposition');

    # This seems a bit odd - I think it's to handle cases of things
    # like HTML mail with images referred to by cid: URIs, and those
    # images have a content-disposition with a filename, but their
    # disposition is inline.
    return 1
        unless ( $disp and $disp =~ /attachment|inline/i )

        # When testing with Thunderbird, I noticed that when you embed
        # an image in an HTML email, it does not give it a
        # Content-Disposition at all. But clearly if a part if an
        # image we want to save it.
        or $type =~ m{^image};

    return 0;
}

{
    Readonly my $OneMB => 1024**2;

    sub _has_free_temp_space_for_attachment {
        my $self     = shift;
        my $size     = shift;
        my $filename = shift;

        my $dir = $Socialtext::Upload::STORAGE_DIR;
        my $df = Filesys::DfPortable::dfportable($dir);
        return 1 unless $df;
        my $free = $df->{bavail};
        my $free_after_save = $free - $size;

        if ( $free_after_save < $OneMB * 50 ) {
            st_log(   warning => "Saving the $filename attachment in "
                    . $self->{page}->title()
                    . " from "
                    . $self->{from}->address
                    . " would leave less than 50MB free in $dir. Not saving."
            );
            return;
        }
        elsif ( $free_after_save < $OneMB * 500 ) {
            my $mb_free = int( $free_after_save / $OneMB );

            st_log(   warning => "Saving the $filename attachment in "
                    . $self->{page}->title()
                    . " from "
                    . $self->{from}->address
                    . " leaves ${mb_free}MB free in $dir." );
        }

        return 1;
    }
}

sub _get_email_body {
    my $self = shift;

    my @order =
        $self->{workspace}->prefers_incoming_html_email()
        ? qw( html text )
        : qw( text html );

    for my $type (@order) {
        my $meth = "_get_${type}_body";

        $self->$meth() and return;
    }
}

sub _get_text_body {
    my $self = shift;

    my @lines;
    for my $part ( @{ $self->{body_parts} } ) {
        $self->_plain_lines_from_part( $part, \@lines );
    }

    return unless @lines;

    my $body = join "\n",@lines;
    $self->{body}      = \$body;
    $self->{body_type} = 'plain';

    return 1;
}

sub _plain_lines_from_part {
    my $self  = shift;
    my $part  = shift;
    my $lines = shift;

    my $body = $self->_body_from_part_by_type( $part, 'plain' );
    return unless defined $body and length $body;

    # This needs to happen before we reformat flowed text or else the
    # commands may get mashed onto the same lines as text.
    $body = join "\n",
        @{ $self->_scan_lines_for_commands( [ split /\n/, $body ] ) };

    my $ct = Email::MIME::ContentType::parse_content_type(
        $part->content_type() );

    if (    $ct->{composite} eq 'plain'
        and $ct->{attributes}{format}
        and $ct->{attributes}{format} eq 'flowed' ) {
        push @$lines, split /\n/,
            Text::Flowed::reformat(
            $body,
            {
                opt_length => 1000000,
                max_length => 1000000,
            },
            );
    }
    else {
        push @$lines, split /\n/, $body;
    }
}

sub _guess_charset {
    my $self    = shift;
    my $body    = shift;
    my $charset = shift;
    my $locale  = system_locale();

    unless ($charset) {
        my $locale = system_locale();
        $charset = Socialtext::File::guess_string_encoding( $locale, \$body );
    }
    return $charset;
}

sub _body_from_part_by_type {
    my $self = shift;
    my $part = shift;
    my $type = shift;

    my $ct = Email::MIME::ContentType::parse_content_type(
        $part->content_type() );

    return
        unless $ct->{discrete} eq 'text'
        and $ct->{composite}   eq $type;

    my $body = $part->body();
    return $body if Encode::is_utf8($body);

    my $charset = $self->_guess_charset( $body, $ct->{attributes}{charset} );

    Encode::from_to( $body, $charset, 'utf8' );
    Encode::_utf8_on($body) unless Encode::is_utf8($body);

    return $body;
}

sub _scan_lines_for_commands {
    my $self  = shift;
    my $lines = shift;

    my @not_commands;
    while ( my $line = shift @$lines ) {

        # skip initial blank lines
        next unless $line =~ /\S/;

        # This abomination re is designed to deal with poorly
        # constructed format=flowed data.
        unless ( $line =~ /^(\S*?):\s*(\S+.*?)(?:  \S+.*$|\s*$)/ ) {
            unshift @$lines, @not_commands, $line;
            last;
        }

        my $command = lc $1;
        my $value   = $2;

        $value =~ s/^\s+|\s+$//g;

        if ( $command =~ /category|tag/ ) {
            push @{ $self->{categories} }, split /\s*,\s*/, $value;
        }
        elsif ( $command eq 'replace' ) {
            $self->{body_placement} = 'replace';
        }
        elsif ( $command eq 'append' ) {
            my $where = lc $value;
            $self->{body_placement} = $where
                if $where =~ /(?:top|bottom)/;
        }
        else {
            push @not_commands, $line;
        }
    }

    return $lines;
}

sub _get_html_body {
    my $self = shift;

    my @lines;
    for my $part ( @{ $self->{body_parts} } ) {
        $self->_html_lines_from_part( $part, \@lines );
    }

    return unless @lines;

    my $html = join '', @lines;
    my $encode_type = Socialtext::File::guess_string_encoding( 'ja', \$html );
    Encode::_utf8_off($html) if Encode::is_utf8($html);

    my $converter = HTML::WikiConverter->new(
        dialect         => 'Socialtext::Fixed',
        escape_entities => 0
    );
    my $body = $converter->html2wiki($html);

    $body =~ s/{image:\s+cid:(\S+?)}/$self->_wafl_for_cid($1)/eg;

    $self->{body}      = \$body;
    $self->{body_type} = 'html';

    return 1;
}

sub _wafl_for_cid {
    my $self = shift;
    my $cid  = shift;

    return '{image: ' . $self->{content_id}{$cid} . '}'
        if $self->{content_id}{$cid};

    return '{image: ' . $cid . '}';
}

sub _html_lines_from_part {
    my $self  = shift;
    my $part  = shift;
    my $lines = shift;

    my $body = $self->_body_from_part_by_type( $part, 'html' );
    return unless defined $body and length $body;

    my $tree = HTML::TreeBuilder->new_from_content($body);

    # The goal here is to only include elements inside the <body>
    # tag. If the HTML in the email had no <body> tag, we just use the
    # entire tree of elements.
    my $body_tree = $tree->find_by_tag_name('body');
    $body_tree ||= $tree;

    push @$lines, split /\n/, join '',
        map { ref $_ ? $_->as_HTML('utf8') : $_ } $body_tree->content_list();

    $body_tree->delete() if $body_tree->can('delete');
    $tree->delete();
}

sub _save_html_bodies_as_attachments {
    my $self = shift;

    $self->_save_html_body_as_attachment($_) for @{ $self->{body_parts} };
}

sub _save_html_body_as_attachment {
    my $self = shift;
    my $part = shift;

    my $ct = Email::MIME::ContentType::parse_content_type(
        $part->content_type() );

    return unless $ct->{discrete} eq 'text' and $ct->{composite} eq 'html';

    $self->_save_attachment_from_part(
        $part, 'ignore disposition',
        'no wafl'
    );
}

sub _set_page_categories {
    my $self = shift;

    my $local = $self->_get_to_address_local_part();

    my $cat = ( split /[\+\.]/, $local, 2 )[1];
    $cat = Socialtext::CategoryPlugin->Decode_category_email($cat)
        if defined $cat;

    $self->{page}->rev->add_tags([grep {defined} @{$self->{categories}}, $cat]);
}

sub _get_to_address_local_part {
    my $self = shift;

    my $ws_name = $self->{workspace}->name();
    my $ws_re   = qr/\Q$ws_name\E/i;

    # NLW::EmailReceive checked Bcc, but that makes no sense on an
    # incoming message
    for my $address (
        # We start with the shortest address to prevent possible bugs
        # with the use of "." as a category separator. If we have a
        # workspace named john and send mail to john@socialtext.net
        # and john.smith@example.com, we don't want the email to end
        # up in the "smith" category.
        sort { length $a <=> length $b }
        map  { $_->user }
        map  { Email::Address->parse($_) }
        ( map  { $self->{email}->header($_) } qw( To Cc ) ),
        $ENV{RECIPIENT}
        ) {

        return $1 if $address =~ /^\"?($ws_re[^\"]*)\"?/;
    }

    # This could happen if the message arrived via a Bcc to the
    # workspace.
    return $ws_name;
}

sub _update_page_body {
    my $self = shift;

    my $page = $self->{page};
    my $body_ref = $self->_page_body_from_email();
    given ($self->{body_placement}) {
        $page->prepend($body_ref)  when 'top';
        $page->append($body_ref)   when 'bottom';
        $page->body_ref($body_ref);
    }

    $page->store();
}

sub _page_body_from_email {
    my $self = shift;

    my $header = $self->_make_page_header();
    Encode::_utf8_on($header) unless Encode::is_utf8($header);
    Socialtext::Encode::ensure_ref_is_utf8($self->{body});
    my $body = join '', @$header, ${$self->{body}};
    return \$body;
}

sub _make_page_header {
    my $self = shift;

    my @header = ('');                 # will become a newline
    my $from   = loc('email.from:') . ' ';
    if ( my $name = $self->{from}->name() ) {
        $from .= qq|"$name" |;
    }
    $from .= '<mailto:' . $self->{from}->address() . '>';

    push @header, "$from\n";
    my $formated_date;
    if ( $self->{email}->header('Date') ) {
        eval {
            my $datetime = DateTime::Format::Mail->parse_datetime(
                $self->{email}->header('Date') );
            $formated_date = $self->format_date($datetime);
        };
        if ($@) {
            $formated_date = $self->{email}->header('Date');
        }
        push @header, loc('email.date:') . " $formated_date\n";
    }
    for my $att ( @{ $self->{attachments} } ) {
        my $wafl = $att->image_or_file_wafl();
        ( my $re = $wafl ) =~ s/\n//g;

        next if ref($self->{body}) and ${$self->{body}} =~ /\Q$re/s;
        next if $self->{no_wafl}{ $att->filename() };

        push @header, $wafl . "\n\n";
    }

    return \@header;
}

sub format_date {
    die "SubClass must be implemented(format_date).\n";
}

package HTML::WikiConverter::Socialtext::Fixed;

use strict;
use warnings;

use base 'HTML::WikiConverter::Socialtext';

# This works around a bug present in 0.03 of
# HTML::WikiConvert::Socialtext. Presumably KJ will fix it in future
# versions and this can be removed.
sub _image {
    my ( $self, $node, $rules ) = @_;
    my $image_file = $node->attr('src');
    return unless defined $image_file && length $image_file;
    if ( $image_file !~ /http/ ) {
        $image_file =~ s/.*\/([^\/]+)$/$1/g;
        $image_file =~ s/\?action=.*$//g;
        return '{image: ' . $image_file . '} ' || '';
    }
    else {
        return $image_file;
    }
}

# Gah, the original uses direct references to the code (\&_image)
# instead of calling them as methods, so we have to redefine the rules
# to get it to see our new version of _image. KJ, can you fix this
# too?

sub rules {
    return {
        hr => { replace => "\n----\n" },
        br => { replace => "\n" },

        h1 => {
            start => '^ ', block => 1, trim => 'both', line_format => 'single'
        },
        h2 => {
            start => '^^ ', block => 1, trim => 'both',
            line_format => 'single'
        },
        h3 => {
            start => '^^^ ', block => 1, trim => 'both',
            line_format => 'single'
        },
        h4 => {
            start => '^^^^ ', block => 1, trim => 'both',
            line_format => 'single'
        },
        h5 => {
            start => '^^^^^ ', block => 1, trim => 'both',
            line_format => 'single'
        },
        h6 => {
            start => '^^^^^^ ', block => 1, trim => 'both',
            line_format => 'single'
        },

        p => { block => 1, line_format => 'multi' },
        b => {
            start => '*', end => '*', line_format => 'single', trim => 'both'
        },
        strong => { alias => 'b' },
        i      => {
            start => '_', end => '_', line_format => 'single', trim => 'both'
        },
        em => { alias => 'i' },
        u  => {
            start => '_', end => '_', line_format => 'single', trim => 'both'
        },
        strike => {
            start => '-', end => '-', line_format => 'single', trim => 'both'
        },
        s => { alias => 'strike' },

        tt => {
            start => '`', end => '`', trim => 'both', line_format => 'single'
        },
        code => { alias => 'tt' },
        pre  => {
            start => "\n.pre\n", end => "\n.pre\n", line_prefix => '',
            line_format => 'blocks'
        },

        a => {
            replace => sub { shift->_link(@_) }
        },
        img => {
            replace => sub { shift->_image(@_) }
        },

        table => { block => 1, line_format => 'multi', trim => 'none' },
        tr    => { end   => " |\n" },
        td => { start => '| ', end => ' ' },
        th => { alias => 'td' },

        ul => { line_format => 'multi', block => 1 },
        ol => { alias       => 'ul' },
        li => { start => sub { shift->_li_start(@_) }, trim => 'leading' },
        dl => { alias => 'ul' },
        dt => { alias => 'li' },
        dd => { alias => 'li' },
    };
}

1;

__END__

=head1 NAME

Socialtext::EmailReceiver::en - Takes an incoming email and turns it into a wiki page

=head1 SYNOPSIS

  eval {
      Socialtext::EmailReceiver::en->receive_handle(
          handle    => \*STDIN,
          workspace => $workspace,
      );
  };

  # handle exceptions

=head1 DESCRIPTION

This module is used to take an incoming email and turn it into a wiki
page.

=head1 METHODS

This module provides two public class methods:

=head2 Socialtext::EmailReceiver::en->receive_handle()

This method requires two arguments, "handle" and "workspace". The
"handle" must be a file handle opened for reading and "workspace"
must be a C<Socialtext::Workspace> object.

The handle should be opened to a complete email message, including
headers.

=head2 Socialtext::EmailReceiver::en->receive_string()

This method requires two arguments, "string" and "workspace". The
"string" must be a complete email message, and "workspace" must be a
C<Socialtext::Workspace> object.

=head2 Exceptions

If for some reason the sender is not allowed to send email to the
specified workspace, a C<Socialtext::Exception::Auth> exception will
be thrown.

If there is a system error, a C<Socialtext::Exception::System>
exception will be thrown.

=head1 HOW IT WORKS

The process of turning an email into a wiki page is fairly
involved. It uses the Perl Email Project suite of modules to do the
heavy lifting of parsing emails. Here are the steps this module takes.

=head2 Email Cleanup

The module tries to clean any bogus data in the email so it is more
standards-compliant. This helps us avoid needless exceptions for

=head2 Determine Sender

The module parses the "From" header using C<Email::Address>, in order
to extract the sender's email address. If no From header is present,
or it does not contain a valid email address, a
C<Socialtext::Exception::Auth> exception will be thrown.

=head2 Check ACLs

The sender must have "email_in" permission for the workspace to which
the email is addressed, or a C<Socialtext::Exception::Auth> exception
will be thrown.

=head2 Get the User for the Address

If the sender's email does not match an existing user in the DBMS, we
create one. Otherwise we use the existing user row that matches the
sender's email.

This step is done after checking permissions in order to avoid
needlessly creating users.

=head2 Make or Retrieve a Wiki Page Object

An object is created for the wiki page to be updated or added. The
page title is the same as the email's subject, except we strip all
instances of "Fw:", "Fwd:" or "Re:' at the beginning of the subject first. We
also trim leading and trailing whitespace.

If the email has no subject we create one based on the email's sender
and the email's "Date" header.

=head2 Separate Email Body from Attachments, and Save Attachments

Any part with a "text/plain" or "text/html", and which does not have a
"Content-Disposition" header of "attachment" is considered to be a
body part. If the content type for "text/plain" part includes
"format=flowed", we use C<Text::Flowed> to reformat the message. We
also make sure all incoming email ends up being decoded to UTF-8
before it is saved.

An attachment is any I<other> part in a multipart message which has a
"Content-Disposition" header ("inline" I<or> "attachment"). We also
assume that images are always attachments, regardless of their
"Content-Disposition".

When saving attachments, we make sure that the process of saving will
not reduce available temp disk space below 50MB. If it would, we log
an error and skip the attachment. If saving it would reduce the space
below 500MB, we log an error but save the attachment anyway.

=head2 Scan Text Body for Commands

Incoming "text/plain" email bodies may contain commands as the first
non-empty lines of the email. Command names are
case-insensitive. Valid commands are:

=over 4

=item * Tag: Name1, Name2, Name3

Multiple tags can be separate by commas, or specified with multiple
"tag" commands. Note that "Category" can be used as a synonym for
"Tag".

=item * Append: Top, Bottom, or Replace

Overrides the workspace's default placement of an incoming email on an
existing page.

=item * Replace: 1

Same as "Append: Replace".

=back

=head2 Set Page Categories

All incoming email will be in the category "Email". We also set
categories based on any "CategorY' commands in the email's body, and
we check the "To" and "Cc" addresses to see if they include a category
as part of the address.

Any existing page categories are also preserved.

=head2 Save the Page

We update the page's content with the email's content. We also add the
From and Date headers to the page body like this:

 From: "Bob Smith" <mailto:bob.smith@example.com>
 Date: Thu, 05 Feb 2004 11:23:58 -0600

This is prepended to the page body. If the email included attachments
and they are not referred to in the page body (via WAFL), we add
appropriate WAFL to link to those attachments. These WAFLs come after
the header and before the email body.

Finally we save the page as a new revision.

=head3 HTML Body Handling

If an email has both plain text and HTML bodies, we check the
workspace's C<prefers_incoming_html_email> value to determine which
one to use.

When using an email's HTML body, it is converted to wikitext using
C<HTML::WikiConverter::Socialtext> and saved as the page body. If it
contains C<< <img> >> tags that refer to attachments with a "cid:"
URI, we convert those to image WAFL.

Regardless of how C<prefers_incoming_html_email> is set, we always
save a copy of the original HTML body as an attachment, so that it's
viewable with its original formatting.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005-2006 Socialtext, Inc., All Rights Reserved.

=cut
