package Socialtext::Rest::Echo;
# @COPYRIGHT@

use strict;
use warnings;

use base 'Socialtext::Rest';
use Socialtext::JSON qw/encode_json decode_json/;
use XML::Parser;

sub GET_html {
    my ( $self, $rest ) = @_;
    my $text = $self->text;
    $rest->header(-type => 'text/html');
    return "<html><body><b>$text</b></body></html>";
}

sub GET_json {
    my ( $self, $rest ) = @_;
    my $text = $self->text;
    $text =~ s/"/\\"/g;
    $rest->header(-type => 'application/json');
    return encode_json({text => $text});
}

sub GET_xml {
    my ( $self, $rest ) = @_;
    my $text = $self->text;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $rest->header(-type => 'text/xml');
    return <<XML
<?xml version="1.0" encoding="utf-8"?>
<st:xml xmlns:st="http://socialtext.net/xmlns/0.1">
    <st:text>$text</st:text>
</st:xml>
XML
}

sub GET_wikitext {
    my ( $self, $rest ) = @_;
    my $text = $self->text;
    $rest->header(-type => 'text/x.socialtext-wiki');
    return "^ Given Text\n.pre\n$text\n.pre\n";
}

sub POST_js {
    my ( $self, $rest ) = @_;
    warn "POST_js() called\n";
    my $msg
        = eval { decode_json( $self->rest->getContent() )->{message} };
    return $self->error( "400", "Bad Request", $@ ) if $@;
    return $self->_response( $self->text, $msg );
}

sub POST_xml {
    my ( $self, $rest ) = @_;
    my $msg = eval {
        XML::Parser->new( Style => 'Tree' )
                   ->parse( $self->rest->getContent() )
                   ->[1]->[4]->[2];
    };
    return $self->error( "400", "Bad Method", $@ ) if $@;
    return $self->_response( $self->text, $msg );
}

sub POST_cowsay {
    my ( $self, $rest ) = @_;
    my $msg = ( $self->rest->getContent() =~ /^\s*<\s*(.*?)\s*>\s*$/sm ) ? $1 : "";
    return $self->_response( $self->text, $msg );
}

sub _response {
    my $self = shift;
    my $ct = $self->rest->bct_hack( 'text/xml', 'application/json' );
    if ($ct eq 'text/xml') {
        return $self->_xml_response(@_);
    } else {
        return $self->_js_response(@_);
    }
}

sub _js_response {
    my ( $self, $text, $msg ) = @_;
    $msg = "" unless defined $msg;
    $self->rest->header(-type => 'application/json');
    return encode_json( { text => $text, message => $msg } );
}

sub _xml_response {
    my ( $self, $text, $msg ) = @_;
    $msg = "" unless defined $msg;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $msg =~ s/&/&amp;/g;
    $msg =~ s/</&lt;/g;
    $self->rest->header(-type => 'text/xml');
    return<<XML;
<?xml version="1.0" encoding="utf-8"?>
<st:xml xmlns:st="http://socialtext.net/xmlns/0.1">
    <st:text>$text</st:text>
    <st:message>$msg</st:message>
</st:xml>
XML
}

sub allowed_methods { 'GET, HEAD' }

1;
