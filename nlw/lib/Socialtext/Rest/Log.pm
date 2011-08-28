package Socialtext::Rest::Log;
# @COPYRIGHT@

use strict;
use warnings;

use base 'Socialtext::Rest';
use Socialtext::JSON qw/encode_json/;
use XML::Parser;
use Socialtext::Log qw(st_log);

sub POST_form {
    my ( $self, $rest ) = @_;
    st_log->info("LOG,". $self->rest->getContent());
    $self->rest->header(-type => 'application/json');
    return "[]";
}


sub allowed_methods { 'POST' }


1;
