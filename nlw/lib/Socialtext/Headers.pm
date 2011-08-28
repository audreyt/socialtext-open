# @COPYRIGHT@
package Socialtext::Headers;
use strict;
use warnings;

use base 'Socialtext::Base';
use Socialtext::HTTP ':codes';

use Class::Field qw( field );

sub class_id { 'headers' }

field content_type => 'text/html';
field content_disposition => undef;
field content_length => undef;
field charset => 'UTF-8';
field expires => 'now';
field pragma => 'no-cache';
field cache_control => 'no-store, no-cache, must-revalidate, post-check=0, pre-check=0';
field last_modified => -init => 'scalar gmtime';
field 'location';
field status => HTTP_200_OK;

# Erase certain cache headers which will prevent IE 6/7 from downloading
# attachments under SSL.
# 
# See: http://support.microsoft.com/default.aspx?scid=kb;en-us;812935
sub erase_cache_headers {
    my $self = shift;
    $self->cache_control(undef);
    $self->pragma(undef);
}

sub add_attachment {
    my ( $self, %args ) = @_;
    $self->content_disposition("attachment; filename=\"$args{filename}\"");
    $self->content_type( $args{type} || 'text/html' );
    $self->content_length( $args{len} );
    if (defined $args{charset} ) {
        $self->charset( $args{charset} );
    }
    $self->erase_cache_headers();
}

# XXX not really print at all, but maintaining
# an old interface. this sets the headers in
# the header object.
sub print {
    my $self = shift;
    my $content_type = $self->content_type;
    $content_type .= '; charset=' . $self->charset
      if $content_type =~ /^text/;
    my %headers = (
        $self->hub->rest->header,   # preserve any existing headers
        -type => $content_type,
    );
    for my $header (qw(Content-Length Content-disposition Expires Pragma 
                      Cache-control Last-modified Location Status)) {
        my $field = lc $header;
        $field =~ tr/-/_/;

        # We check existence rather than definedness here because if someone
        # explicitly sets a header to undef, they mean for that to be
        # removed from the set of headers (e.g., as in erase_cache_headers
        # above).
        $headers{'-' . $header} = $self->{$field}
            if exists $self->{$field};
    }
    $self->hub->rest->header(%headers);
}

# XXX: this redirect is often bogus (a partial rather than full path)
sub redirect {
    my $self = shift;
    if (@_) {
        $self->location(shift);
        $self->status(HTTP_302_Found);
    }
    return $self->location;
}

1;
