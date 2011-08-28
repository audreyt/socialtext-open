package Socialtext::Rest::Entity;
# @COPYRIGHT@

use warnings;
use strict;

=head1 NAME

Socialtext::Rest::Entity - Superclass for representations of a single object.

=head1 SEE ALSO

L<Socialtext::Rest::Collection>

=cut

use Socialtext::JSON;
use Socialtext::Encode;
use YAML qw/Dump/;
use base 'Socialtext::Rest';
use Socialtext::HTTP ':codes';


sub allowed_methods {'GET, HEAD, PUT'}

sub attribute_table_row {
    my ( $self, $name, $value ) = @_;

    $value = "<a href='$value'>$value</a>" if $name =~ /uri$/;

    if (ref $value eq 'ARRAY') {
        $value = join('</td><td>', @$value);
    }

    $value = '' unless defined $value;
    return "<tr><td>$name</td><td>$value</td></tr>\n";
}

{
    no warnings 'once';
    *GET_text = _make_getter(\&resource_to_text, 'text/plain');
    *GET_html = _make_getter(\&resource_to_html, 'text/html');
    *GET_json = _make_getter(\&resource_to_json, 'application/json');
    *GET_yaml = _make_getter(
        \&Socialtext::Rest::resource_to_yaml, 'text/x-yaml');
    *PUT_json = _make_putter(\&json_to_resource);
}

# REVIEW: This is cut-paste from Socialtext::Rest::Collection.
sub _make_getter {
    my ( $sub, $content_type ) = @_;
    return sub {
        my ( $self, $rest ) = @_;

        $self->if_authorized(
            'GET',
            sub {
                if ( defined( my $resource = $self->get_resource($rest) ) ) {
                    $rest->header(
                        -status        => HTTP_200_OK,
                        -type          => $content_type . '; charset=UTF-8',
                        -Last_Modified => $self->make_http_date(
                            $self->last_modified($resource)
                        ),
                        $rest->header(),
                    );
                    return $self->$sub($resource);
                }
                return $self->http_404($rest);
            }
        );
    };
}

sub last_modified { time }

# FIXME: No permissions checking here YET as its not used
# and what permission to check may need to be passed in as
# an argument. The same applies to _make_poster below.
sub _make_putter {
    my ( $sub ) = @_;
    return sub {
        my ( $self, $rest ) = @_;
        my $content = eval {
            my ( $location, $type, $content )
                = $self->put_generic( $self->$sub( $rest->getContent ) );
            my $status =
                  $location ? HTTP_201_Created
                : $content  ? HTTP_200_OK
                : HTTP_204_No_Content;
            $rest->header(
                -status => $status,
                $type     ? ( -type     => $type )     : (),
                $location ? ( -Location => $location ) : () );
            return $content;
        };
        if ($@) {
            return $self->_put_or_post_error($rest, $@);
        }
        return $content;
    }
}

# see also: _make_putter
sub _make_poster {
    my ( $sub ) = @_;
    return sub {
        my ( $self, $rest ) = @_;
        my $content = eval {
            my ( $type, $content )
                = $self->post_generic( $self->$sub( $rest->getContent ) );
            my $status = $content  ? HTTP_200_OK : HTTP_204_No_Content;
            $rest->header(
                -status => $status,
                $type     ? ( -type     => $type )     : (),
            );
            return $content;
        };
        if ($@) {
            return $self->_put_or_post_error($rest, $@);
        }
        return $content;
    }
}

sub _put_or_post_error {
    my $self = shift;
    my $rest = shift;
    my $error = shift;
    my %headers = $rest->header;
    if (!%headers || !$headers{-status} || 
        $headers{-status} =~ /^2../) 
    {
        $rest->header(
            -status => HTTP_400_Bad_Request
            -type   => 'text/plain' 
        );
    }
    warn "Error in ST::Rest::Entity $error";
    ($error) = split "\n", $error;
    return $error;
}

sub resource_to_text {
    my ( $self, $resource ) = @_;

    my $name = $self->entity_name;

    return $name . ': '
        . join( ', ', map {"$_:$resource->{$_}"} keys %$resource );
}

sub resource_to_html {
    my ( $self, $resource ) = @_;

    my $name = $self->entity_name;
    my $body = join '',
        map { $self->attribute_table_row( $_, $resource->{$_} ) }
            keys %$resource;
    return ( << "END_OF_HEADER" . $body . << "END_OF_TRAILER" );
<html>
<head>
<title>$name</title>
</head>
<body>
<h1>$name</h1>
<table>
END_OF_HEADER
</table>
</body>
</html>
END_OF_TRAILER
}

sub resource_to_json { encode_json($_[1]) }
sub json_to_resource { decode_json($_[1]) }

# decodes x-www-form-encoded data into a resource (i.e. a hash)
sub form_to_resource {
    my $self = shift;
    my $form_data = shift;

    my $resource = {};

    my $cgi = Socialtext::CGI::Scrubbed->new($form_data);
    my %params = $cgi->Vars();
    foreach my $key (keys %params) {
        my $res = $resource;
        my $res_key = $key;

        # resolve dotted names to nested hashes
        while ($res_key =~ /^([^.]+)\.(.+)$/) {
            my ($before,$after) = ($1,$2);
            $res->{$before} ||= {};
            $res = $res->{$before};
            $res_key = $after;
        }

        $res->{$res_key} = Socialtext::Encode::guess_decode($params{$key});
    }

    return $resource;
}

1;
